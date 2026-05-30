//+------------------------------------------------------------------+
//|                                                WakaWakaStyle.mq5  |
//|   Mean-reversion GRID + martingale Expert Advisor (MT5)          |
//|                                                                  |
//|   INDEPENDENT, clean-room implementation inspired by the         |
//|   publicly described "RSI/ATR mean-reversion grid with smart     |
//|   basket close" approach. Designed for ranging FX pairs (e.g.    |
//|   AUDCAD, AUDNZD, NZDCAD) on M15. NOT a copy of, nor affiliated  |
//|   with, any commercial product. Test on DEMO first.             |
//+------------------------------------------------------------------+
#property copyright "Open implementation - educational use"
#property version   "1.00"
#property strict
#property description "RSI/ATR mean-reversion grid + martingale with smart basket take-profit. For ranging pairs on M15."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//==================================================================
//  INPUTS
//==================================================================
input group "=== General ==="
input long            InpMagic          = 20240611;  // Magic number
input string          InpComment        = "WAKA";    // Trade comment
input int             InpSlippagePoints = 30;         // Max slippage (points)
input int             InpMaxSpreadPts   = 35;         // Max spread (points)

input group "=== Mean-Reversion Signal ==="
input ENUM_TIMEFRAMES InpTF             = PERIOD_M15; // Working timeframe
input int             InpRsiPeriod      = 14;         // RSI period
input double          InpRsiBuyLevel    = 30.0;       // Buy when RSI below this (oversold)
input double          InpRsiSellLevel   = 70.0;       // Sell when RSI above this (overbought)

input group "=== Grid (ATR-spaced averaging) ==="
input int             InpAtrPeriod      = 14;         // ATR period for grid spacing
input double          InpAtrStepMult    = 1.5;        // Grid step = ATR * this
input double          InpMinStepPts     = 150;        // Minimum grid step (points)
input int             InpMaxTrades      = 12;         // Max orders per basket
input double          InpLotMultiplier  = 1.4;        // Martingale multiplier per level

input group "=== Lot ==="
input double          InpFirstLot       = 0.01;       // First-order lot
input double          InpMaxLot         = 5.0;        // Hard lot cap

input group "=== Basket Exit ==="
input double          InpTargetPerLot   = 200;        // TP target in points from avg price
input double          InpBasketTPMoney  = 0;          // Money TP ($). 0 = off
input bool            InpUseBreakEven   = true;       // Move target after grid expands
input double          InpBreakEvenShrink = 0.5;       // After level>half, shrink TP target by this factor

input group "=== Safety ==="
input double          InpMaxDrawdownPct = 30.0;       // Equity DD% guard (0=off)

//==================================================================
//  GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;
int      hRsi = INVALID_HANDLE;
int      hAtr = INVALID_HANDLE;
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

   hRsi = iRSI(_Symbol, InpTF, InpRsiPeriod, PRICE_CLOSE);
   hAtr = iATR(_Symbol, InpTF, InpAtrPeriod);
   if(hRsi == INVALID_HANDLE || hAtr == INVALID_HANDLE)
     { Print("Indicator handle error"); return(INIT_FAILED); }

   g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("WakaWakaStyle initialized on ", _Symbol);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(hRsi != INVALID_HANDLE) IndicatorRelease(hRsi);
   if(hAtr != INVALID_HANDLE) IndicatorRelease(hAtr);
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
//  GRID LOGIC
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
   double step = GridStep();
   double last = LastEntryPrice(dir);
   if(dir == 0 || last <= 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(dir > 0)  // BUY basket -> average down
     { if(ask <= last - step) OpenTrade(ORDER_TYPE_BUY, NextLot(count)); }
   else         // SELL basket -> average up
     { if(bid >= last + step) OpenTrade(ORDER_TYPE_SELL, NextLot(count)); }
  }

int Signal()
  {
   double rsi[1];
   if(CopyBuffer(hRsi, 0, 1, 1, rsi) < 1) return 0;   // last closed bar
   if(rsi[0] <= InpRsiBuyLevel)  return  1;
   if(rsi[0] >= InpRsiSellLevel) return -1;
   return 0;
  }

double GridStep()
  {
   double atr[1];
   double minStep = InpMinStepPts * g_point;
   if(CopyBuffer(hAtr, 0, 0, 1, atr) == 1 && atr[0] > 0)
      return MathMax(atr[0] * InpAtrStepMult, minStep);
   return minStep;
  }

//==================================================================
//  BASKET EXIT
//==================================================================
void ManageBasket()
  {
   int count = CountPositions();
   if(count == 0) return;

   double profit = BasketProfitMoney();
   if(InpBasketTPMoney > 0 && profit >= InpBasketTPMoney)
     { CloseBasket("Money TP"); return; }

   int    dir = BasketDirection();
   double avg = BasketAvgPrice();
   if(dir == 0 || avg <= 0) return;

   double target = InpTargetPerLot;
   if(InpUseBreakEven && count > InpMaxTrades / 2)
      target *= InpBreakEvenShrink;   // get out faster once the grid is large

   double tpPx = (dir > 0) ? avg + target * g_point : avg - target * g_point;
   double cur  = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if((dir > 0 && cur >= tpPx) || (dir < 0 && cur <= tpPx))
      CloseBasket("Basket TP");
  }

//==================================================================
//  ORDERS
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

double NextLot(int idx)
  {
   double lot = InpFirstLot * MathPow(InpLotMultiplier, idx);
   return NormalizeLot(lot);
  }

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
