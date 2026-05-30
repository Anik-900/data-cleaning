//+------------------------------------------------------------------+
//|                                                AuraBlackStyle.mq5 |
//|   Multi-Layer Perceptron (MLP) neural Expert Advisor for MT5    |
//|                                                                  |
//|   INDEPENDENT, clean-room implementation inspired by the         |
//|   publicly described "trained multilayer perceptron neural net   |
//|   with a hard stop loss & take profit on every position, no      |
//|   martingale / no grid" approach. The network here is a          |
//|   transparent, hand-tunable 4-3-1 MLP (tanh hidden, tanh out).   |
//|   NOT a copy of, nor affiliated with, any commercial product.    |
//|   Use at your own risk. ALWAYS test on DEMO first.               |
//+------------------------------------------------------------------+
#property copyright "Open implementation - educational use"
#property version   "1.00"
#property strict
#property description "MLP (4-3-1, tanh) neural signal over normalized indicators. Hard SL/TP each trade, single position, no martingale."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//==================================================================
//  INPUTS
//==================================================================
input group "=== General ==="
input long            InpMagic          = 20240615;  // Magic number
input string          InpComment        = "AURA";    // Trade comment
input int             InpSlippagePoints = 30;         // Max slippage (points)
input int             InpMaxSpreadPts   = 40;         // Max spread (points)

input group "=== Network Inputs ==="
input ENUM_TIMEFRAMES InpTF             = PERIOD_H1;  // Working timeframe
input int             InpRsiPeriod      = 14;         // RSI period (input x1)
input int             InpMaFast         = 10;         // Fast EMA (input x2 = trend)
input int             InpMaSlow         = 40;         // Slow EMA (input x2 = trend)
input int             InpStochK         = 14;         // Stochastic %K (input x3)
input int             InpCciPeriod      = 20;         // CCI period (input x4)

input group "=== MLP Hidden Layer Weights (4 inputs -> 3 hidden) ==="
input double          InpH1_w1 =  1.0; input double InpH1_w2 =  1.2; input double InpH1_w3 = -0.5; input double InpH1_w4 =  0.6; input double InpH1_b = 0.0;
input double          InpH2_w1 = -0.8; input double InpH2_w2 =  0.9; input double InpH2_w3 =  1.0; input double InpH2_w4 = -0.4; input double InpH2_b = 0.0;
input double          InpH3_w1 =  0.5; input double InpH3_w2 = -0.6; input double InpH3_w3 =  0.7; input double InpH3_w4 =  1.1; input double InpH3_b = 0.0;

input group "=== MLP Output Layer Weights (3 hidden -> 1 output) ==="
input double          InpO_w1  =  1.0; input double InpO_w2  =  1.0; input double InpO_w3 = 1.0; input double InpO_b = 0.0;
input double          InpThreshold = 0.40;            // |output| must exceed this to trade (0..1)

input group "=== Lot / Risk ==="
input bool            InpAutoLot        = true;       // Risk-based lot sizing
input double          InpRiskPercent    = 0.5;        // Risk % per trade
input double          InpManualLot      = 0.01;       // Manual lot (AutoLot=false)
input double          InpMaxLot         = 4.0;        // Hard lot cap

input group "=== Stops (points) ==="
input double          InpStopLossPts    = 400;        // Stop loss (points)
input double          InpTakeProfitPts  = 500;        // Take profit (points)
input bool            InpUseTrailing    = true;       // Trailing stop
input double          InpTrailStartPts  = 250;        // Start trailing after (points)
input double          InpTrailDistPts   = 200;        // Trailing distance (points)

input group "=== Filters ==="
input int             InpMaxPositions   = 1;          // Max simultaneous positions (no grid)
input double          InpMaxDrawdownPct = 20.0;       // Equity DD% guard (0=off)

//==================================================================
//  GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;
int      hRsi=INVALID_HANDLE, hFast=INVALID_HANDLE, hSlow=INVALID_HANDLE, hStoch=INVALID_HANDLE, hCci=INVALID_HANDLE;
double   g_point;
int      g_digits;
double   g_startEquity = 0.0;
bool     g_paused = false;

//==================================================================
//  INIT / DEINIT
//==================================================================
int OnInit()
  {
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.LogLevel(LOG_LEVEL_ERRORS);

   hRsi   = iRSI(_Symbol, InpTF, InpRsiPeriod, PRICE_CLOSE);
   hFast  = iMA(_Symbol, InpTF, InpMaFast, 0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, InpTF, InpMaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hStoch = iStochastic(_Symbol, InpTF, InpStochK, 3, 3, MODE_SMA, STO_LOWHIGH);
   hCci   = iCCI(_Symbol, InpTF, InpCciPeriod, PRICE_TYPICAL);
   if(hRsi==INVALID_HANDLE||hFast==INVALID_HANDLE||hSlow==INVALID_HANDLE||hStoch==INVALID_HANDLE||hCci==INVALID_HANDLE)
     { Print("Indicator handle error"); return(INIT_FAILED); }

   g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("AuraBlackStyle initialized on ", _Symbol);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(hRsi  !=INVALID_HANDLE) IndicatorRelease(hRsi);
   if(hFast !=INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow !=INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hCci  !=INVALID_HANDLE) IndicatorRelease(hCci);
  }

//==================================================================
//  MAIN TICK
//==================================================================
void OnTick()
  {
   if(!ManageDrawdown()) return;
   ManageTrailing();

   if(!IsNewBar(InpTF)) return;
   if(g_paused) return;
   if(CurrentSpreadPoints() > InpMaxSpreadPts) return;
   if(CountPositions() >= InpMaxPositions) return;

   int sig = Signal();
   if(sig > 0)      OpenTrade(ORDER_TYPE_BUY);
   else if(sig < 0) OpenTrade(ORDER_TYPE_SELL);
  }

//==================================================================
//  MLP forward pass (4 inputs -> 3 hidden tanh -> 1 output tanh)
//==================================================================
double Tanh(double z)
  {
   double e2 = MathExp(-2.0 * z);
   return (1.0 - e2) / (1.0 + e2);
  }

double MLP()
  {
   double rsi[1], fast[1], slow[1], stoch[1], cci[1];
   if(CopyBuffer(hRsi,  0, 1, 1, rsi)   < 1) return 0;
   if(CopyBuffer(hFast, 0, 1, 1, fast)  < 1) return 0;
   if(CopyBuffer(hSlow, 0, 1, 1, slow)  < 1) return 0;
   if(CopyBuffer(hStoch,0, 1, 1, stoch) < 1) return 0;  // %K main buffer
   if(CopyBuffer(hCci,  0, 1, 1, cci)   < 1) return 0;

   // Normalize inputs roughly to [-1, +1]
   double x1 = (rsi[0] - 50.0) / 50.0;                            // RSI
   double x2 = MathMax(-1.0, MathMin(1.0, (fast[0]-slow[0])/(slow[0]*0.01))); // EMA trend %
   double x3 = (stoch[0] - 50.0) / 50.0;                          // Stochastic
   double x4 = MathMax(-1.0, MathMin(1.0, cci[0] / 200.0));       // CCI

   // Hidden layer (3 neurons, tanh)
   double h1 = Tanh(InpH1_b + InpH1_w1*x1 + InpH1_w2*x2 + InpH1_w3*x3 + InpH1_w4*x4);
   double h2 = Tanh(InpH2_b + InpH2_w1*x1 + InpH2_w2*x2 + InpH2_w3*x3 + InpH2_w4*x4);
   double h3 = Tanh(InpH3_b + InpH3_w1*x1 + InpH3_w2*x2 + InpH3_w3*x3 + InpH3_w4*x4);

   // Output layer (tanh) -> (-1, +1)
   double out = Tanh(InpO_b + InpO_w1*h1 + InpO_w2*h2 + InpO_w3*h3);
   return out;
  }

int Signal()
  {
   double out = MLP();
   if(out >=  InpThreshold) return  1;
   if(out <= -InpThreshold) return -1;
   return 0;
  }

//==================================================================
//  ORDERS (hard SL/TP every trade)
//==================================================================
bool OpenTrade(ENUM_ORDER_TYPE type)
  {
   double lot = NormalizeLot(CalcLot(InpStopLossPts));
   if(lot <= 0) return false;
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl, tp;
   if(type == ORDER_TYPE_BUY)
     { sl = price - InpStopLossPts * g_point; tp = price + InpTakeProfitPts * g_point; }
   else
     { sl = price + InpStopLossPts * g_point; tp = price - InpTakeProfitPts * g_point; }
   sl = NormalizeDouble(sl, g_digits);
   tp = NormalizeDouble(tp, g_digits);

   bool ok = trade.PositionOpen(_Symbol, type, lot, price, sl, tp, InpComment);
   if(!ok) PrintFormat("Open failed err=%d (%s)", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return ok;
  }

void ManageTrailing()
  {
   if(!InpUseTrailing) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!posinfo.SelectByTicket(t)) continue;
      if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;
      double open = posinfo.PriceOpen();
      double sl   = posinfo.StopLoss();
      if(posinfo.PositionType() == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid - open >= InpTrailStartPts * g_point)
           {
            double newSL = NormalizeDouble(bid - InpTrailDistPts * g_point, g_digits);
            if(newSL > sl || sl == 0.0) trade.PositionModify(t, newSL, posinfo.TakeProfit());
           }
        }
      else
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(open - ask >= InpTrailStartPts * g_point)
           {
            double newSL = NormalizeDouble(ask + InpTrailDistPts * g_point, g_digits);
            if(newSL < sl || sl == 0.0) trade.PositionModify(t, newSL, posinfo.TakeProfit());
           }
        }
     }
  }

//==================================================================
//  LOT / HELPERS
//==================================================================
double CalcLot(double slPoints)
  {
   if(!InpAutoLot) return NormalizeLot(InpManualLot);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;
   double tickVal   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSz <= 0 || slPoints <= 0) return NormalizeLot(InpManualLot);
   double lossPerLot = (slPoints * g_point / tickSz) * tickVal;
   if(lossPerLot <= 0) return NormalizeLot(InpManualLot);
   return NormalizeLot(riskMoney / lossPerLot);
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

void CloseAll(string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!posinfo.SelectByTicket(t)) continue;
      if(posinfo.Symbol() == _Symbol && posinfo.Magic() == InpMagic) trade.PositionClose(t);
     }
  }

bool ManageDrawdown()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_startEquity) g_startEquity = equity;
   if(InpMaxDrawdownPct > 0 && g_startEquity > 0)
     {
      double dd = (g_startEquity - equity) / g_startEquity * 100.0;
      if(dd >= InpMaxDrawdownPct) { CloseAll("Max DD protection"); g_paused = true; return false; }
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
