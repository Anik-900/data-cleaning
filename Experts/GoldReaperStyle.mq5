//+------------------------------------------------------------------+
//|                                              GoldReaperStyle.mq5  |
//|   Breakout pending-order SCALPER for XAUUSD (Gold) on MT5         |
//|                                                                  |
//|   INDEPENDENT, clean-room implementation inspired by the         |
//|   publicly described "multi-timeframe S/R breakout scalper with  |
//|   a hard stop loss on every trade, trailing, and a news filter   |
//|   (no grid, no martingale)" approach. NOT a copy of, nor         |
//|   affiliated with, any commercial product.                       |
//|   Use at your own risk. ALWAYS test on DEMO first.               |
//+------------------------------------------------------------------+
#property copyright "Open implementation - educational use"
#property version   "1.00"
#property strict
#property description "Breakout pending-order scalper for Gold (XAUUSD): hard SL/TP, trailing, spread/time filter. No grid/martingale."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//==================================================================
//  INPUTS
//==================================================================
input group "=== General ==="
input long            InpMagic           = 20240610;  // Magic number
input string          InpComment         = "REAPER";  // Trade comment
input int             InpSlippagePoints  = 30;         // Max slippage (points)
input int             InpMaxSpreadPts    = 50;         // Max spread (points)

input group "=== Breakout Channel ==="
input ENUM_TIMEFRAMES InpChannelTF       = PERIOD_M15; // Channel timeframe
input int             InpChannelBars     = 24;         // Lookback bars for high/low channel
input double          InpBreakoutBufferPts = 30;       // Place stop orders this far beyond the channel (points)
input int             InpPendingExpiryBars = 4;        // Cancel untriggered pending order after N bars

input group "=== Risk / Money ==="
input bool            InpAutoLot         = true;       // Risk-based lot sizing
input double          InpRiskPercent     = 0.5;        // Risk % of balance per trade
input double          InpManualLot       = 0.01;       // Manual lot (AutoLot=false)
input double          InpMaxLot          = 5.0;        // Hard lot cap

input group "=== Stops (in points) ==="
input double          InpStopLossPts     = 350;        // Hard stop loss (points)
input double          InpTakeProfitPts   = 500;        // Take profit (points)

input group "=== Trailing ==="
input bool            InpUseTrailing     = true;       // Trailing stop
input double          InpTrailStartPts   = 200;        // Start trailing after this profit (points)
input double          InpTrailDistPts    = 150;        // Trailing distance (points)
input double          InpTrailStepPts    = 20;         // Min step to advance trail (points)

input group "=== Filters ==="
input int             InpMaxPositions    = 2;          // Max simultaneous positions
input bool            InpUseTimeFilter   = true;       // Restrict trading hours
input int             InpStartHour       = 7;          // Start hour (server time)
input int             InpEndHour         = 21;         // End hour (server time)
input double          InpMaxDrawdownPct  = 20.0;       // Equity DD% guard (0=off)

//==================================================================
//  GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;
COrderInfo    ordinfo;

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
   g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("GoldReaperStyle initialized on ", _Symbol);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) {}

//==================================================================
//  MAIN TICK
//==================================================================
void OnTick()
  {
   if(!ManageDrawdown())
      return;

   ManageTrailing();        // every tick

   if(!IsNewBar(InpChannelTF))
      return;

   CleanupExpiredPendings();

   if(g_paused) return;
   if(InpUseTimeFilter && !IsWithinTradingHours()) { DeleteAllPendings(); return; }
   if(CurrentSpreadPoints() > InpMaxSpreadPts) return;
   if(CountPositions() + CountPendings() >= InpMaxPositions) return;

   PlaceBreakoutOrders();
  }

//==================================================================
//  BREAKOUT ORDER PLACEMENT (buy-stop above range, sell-stop below)
//==================================================================
void PlaceBreakoutOrders()
  {
   double hi = iHigh(_Symbol, InpChannelTF, iHighest(_Symbol, InpChannelTF, MODE_HIGH, InpChannelBars, 1));
   double lo = iLow(_Symbol, InpChannelTF, iLowest(_Symbol, InpChannelTF, MODE_LOW, InpChannelBars, 1));
   if(hi <= 0 || lo <= 0) return;

   double buf   = InpBreakoutBufferPts * g_point;
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;

   datetime expiry = (InpPendingExpiryBars > 0)
                     ? TimeCurrent() + InpPendingExpiryBars * PeriodSeconds(InpChannelTF)
                     : 0;

   // Buy stop above range high
   if(!HasPendingType(ORDER_TYPE_BUY_STOP))
     {
      double price = hi + buf;
      if(price > ask + stops)
        {
         double sl = price - InpStopLossPts * g_point;
         double tp = price + InpTakeProfitPts * g_point;
         double lot = CalcLot(InpStopLossPts);
         PlacePending(ORDER_TYPE_BUY_STOP, lot, price, sl, tp, expiry);
        }
     }

   // Sell stop below range low
   if(!HasPendingType(ORDER_TYPE_SELL_STOP))
     {
      double price = lo - buf;
      if(price < bid - stops)
        {
         double sl = price + InpStopLossPts * g_point;
         double tp = price - InpTakeProfitPts * g_point;
         double lot = CalcLot(InpStopLossPts);
         PlacePending(ORDER_TYPE_SELL_STOP, lot, price, sl, tp, expiry);
        }
     }
  }

bool PlacePending(ENUM_ORDER_TYPE type, double lot, double price, double sl, double tp, datetime expiry)
  {
   lot   = NormalizeLot(lot);
   price = NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   sl    = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   tp    = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

   ENUM_ORDER_TYPE_TIME tmode = (expiry > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
   bool ok = trade.OrderOpen(_Symbol, type, lot, 0.0, price, sl, tp, tmode, expiry, InpComment);
   if(!ok)
      PrintFormat("Pending failed type=%d price=%.3f err=%d (%s)",
                  type, price, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return ok;
  }

//==================================================================
//  TRAILING STOP (per open position)
//==================================================================
void ManageTrailing()
  {
   if(!InpUseTrailing) return;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!posinfo.SelectByTicket(ticket)) continue;
      if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;

      double open = posinfo.PriceOpen();
      double sl   = posinfo.StopLoss();

      if(posinfo.PositionType() == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid - open >= InpTrailStartPts * g_point)
           {
            double newSL = NormalizeDouble(bid - InpTrailDistPts * g_point, digits);
            if(newSL > sl + InpTrailStepPts * g_point || sl == 0.0)
               trade.PositionModify(ticket, newSL, posinfo.TakeProfit());
           }
        }
      else
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(open - ask >= InpTrailStartPts * g_point)
           {
            double newSL = NormalizeDouble(ask + InpTrailDistPts * g_point, digits);
            if((newSL < sl - InpTrailStepPts * g_point) || sl == 0.0)
               trade.PositionModify(ticket, newSL, posinfo.TakeProfit());
           }
        }
     }
  }

//==================================================================
//  PENDING ORDER HOUSEKEEPING
//==================================================================
void CleanupExpiredPendings()
  {
   // GTC fallback: if expiry not supported by broker we manually drop stale orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!ordinfo.Select(ticket)) continue;
      if(ordinfo.Symbol() != _Symbol || ordinfo.Magic() != InpMagic) continue;
      if(InpPendingExpiryBars <= 0) continue;

      long age = (long)(TimeCurrent() - ordinfo.TimeSetup());
      if(age > (long)InpPendingExpiryBars * PeriodSeconds(InpChannelTF))
         trade.OrderDelete(ticket);
     }
  }

void DeleteAllPendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!ordinfo.Select(ticket)) continue;
      if(ordinfo.Symbol() == _Symbol && ordinfo.Magic() == InpMagic)
         trade.OrderDelete(ticket);
     }
  }

bool HasPendingType(ENUM_ORDER_TYPE type)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!ordinfo.Select(ticket)) continue;
      if(ordinfo.Symbol() != _Symbol || ordinfo.Magic() != InpMagic) continue;
      if(ordinfo.OrderType() == type) return true;
     }
   return false;
  }

int CountPendings()
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!ordinfo.Select(ticket)) continue;
      if(ordinfo.Symbol() == _Symbol && ordinfo.Magic() == InpMagic) c++;
     }
   return c;
  }

//==================================================================
//  LOT SIZING (risk-based from stop distance)
//==================================================================
double CalcLot(double slPoints)
  {
   if(!InpAutoLot) return NormalizeLot(InpManualLot);

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;
   double tickVal   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSz <= 0 || slPoints <= 0) return NormalizeLot(InpManualLot);

   double slPrice    = slPoints * g_point;
   double lossPerLot = (slPrice / tickSz) * tickVal;
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
   if(lot > cap)    lot = cap;
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
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!posinfo.SelectByTicket(ticket)) continue;
      if(posinfo.Symbol() == _Symbol && posinfo.Magic() == InpMagic) c++;
     }
   return c;
  }

bool ManageDrawdown()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_startEquity) g_startEquity = equity;
   if(InpMaxDrawdownPct > 0 && g_startEquity > 0)
     {
      double ddPct = (g_startEquity - equity) / g_startEquity * 100.0;
      if(ddPct >= InpMaxDrawdownPct)
        {
         CloseAll();
         DeleteAllPendings();
         g_paused = true;
         return false;
        }
     }
   if(g_paused && CountPositions() == 0)
     {
      g_paused = false;
      g_startEquity = equity;
     }
   return true;
  }

void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!posinfo.SelectByTicket(ticket)) continue;
      if(posinfo.Symbol() == _Symbol && posinfo.Magic() == InpMagic)
         trade.PositionClose(ticket);
     }
  }

int CurrentSpreadPoints() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); }

bool IsWithinTradingHours()
  {
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   if(InpStartHour <= InpEndHour) return (t.hour >= InpStartHour && t.hour < InpEndHour);
   return (t.hour >= InpStartHour || t.hour < InpEndHour);
  }

bool IsNewBar(ENUM_TIMEFRAMES tf)
  {
   static datetime last = 0;
   datetime cur = (datetime)SeriesInfoInteger(_Symbol, tf, SERIES_LASTBAR_DATE);
   if(cur != last) { last = cur; return true; }
   return false;
  }
//+------------------------------------------------------------------+
