//+------------------------------------------------------------------+
//|                                            PerceptraderStyle.mq5  |
//|   Perceptron (neural-weighted) signal + controlled GRID  (MT5)  |
//|                                                                  |
//|   INDEPENDENT, clean-room implementation inspired by the         |
//|   publicly described "Artificial Neural Network / perceptron     |
//|   driven grid trading system" approach. The perceptron here is   |
//|   a transparent weighted sum of normalized indicators (you can   |
//|   tune the weights). NOT a copy of, nor affiliated with, any     |
//|   commercial product. Use at your own risk. Test on DEMO first.  |
//+------------------------------------------------------------------+
#property copyright "Open implementation - educational use"
#property version   "1.00"
#property strict
#property description "Perceptron-weighted multi-indicator signal feeding a controlled grid. Tunable input weights act as the 'neural' layer."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//==================================================================
//  INPUTS
//==================================================================
input group "=== General ==="
input long            InpMagic          = 20240613;  // Magic number
input string          InpComment        = "PERCEP";  // Trade comment
input int             InpSlippagePoints = 30;         // Max slippage (points)
input int             InpMaxSpreadPts   = 30;         // Max spread (points)

input group "=== Perceptron Inputs (timeframe + indicators) ==="
input ENUM_TIMEFRAMES InpTF             = PERIOD_M5;  // Working timeframe
input int             InpRsiPeriod      = 14;         // RSI period
input int             InpMaFast         = 12;         // Fast EMA (slope/momentum)
input int             InpMaSlow         = 48;         // Slow EMA (trend)
input int             InpMomPeriod      = 14;         // Momentum period
input int             InpCciPeriod      = 20;         // CCI period

input group "=== Perceptron Weights (the 'neural' layer) ==="
input double          InpW_Rsi          = 1.0;        // Weight: RSI reversion
input double          InpW_MaTrend      = 1.0;        // Weight: EMA trend
input double          InpW_Momentum     = 0.8;        // Weight: momentum
input double          InpW_Cci          = 0.8;        // Weight: CCI
input double          InpBias           = 0.0;        // Bias term
input double          InpSignalThreshold = 0.35;      // |output| must exceed this to act (0..1)

input group "=== Grid (controlled) ==="
input double          InpGridStepPts    = 250;        // Grid step (points)
input int             InpMaxTrades      = 8;          // Max orders per basket
input double          InpLotMultiplier  = 1.3;        // Lot multiplier per level

input group "=== Lot ==="
input double          InpFirstLot       = 0.01;       // First-order lot
input double          InpMaxLot         = 4.0;        // Hard lot cap

input group "=== Basket Exit ==="
input double          InpTakeProfitPts  = 300;        // TP from avg price (points)
input double          InpBasketTPMoney  = 0;          // Money TP ($). 0 = off

input group "=== Safety ==="
input double          InpMaxDrawdownPct = 25.0;       // Equity DD% guard (0=off)

//==================================================================
//  GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;
int      hRsi = INVALID_HANDLE, hFast = INVALID_HANDLE, hSlow = INVALID_HANDLE;
int      hMom = INVALID_HANDLE, hCci  = INVALID_HANDLE;
double   g_point;
double   g_startEquity = 0.0;
bool     g_paused = false;

//==================================================================
//  INIT / DEINIT
//==================================================================
int OnInit()
  {
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.LogLevel(LOG_LEVEL_ERRORS);

   hRsi  = iRSI(_Symbol, InpTF, InpRsiPeriod, PRICE_CLOSE);
   hFast = iMA(_Symbol, InpTF, InpMaFast, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, InpTF, InpMaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hMom  = iMomentum(_Symbol, InpTF, InpMomPeriod, PRICE_CLOSE);
   hCci  = iCCI(_Symbol, InpTF, InpCciPeriod, PRICE_TYPICAL);
   if(hRsi==INVALID_HANDLE||hFast==INVALID_HANDLE||hSlow==INVALID_HANDLE||hMom==INVALID_HANDLE||hCci==INVALID_HANDLE)
     { Print("Indicator handle error"); return(INIT_FAILED); }

   g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("PerceptraderStyle initialized on ", _Symbol);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(hRsi !=INVALID_HANDLE) IndicatorRelease(hRsi);
   if(hFast!=INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow!=INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hMom !=INVALID_HANDLE) IndicatorRelease(hMom);
   if(hCci !=INVALID_HANDLE) IndicatorRelease(hCci);
  }

//==================================================================
//  MAIN TICK
//==================================================================
void OnTick()
  {
   if(!ManageDrawdown()) return;
   ManageBasket();

   if(!IsNewBar(InpTF)) return;
   if(g_paused) return;
   if(CurrentSpreadPoints() > InpMaxSpreadPts) return;

   ManageGrid();
  }

//==================================================================
//  PERCEPTRON: weighted sum of normalized indicator inputs -> tanh
//  Output in (-1, +1). Positive => buy bias, negative => sell bias.
//==================================================================
double Perceptron()
  {
   double rsi[1], fast[2], slow[1], mom[1], cci[1];
   if(CopyBuffer(hRsi, 0, 1, 1, rsi)  < 1) return 0;
   if(CopyBuffer(hFast,0, 1, 2, fast) < 2) return 0;
   if(CopyBuffer(hSlow,0, 1, 1, slow) < 1) return 0;
   if(CopyBuffer(hMom, 0, 1, 1, mom)  < 1) return 0;
   if(CopyBuffer(hCci, 0, 1, 1, cci)  < 1) return 0;

   // Normalize each input roughly into [-1, +1]
   double xRsi   = (50.0 - rsi[0]) / 50.0;                 // oversold(+) / overbought(-)
   double xTrend = (fast[1] - slow[0]) / (slow[0] * 0.01); // EMA spread in % units
   xTrend = MathMax(-1.0, MathMin(1.0, xTrend));
   double xMom   = (mom[0] - 100.0) / 1.0;                 // momentum around 100
   xMom = MathMax(-1.0, MathMin(1.0, xMom));
   double xCci   = MathMax(-1.0, MathMin(1.0, cci[0] / 200.0));

   double z = InpBias
            + InpW_Rsi      * xRsi
            + InpW_MaTrend   * xTrend
            + InpW_Momentum  * xMom
            + InpW_Cci       * xCci;

   // tanh activation
   double e2 = MathExp(-2.0 * z);
   double out = (1.0 - e2) / (1.0 + e2);
   return out;
  }

int Signal()
  {
   double out = Perceptron();
   if(out >=  InpSignalThreshold) return  1;
   if(out <= -InpSignalThreshold) return -1;
   return 0;
  }

//==================================================================
//  GRID
//==================================================================
void ManageGrid()
  {
   int count = CountPositions();
   if(count >= InpMaxTrades) return;

   if(count == 0)
     {
      int sig = Signal();
      if(sig > 0) OpenTrade(ORDER_TYPE_BUY,  NextLot(0));
      else if(sig < 0) OpenTrade(ORDER_TYPE_SELL, NextLot(0));
      return;
     }

   int    dir  = BasketDirection();
   double step = InpGridStepPts * g_point;
   double last = LastEntryPrice(dir);
   if(dir == 0 || last <= 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(dir > 0) { if(ask <= last - step) OpenTrade(ORDER_TYPE_BUY,  NextLot(count)); }
   else        { if(bid >= last + step) OpenTrade(ORDER_TYPE_SELL, NextLot(count)); }
  }

void ManageBasket()
  {
   int count = CountPositions();
   if(count == 0) return;

   double profit = BasketProfitMoney();
   if(InpBasketTPMoney > 0 && profit >= InpBasketTPMoney) { CloseBasket("Money TP"); return; }

   int    dir = BasketDirection();
   double avg = BasketAvgPrice();
   if(dir == 0 || avg <= 0) return;
   double tpPx = (dir > 0) ? avg + InpTakeProfitPts * g_point : avg - InpTakeProfitPts * g_point;
   double cur  = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if((dir > 0 && cur >= tpPx) || (dir < 0 && cur <= tpPx)) CloseBasket("Basket TP");
  }

//==================================================================
//  ORDERS / LOT
//==================================================================
bool OpenTrade(ENUM_ORDER_TYPE type, double lot)
  {
   lot = NormalizeLot(lot);
   if(lot <= 0) return false;
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool ok = trade.PositionOpen(_Symbol, type, lot, price, 0, 0, InpComment);
   if(!ok) PrintFormat("Open failed err=%d (%s)", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return ok;
  }

void CloseBasket(string reason)
  {
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!posinfo.SelectByTicket(t)) continue;
      if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;
      if(trade.PositionClose(t)) closed++;
     }
   if(closed > 0) PrintFormat("Basket closed (%d) | %s", closed, reason);
  }

double NextLot(int idx) { return NormalizeLot(InpFirstLot * MathPow(InpLotMultiplier, idx)); }

double NormalizeLot(double lot)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0) stepLot = 0.01;
   lot = MathFloor(lot / stepLot + 0.0000001) * stepLot;
   double cap = MathMin(maxLot, InpMaxLot);
   if(lot > cap) lot = cap;
   if(lot < minLot) lot = minLot;
   return NormalizeDouble(lot, 2);
  }

//==================================================================
//  HELPERS
//==================================================================
int CountPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!posinfo.SelectByTicket(t)) continue;
      if(posinfo.Symbol() == _Symbol && posinfo.Magic() == InpMagic) c++;
     }
   return c;
  }

int BasketDirection()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!posinfo.SelectByTicket(t)) continue;
      if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;
      return (posinfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
     }
   return 0;
  }

double BasketProfitMoney()
  {
   double p = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!posinfo.SelectByTicket(t)) continue;
      if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;
      p += posinfo.Profit() + posinfo.Swap() + posinfo.Commission();
     }
   return p;
  }

double BasketAvgPrice()
  {
   double svp = 0.0, sv = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!posinfo.SelectByTicket(t)) continue;
      if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;
      svp += posinfo.PriceOpen() * posinfo.Volume();
      sv  += posinfo.Volume();
     }
   return (sv > 0) ? svp / sv : 0.0;
  }

double LastEntryPrice(int dir)
  {
   double res = -1;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!posinfo.SelectByTicket(t)) continue;
      if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;
      double px = posinfo.PriceOpen();
      if(res < 0) { res = px; continue; }
      if(dir > 0) res = MathMin(res, px);
      else        res = MathMax(res, px);
     }
   return res;
  }

bool ManageDrawdown()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_startEquity) g_startEquity = equity;
   if(InpMaxDrawdownPct > 0 && g_startEquity > 0)
     {
      double dd = (g_startEquity - equity) / g_startEquity * 100.0;
      if(dd >= InpMaxDrawdownPct)
        { if(CountPositions() > 0) CloseBasket("Max DD protection"); g_paused = true; return false; }
     }
   if(g_paused && CountPositions() == 0) { g_paused = false; g_startEquity = equity; }
   return true;
  }

int CurrentSpreadPoints() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); }

bool IsNewBar(ENUM_TIMEFRAMES tf)
  {
   static datetime last = 0;
   datetime cur = (datetime)SeriesInfoInteger(_Symbol, tf, SERIES_LASTBAR_DATE);
   if(cur != last) { last = cur; return true; }
   return false;
  }
//+------------------------------------------------------------------+
