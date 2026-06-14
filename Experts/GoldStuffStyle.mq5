//+------------------------------------------------------------------+
//|                                              GoldStuffStyle.mq5   |
//|   Trend + averaging-grid Expert Advisor for XAUUSD (Gold) on MT5  |
//|                                                                  |
//|   INDEPENDENT, clean-room implementation inspired by the         |
//|   publicly described "trend entry + Distance/Multiplier          |
//|   averaging grid + autolot + trailing" approach popularised by   |
//|   gold EAs. It is NOT a copy of, nor affiliated with, any        |
//|   commercial product. Use at your own risk. Test on DEMO first.  |
//+------------------------------------------------------------------+
#property copyright "Open implementation - educational use"
#property version   "1.00"
#property strict
#property description "Trend-entry averaging grid EA for Gold (XAUUSD): autolot, Distance/Multiplier grid, TakeProfit, break-even trailing."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//==================================================================
//  INPUTS  (named to mirror the well-known public parameter set)
//==================================================================
input group "=== General ==="
input long            InpMagic          = 20240603;  // Magic number (unique per chart)
input string          InpComment        = "GS";      // Trade comment
input int             InpSlippagePoints = 30;         // Max slippage/deviation (points)
input int             InpMaxSpreadPts   = 60;         // Max spread (points) to allow new entries

input group "=== Direction ==="
input bool            InpAllowBuy       = true;       // Allow BUY trades
input bool            InpAllowSell      = true;       // Allow SELL trades
input bool            InpReverseSignal  = false;      // Reverse the trend signal

input group "=== Trend Signal ==="
input ENUM_TIMEFRAMES InpSignalTF       = PERIOD_M15; // Signal timeframe
input int             InpFastMA         = 8;          // Fast EMA period
input int             InpSlowMA         = 32;         // Slow EMA period

input group "=== Lot / Autolot ==="
input bool            InpAutoLot        = true;       // Use automatic lot sizing
input double          InpRiskPerThousand= 0.01;       // Auto lot per 1000 of balance
input double          InpManualLot      = 0.01;       // Manual first lot (when AutoLot=false)
input double          InpMultiplier     = 1.6;        // Lot multiplier for each grid order
input double          InpMaxLot         = 5.0;        // Hard cap on any single lot

input group "=== Grid (averaging) ==="
input double          InpDistancePts    = 300;        // Distance between grid orders (points)
input int             InpMaxTrades      = 10;         // Max simultaneous trades per basket

input group "=== Take Profit ==="
input double          InpTakeProfitPts  = 200;        // TP target from basket avg price (points)
input double          InpBasketTPMoney  = 0;          // Close basket at this profit ($). 0 = off

input group "=== Trailing / Break-even ==="
input bool            InpUseTrailing    = true;       // Trail the basket once in profit
input double          InpStartTrailPts  = 120;        // Start trailing after this profit (points from avg)
input double          InpTrailStopPts   = 80;         // Trailing distance (points)
input double          InpTrailStepPts   = 10;         // Min step to move the trail (points)

input group "=== Filters / Safety ==="
input bool            InpUseTimeFilter  = false;      // Restrict trading hours
input int             InpStartHour      = 0;          // Start hour (server time)
input int             InpEndHour        = 24;         // End hour (server time)
input double          InpMaxDrawdownPct = 30.0;       // Close all & pause if equity DD% exceeds this (0=off)

//==================================================================
//  GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;

int      hFast = INVALID_HANDLE;
int      hSlow = INVALID_HANDLE;

double   g_point;
double   g_startEquity = 0.0;
bool     g_paused = false;
double   g_trailStop = 0.0;   // active basket trailing stop price (0 = none)

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

   hFast = iMA(_Symbol, InpSignalTF, InpFastMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, InpSignalTF, InpSlowMA, 0, MODE_EMA, PRICE_CLOSE);
   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE)
     {
      Print("Failed to create MA handles");
      return(INIT_FAILED);
     }

   g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("GoldStuffStyle initialized on ", _Symbol, " | point=", g_point);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(hFast != INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE) IndicatorRelease(hSlow);
  }

//==================================================================
//  MAIN TICK
//==================================================================
void OnTick()
  {
   if(!ManageDrawdown())
      return;

   ManageBasket();   // TP / money TP / trailing every tick

   // entries evaluated once per signal bar
   if(!IsNewBar(InpSignalTF))
      return;
   if(g_paused)
      return;
   if(InpUseTimeFilter && !IsWithinTradingHours())
      return;

   int sig = SignalDirection();   // +1 buy, -1 sell, 0 none
   if(sig == 0)
      return;
   if(CurrentSpreadPoints() > InpMaxSpreadPts)
      return;

   ManageGridEntries(sig);
  }

//==================================================================
//  TREND SIGNAL (fast vs slow EMA, with optional reverse)
//==================================================================
int SignalDirection()
  {
   double fast[1], slow[1];
   if(CopyBuffer(hFast, 0, 0, 1, fast) < 1) return 0;
   if(CopyBuffer(hSlow, 0, 0, 1, slow) < 1) return 0;

   int dir = 0;
   if(fast[0] > slow[0]) dir =  1;
   if(fast[0] < slow[0]) dir = -1;

   if(InpReverseSignal) dir = -dir;
   return dir;
  }

//==================================================================
//  GRID ENTRIES (initial trend entry + averaging on Distance)
//==================================================================
void ManageGridEntries(int sig)
  {
   int count = CountPositions();
   if(count >= InpMaxTrades)
      return;

   // --- First trade in signal direction
   if(count == 0)
     {
      if(sig > 0 && InpAllowBuy)  OpenTrade(ORDER_TYPE_BUY,  NextLot(0));
      else if(sig < 0 && InpAllowSell) OpenTrade(ORDER_TYPE_SELL, NextLot(0));
      return;
     }

   // --- Averaging: add same-direction order when price moves Distance against basket
   int basketDir = BasketDirection();
   if(basketDir == 0) return;

   double dist      = InpDistancePts * g_point;
   double lastEntry = LastEntryPrice(basketDir);
   if(lastEntry <= 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(basketDir > 0) // BUY basket -> average down
     {
      if(InpAllowBuy && ask <= lastEntry - dist)
         OpenTrade(ORDER_TYPE_BUY, NextLot(count));
     }
   else              // SELL basket -> average up
     {
      if(InpAllowSell && bid >= lastEntry + dist)
         OpenTrade(ORDER_TYPE_SELL, NextLot(count));
     }
  }

//==================================================================
//  BASKET MANAGEMENT (TP / money TP / trailing-stop)
//==================================================================
void ManageBasket()
  {
   int count = CountPositions();
   if(count == 0)
     {
      g_trailStop = 0.0;
      return;
     }

   int    dir   = BasketDirection();
   double avg   = BasketAvgPrice();
   double profit= BasketProfitMoney();
   if(dir == 0 || avg <= 0) return;

   // --- Money-based basket TP
   if(InpBasketTPMoney > 0 && profit >= InpBasketTPMoney)
     {
      CloseBasket("Basket money TP");
      return;
     }

   double cur = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                          : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // --- Fixed TP from average price
   if(InpTakeProfitPts > 0)
     {
      double tpPx = (dir > 0) ? avg + InpTakeProfitPts * g_point
                              : avg - InpTakeProfitPts * g_point;
      if((dir > 0 && cur >= tpPx) || (dir < 0 && cur <= tpPx))
        {
         CloseBasket("Basket TP");
         return;
        }
     }

   // --- Trailing stop on the basket (in points from avg price)
   if(InpUseTrailing)
     {
      double profitPts = (dir > 0) ? (cur - avg) / g_point
                                   : (avg - cur) / g_point;

      if(profitPts >= InpStartTrailPts)
        {
         if(dir > 0)
           {
            double newStop = cur - InpTrailStopPts * g_point;
            if(g_trailStop == 0.0 || newStop >= g_trailStop + InpTrailStepPts * g_point)
               g_trailStop = newStop;
            if(g_trailStop > 0.0 && cur <= g_trailStop)
              {
               CloseBasket("Trailing stop");
               return;
              }
           }
         else
           {
            double newStop = cur + InpTrailStopPts * g_point;
            if(g_trailStop == 0.0 || newStop <= g_trailStop - InpTrailStepPts * g_point)
               g_trailStop = newStop;
            if(g_trailStop > 0.0 && cur >= g_trailStop)
              {
               CloseBasket("Trailing stop");
               return;
              }
           }
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
   else
      g_trailStop = 0.0; // reset trail when basket size changes
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
   g_trailStop = 0.0;
  }

//==================================================================
//  LOT SIZING (autolot or manual, with grid multiplier)
//==================================================================
double NextLot(int gridIndex)
  {
   double base = BaseLot();
   double lot  = base * MathPow(InpMultiplier, gridIndex);
   return NormalizeLot(lot);
  }

double BaseLot()
  {
   if(!InpAutoLot)
      return InpManualLot;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double lot = (balance / 1000.0) * InpRiskPerThousand;
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

bool IsWithinTradingHours()
  {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(InpStartHour <= InpEndHour)
      return (t.hour >= InpStartHour && t.hour < InpEndHour);
   return (t.hour >= InpStartHour || t.hour < InpEndHour);
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
