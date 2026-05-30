//+------------------------------------------------------------------+
//|                                          DarwinEvolutionStyle.mq5 |
//|   Multi-indicator CONFLUENCE Expert Advisor for MT5             |
//|                                                                  |
//|   INDEPENDENT, clean-room implementation inspired by the         |
//|   publicly described "multi-strategy confluence" approach that   |
//|   combines a Bollinger-band bounce, horizontal support/          |
//|   resistance levels and a higher-timeframe trend filter before   |
//|   taking a trade. NOT a copy of, nor affiliated with, any        |
//|   commercial product. Use at your own risk. Test on DEMO first.  |
//+------------------------------------------------------------------+
#property copyright "Open implementation - educational use"
#property version   "1.00"
#property strict
#property description "Confluence EA: Bollinger bounce + S/R levels + higher-TF trend must agree. Fixed SL/TP, trailing, no martingale."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//==================================================================
//  INPUTS
//==================================================================
input group "=== General ==="
input long            InpMagic          = 20240614;  // Magic number
input string          InpComment        = "DARWIN";  // Trade comment
input int             InpSlippagePoints = 30;         // Max slippage (points)
input int             InpMaxSpreadPts   = 40;         // Max spread (points)

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES InpEntryTF        = PERIOD_M15; // Entry timeframe
input ENUM_TIMEFRAMES InpTrendTF        = PERIOD_H4;  // Higher-TF trend filter

input group "=== Confluence: Bollinger bounce ==="
input int             InpBbPeriod       = 20;         // Bollinger period
input double          InpBbDev          = 2.0;        // Bollinger deviations

input group "=== Confluence: Support / Resistance ==="
input int             InpSrLookback     = 50;         // Bars for S/R high/low
input double          InpSrTolerancePts = 120;        // Distance to S/R to count as 'near' (points)

input group "=== Confluence: Trend filter ==="
input int             InpTrendMA        = 100;        // EMA period on trend TF

input group "=== Decision ==="
input int             InpMinScore       = 2;          // Min confluence score (out of 3) to enter

input group "=== Lot / Risk ==="
input bool            InpAutoLot        = true;       // Risk-based lot sizing
input double          InpRiskPercent    = 0.5;        // Risk % per trade
input double          InpManualLot      = 0.01;       // Manual lot (AutoLot=false)
input double          InpMaxLot         = 4.0;        // Hard lot cap

input group "=== Stops (points) ==="
input double          InpStopLossPts    = 400;        // Stop loss (points)
input double          InpTakeProfitPts  = 600;        // Take profit (points)
input bool            InpUseTrailing    = true;       // Trailing stop
input double          InpTrailStartPts  = 250;        // Start trailing after (points)
input double          InpTrailDistPts   = 200;        // Trailing distance (points)

input group "=== Filters ==="
input int             InpMaxPositions   = 1;          // Max simultaneous positions
input double          InpMaxDrawdownPct = 20.0;       // Equity DD% guard (0=off)

//==================================================================
//  GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;
int      hBands = INVALID_HANDLE;
int      hTrend = INVALID_HANDLE;
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

   hBands = iBands(_Symbol, InpEntryTF, InpBbPeriod, 0, InpBbDev, PRICE_CLOSE);
   hTrend = iMA(_Symbol, InpTrendTF, InpTrendMA, 0, MODE_EMA, PRICE_CLOSE);
   if(hBands == INVALID_HANDLE || hTrend == INVALID_HANDLE)
     { Print("Indicator handle error"); return(INIT_FAILED); }

   g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("DarwinEvolutionStyle initialized on ", _Symbol);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(hBands != INVALID_HANDLE) IndicatorRelease(hBands);
   if(hTrend != INVALID_HANDLE) IndicatorRelease(hTrend);
  }

//==================================================================
//  MAIN TICK
//==================================================================
void OnTick()
  {
   if(!ManageDrawdown()) return;
   ManageTrailing();

   if(!IsNewBar(InpEntryTF)) return;
   if(g_paused) return;
   if(CurrentSpreadPoints() > InpMaxSpreadPts) return;
   if(CountPositions() >= InpMaxPositions) return;

   int dir = ConfluenceSignal();
   if(dir > 0)      OpenTrade(ORDER_TYPE_BUY);
   else if(dir < 0) OpenTrade(ORDER_TYPE_SELL);
  }

//==================================================================
//  CONFLUENCE: combine 3 conditions; need score >= InpMinScore
//==================================================================
int ConfluenceSignal()
  {
   double upper[1], lower[1];
   if(CopyBuffer(hBands, 1, 1, 1, upper) < 1) return 0; // upper
   if(CopyBuffer(hBands, 2, 1, 1, lower) < 1) return 0; // lower

   double trend[1];
   if(CopyBuffer(hTrend, 0, 0, 1, trend) < 1) return 0;

   double closePrev = iClose(_Symbol, InpEntryTF, 1);
   double price     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(closePrev <= 0 || price <= 0) return 0;

   // S/R from recent swing high/low on entry TF
   double srHigh = iHigh(_Symbol, InpEntryTF, iHighest(_Symbol, InpEntryTF, MODE_HIGH, InpSrLookback, 1));
   double srLow  = iLow(_Symbol, InpEntryTF, iLowest(_Symbol, InpEntryTF, MODE_LOW, InpSrLookback, 1));
   double tol    = InpSrTolerancePts * g_point;

   int buyScore = 0, sellScore = 0;

   // 1) Bollinger bounce
   if(closePrev < lower[0]) buyScore++;
   if(closePrev > upper[0]) sellScore++;

   // 2) Near support / resistance
   if(srLow  > 0 && MathAbs(price - srLow)  <= tol) buyScore++;
   if(srHigh > 0 && MathAbs(price - srHigh) <= tol) sellScore++;

   // 3) Higher-TF trend agreement
   if(price > trend[0]) buyScore++;
   else                 sellScore++;

   if(buyScore  >= InpMinScore && buyScore  > sellScore) return  1;
   if(sellScore >= InpMinScore && sellScore > buyScore)  return -1;
   return 0;
  }

//==================================================================
//  ORDER EXECUTION
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
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!posinfo.SelectByTicket(t)) continue;
      if(posinfo.Symbol() == _Symbol && posinfo.Magic() == InpMagic)
         if(trade.PositionClose(t)) closed++;
     }
   if(closed > 0) PrintFormat("Closed %d positions | %s", closed, reason);
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
