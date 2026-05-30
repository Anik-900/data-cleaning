//+------------------------------------------------------------------+
//|                                             NightHunterStyle.mq5  |
//|   Night-session mean-reversion SCALPER for MT5                   |
//|                                                                  |
//|   INDEPENDENT, clean-room implementation inspired by the         |
//|   publicly described "calm Asian-session scalper with strict     |
//|   risk management, fixed stop loss, no grid / no martingale"     |
//|   approach. NOT a copy of, nor affiliated with, any commercial   |
//|   product. Use at your own risk. Test on DEMO first.             |
//+------------------------------------------------------------------+
#property copyright "Open implementation - educational use"
#property version   "1.00"
#property strict
#property description "Night-session (Asian) mean-reversion scalper: Bollinger + RSI, fixed SL/TP, strict filters. No grid/martingale."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//==================================================================
//  INPUTS
//==================================================================
input group "=== General ==="
input long            InpMagic          = 20240612;  // Magic number
input string          InpComment        = "NIGHT";   // Trade comment
input int             InpSlippagePoints = 15;         // Max slippage (points)
input int             InpMaxSpreadPts   = 20;         // Max spread (points) - strict for scalping

input group "=== Session (server time) ==="
input int             InpNightStart     = 22;         // Session start hour
input int             InpNightEnd       = 6;          // Session end hour (wraps past midnight)
input bool            InpCloseOutOfSession = true;    // Close trades when session ends

input group "=== Signal: Bollinger + RSI mean-reversion ==="
input ENUM_TIMEFRAMES InpTF             = PERIOD_M5;  // Working timeframe
input int             InpBbPeriod       = 20;         // Bollinger period
input double          InpBbDev          = 2.0;        // Bollinger deviations
input int             InpRsiPeriod      = 14;         // RSI period
input double          InpRsiBuy         = 35.0;       // Buy if RSI below this
input double          InpRsiSell        = 65.0;       // Sell if RSI above this

input group "=== Lot / Risk ==="
input bool            InpAutoLot        = true;       // Risk-based lot sizing
input double          InpRiskPercent    = 0.5;        // Risk % of balance per trade
input double          InpManualLot      = 0.01;       // Manual lot (AutoLot=false)
input double          InpMaxLot         = 3.0;        // Hard lot cap

input group "=== Stops (points) ==="
input double          InpStopLossPts    = 250;        // Stop loss (points)
input double          InpTakeProfitPts  = 120;        // Take profit (points) - small scalp target
input bool            InpUseTrailing    = true;       // Trailing stop
input double          InpTrailStartPts  = 60;         // Start trail after this profit (points)
input double          InpTrailDistPts   = 50;         // Trailing distance (points)

input group "=== Filters ==="
input int             InpMaxPositions   = 1;          // Max simultaneous positions
input double          InpMaxDrawdownPct = 15.0;       // Equity DD% guard (0=off)

//==================================================================
//  GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;
int      hBands = INVALID_HANDLE;
int      hRsi   = INVALID_HANDLE;
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

   hBands = iBands(_Symbol, InpTF, InpBbPeriod, 0, InpBbDev, PRICE_CLOSE);
   hRsi   = iRSI(_Symbol, InpTF, InpRsiPeriod, PRICE_CLOSE);
   if(hBands == INVALID_HANDLE || hRsi == INVALID_HANDLE)
     { Print("Indicator handle error"); return(INIT_FAILED); }

   g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("NightHunterStyle initialized on ", _Symbol);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(hBands != INVALID_HANDLE) IndicatorRelease(hBands);
   if(hRsi   != INVALID_HANDLE) IndicatorRelease(hRsi);
  }

//==================================================================
//  MAIN TICK
//==================================================================
void OnTick()
  {
   if(!ManageDrawdown()) return;
   ManageTrailing();

   bool inSession = IsNightSession();
   if(!inSession)
     {
      if(InpCloseOutOfSession) CloseAll("Session end");
      return;
     }

   if(!IsNewBar(InpTF)) return;
   if(g_paused) return;
   if(CurrentSpreadPoints() > InpMaxSpreadPts) return;
   if(CountPositions() >= InpMaxPositions) return;

   int sig = Signal();
   if(sig > 0)      OpenTrade(ORDER_TYPE_BUY);
   else if(sig < 0) OpenTrade(ORDER_TYPE_SELL);
  }

//==================================================================
//  SIGNAL: price pierces a Bollinger band + RSI confirms reversion
//==================================================================
int Signal()
  {
   double upper[1], lower[1], rsi[1];
   if(CopyBuffer(hBands, 1, 1, 1, upper) < 1) return 0;  // UPPER_BAND buffer=1
   if(CopyBuffer(hBands, 2, 1, 1, lower) < 1) return 0;  // LOWER_BAND buffer=2
   if(CopyBuffer(hRsi,  0, 1, 1, rsi)   < 1) return 0;

   double closePrev = iClose(_Symbol, InpTF, 1);
   if(closePrev <= 0) return 0;

   // Price closed below lower band & RSI oversold -> expect bounce up (BUY)
   if(closePrev < lower[0] && rsi[0] <= InpRsiBuy)  return 1;
   // Price closed above upper band & RSI overbought -> expect drop (SELL)
   if(closePrev > upper[0] && rsi[0] >= InpRsiSell) return -1;
   return 0;
  }

//==================================================================
//  ORDER EXECUTION (fixed SL/TP per trade)
//==================================================================
bool OpenTrade(ENUM_ORDER_TYPE type)
  {
   double lot = CalcLot(InpStopLossPts);
   lot = NormalizeLot(lot);
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
      if(dd >= InpMaxDrawdownPct)
        { CloseAll("Max DD protection"); g_paused = true; return false; }
     }
   if(g_paused && CountPositions() == 0) { g_paused = false; g_startEquity = equity; }
   return true;
  }

bool IsNightSession()
  {
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   if(InpNightStart <= InpNightEnd)
      return (t.hour >= InpNightStart && t.hour < InpNightEnd);
   // wrap-around midnight (e.g. 22 -> 6)
   return (t.hour >= InpNightStart || t.hour < InpNightEnd);
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
