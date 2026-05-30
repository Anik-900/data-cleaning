//+------------------------------------------------------------------+
//|                                     QuantumAthenaTrendGrid.mq5    |
//|   Lightweight TREND-ALIGNED GRID Expert Advisor for XAUUSD (Gold) |
//|                                                                  |
//|   INDEPENDENT, clean-room implementation inspired by the         |
//|   publicly described "trend-aligned grid" approach (a lighter,   |
//|   focused subset of a larger gold grid system). It is NOT a copy |
//|   of, nor affiliated with, any commercial product.               |
//|   Use at your own risk. ALWAYS test on DEMO first.               |
//+------------------------------------------------------------------+
#property copyright "Open implementation - educational use"
#property version   "1.00"
#property strict
#property description "Lightweight trend-aligned grid EA for Gold (XAUUSD): single-EMA bias, grid adds in trend direction, basket take-profit."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//==================================================================
//  INPUTS  (kept intentionally lean - this is the "lighter" EA)
//==================================================================
input group "=== General ==="
input long            InpMagic           = 20240602;  // Magic number (unique per chart)
input string          InpComment         = "QATH";    // Trade comment
input int             InpMaxSpreadPoints = 60;         // Max spread (points) to allow new entries
input int             InpSlippagePoints  = 30;         // Max slippage/deviation (points)

input group "=== Trend Filter (single EMA - lighter) ==="
input ENUM_TIMEFRAMES InpTrendTF         = PERIOD_M15; // Trend timeframe
input int             InpEmaPeriod       = 100;        // EMA period for trend bias
input int             InpTrendBufferPts  = 50;         // Price must be this far past EMA to confirm bias (points)

input group "=== Grid ==="
input double          InpGridStepPoints  = 300;        // Distance between grid orders (points)
input int             InpMaxTrades       = 8;          // Max simultaneous trades (per basket)
input double          InpLotMultiplier   = 1.3;        // Lot multiplier per grid level (1.0 = uniform lots)

input group "=== Lot ==="
input double          InpFixedLot        = 0.01;       // First-trade lot
input double          InpMaxLot          = 3.0;        // Hard cap on any single lot

input group "=== Basket Take Profit ==="
input double          InpTPpoints        = 450;        // Basket TP target in points (avg-price based)
input double          InpBasketTPMoney   = 0;          // Close basket at this profit ($). 0 = disabled

input group "=== Safety ==="
input double          InpMaxDrawdownPct  = 25.0;       // Close all & pause if equity DD% exceeds this (0=off)

//==================================================================
//  GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;

int      hEma   = INVALID_HANDLE;
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

   hEma = iMA(_Symbol, InpTrendTF, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(hEma == INVALID_HANDLE)
     {
      Print("Failed to create EMA handle");
      return(INIT_FAILED);
     }

   g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("QuantumAthenaTrendGrid initialized on ", _Symbol, " | point=", g_point);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(hEma != INVALID_HANDLE) IndicatorRelease(hEma);
  }

//==================================================================
//  MAIN TICK
//==================================================================
void OnTick()
  {
   if(!ManageDrawdown())
      return;

   ManageBasket();           // handle exits every tick

   if(!IsNewBar(InpTrendTF)) // evaluate entries once per trend bar
      return;
   if(g_paused)
      return;

   int dir = TrendDirection();
   if(dir == 0)
      return;

   if(CurrentSpreadPoints() > InpMaxSpreadPoints)
      return;

   ManageGridEntries(dir);
  }

//==================================================================
//  TREND DIRECTION (single EMA + buffer)
//==================================================================
int TrendDirection()
  {
   double ema[1];
   if(CopyBuffer(hEma, 0, 0, 1, ema) < 1) return 0;

   double price  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = InpTrendBufferPts * g_point;

   if(price > ema[0] + buffer) return  1;  // bullish bias -> buy grid
   if(price < ema[0] - buffer) return -1;  // bearish bias -> sell grid
   return 0;
  }

//==================================================================
//  GRID ENTRIES (only in trend direction)
//==================================================================
void ManageGridEntries(int dir)
  {
   int count = CountPositions();
   if(count >= InpMaxTrades)
      return;

   if(count == 0)
     {
      if(dir > 0) OpenTrade(ORDER_TYPE_BUY,  NextLot(0));
      else        OpenTrade(ORDER_TYPE_SELL, NextLot(0));
      return;
     }

   int basketDir = BasketDirection();
   if(basketDir == 0) return;

   // Trend-aligned: only keep adding while trend still agrees with the basket
   if(dir != basketDir)
      return;

   double step      = InpGridStepPoints * g_point;
   double lastEntry = LastEntryPrice(basketDir);
   if(lastEntry <= 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(basketDir > 0) // BUY basket -> add when price dips a step lower
     {
      if(ask <= lastEntry - step)
         OpenTrade(ORDER_TYPE_BUY, NextLot(count));
     }
   else              // SELL basket -> add when price rises a step higher
     {
      if(bid >= lastEntry + step)
         OpenTrade(ORDER_TYPE_SELL, NextLot(count));
     }
  }

//==================================================================
//  BASKET EXIT (TP by points or money)
//==================================================================
void ManageBasket()
  {
   int count = CountPositions();
   if(count == 0) return;

   double profit = BasketProfitMoney();

   if(InpBasketTPMoney > 0 && profit >= InpBasketTPMoney)
     {
      CloseBasket("Basket money TP");
      return;
     }

   if(InpTPpoints > 0)
     {
      int    dir = BasketDirection();
      double avg = BasketAvgPrice();
      if(avg > 0 && dir != 0)
        {
         double tpPx = (dir > 0) ? avg + InpTPpoints * g_point
                                 : avg - InpTPpoints * g_point;
         double cur  = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if((dir > 0 && cur >= tpPx) || (dir < 0 && cur <= tpPx))
            CloseBasket("Basket points TP");
        }
     }
  }

//==================================================================
//  ORDER EXECUTION
//==================================================================
bool OpenTrade(ENUM_ORDER_TYPE type, double lot)
  {
   lot = NormalizeLot(lot);
   if(lot <= 0) return false;

   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool ok = trade.PositionOpen(_Symbol, type, lot, price, 0, 0, InpComment);
   if(!ok)
      PrintFormat("OpenTrade failed: type=%d lot=%.2f err=%d (%s)",
                  type, lot, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return ok;
  }

void CloseBasket(string reason)
  {
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!posinfo.SelectByTicket(ticket)) continue;
      if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;

      if(trade.PositionClose(ticket))
         closed++;
      else
         PrintFormat("Close failed ticket=%I64u err=%d (%s)",
                     ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
   if(closed > 0)
      PrintFormat("Basket closed (%d positions) | reason: %s", closed, reason);
  }

//==================================================================
//  LOT SIZING
//==================================================================
double NextLot(int gridIndex)
  {
   double lot = InpFixedLot * MathPow(InpLotMultiplier, gridIndex);
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
   if(lot > cap)    lot = cap;
   if(lot < minLot) lot = minLot;
   return NormalizeDouble(lot, 2);
  }

//==================================================================
//  POSITION HELPERS (filtered by symbol + magic)
//==================================================================
int CountPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!posinfo.SelectByTicket(ticket)) continue;
      if(posinfo.Symbol() == _Symbol && posinfo.Magic() == InpMagic)
         c++;
     }
   return c;
  }

int BasketDirection()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!posinfo.SelectByTicket(ticket)) continue;
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
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!posinfo.SelectByTicket(ticket)) continue;
      if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;
      p += posinfo.Profit() + posinfo.Swap() + posinfo.Commission();
     }
   return p;
  }

double BasketAvgPrice()
  {
   double sumVolPrice = 0.0, sumVol = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!posinfo.SelectByTicket(ticket)) continue;
      if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;
      sumVolPrice += posinfo.PriceOpen() * posinfo.Volume();
      sumVol      += posinfo.Volume();
     }
   return (sumVol > 0) ? sumVolPrice / sumVol : 0.0;
  }

double LastEntryPrice(int dir)
  {
   // BUY basket -> lowest open price; SELL basket -> highest open price
   double result = -1;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!posinfo.SelectByTicket(ticket)) continue;
      if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;

      double px = posinfo.PriceOpen();
      if(result < 0) { result = px; continue; }
      if(dir > 0) result = MathMin(result, px);
      else        result = MathMax(result, px);
     }
   return result;
  }

//==================================================================
//  SAFETY / UTILITIES
//==================================================================
bool ManageDrawdown()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_startEquity) g_startEquity = equity;

   if(InpMaxDrawdownPct > 0 && g_startEquity > 0)
     {
      double ddPct = (g_startEquity - equity) / g_startEquity * 100.0;
      if(ddPct >= InpMaxDrawdownPct)
        {
         if(CountPositions() > 0) CloseBasket("Max drawdown protection");
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

int CurrentSpreadPoints()
  {
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
  }

bool IsNewBar(ENUM_TIMEFRAMES tf)
  {
   static datetime lastBarTime = 0;
   datetime cur = (datetime)SeriesInfoInteger(_Symbol, tf, SERIES_LASTBAR_DATE);
   if(cur != lastBarTime)
     {
      lastBarTime = cur;
      return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
