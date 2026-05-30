//+------------------------------------------------------------------+
//|                                            QuantumGoldGrid.mq5    |
//|   Trend-following GRID Expert Advisor for XAUUSD (Gold) on MT5    |
//|                                                                  |
//|   This is an INDEPENDENT, clean-room implementation inspired by  |
//|   the publicly described "trend-following grid + basket close"   |
//|   approach. It is NOT affiliated with, nor a copy of, any        |
//|   commercial product. Use at your own risk. Test on DEMO first.  |
//+------------------------------------------------------------------+
#property copyright "Open implementation - educational use"
#property version   "1.10"
#property strict
#property description "Trend-following grid EA for Gold (XAUUSD) with basket take-profit and risk controls."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//==================================================================
//  INPUTS
//==================================================================
enum ENUM_LOT_MODE
  {
   LOT_FIXED = 0,        // Fixed lot
   LOT_RISK_PERCENT = 1  // % balance risk per initial trade
  };

input group "=== General ==="
input long           InpMagic            = 20240601;   // Magic number (unique per chart)
input string         InpComment          = "QGG";      // Trade comment
input int            InpMaxSpreadPoints  = 60;          // Max spread (points) to allow new entries
input int            InpSlippagePoints   = 30;          // Max slippage/deviation (points)

input group "=== Trend Filter ==="
input ENUM_TIMEFRAMES InpTrendTF         = PERIOD_M15;  // Trend timeframe
input int            InpFastMA           = 50;          // Fast EMA period
input int            InpSlowMA           = 200;         // Slow EMA period
input bool           InpTradeWithTrend   = true;        // Only trade in trend direction

input group "=== Grid Settings ==="
input double         InpGridStepPoints   = 250;         // Distance between grid orders (points)
input int            InpMaxTrades        = 10;          // Max simultaneous trades (per basket)
input bool           InpUseDynamicStep   = true;        // Scale grid step by ATR volatility
input ENUM_TIMEFRAMES InpAtrTF           = PERIOD_M15;  // ATR timeframe (for dynamic step)
input int            InpAtrPeriod        = 14;          // ATR period
input double         InpAtrStepMult      = 1.0;         // Grid step = ATR * this (when dynamic)

input group "=== Lot / Money Management ==="
input ENUM_LOT_MODE  InpLotMode          = LOT_FIXED;   // Lot sizing mode
input double         InpFixedLot         = 0.01;        // Fixed lot (first trade)
input double         InpRiskPercent      = 0.5;         // Risk % of balance (risk mode)
input double         InpLotMultiplier    = 1.5;         // Martingale multiplier per grid step (1.0 = off)
input double         InpMaxLot           = 5.0;         // Hard cap on any single lot

input group "=== Take Profit / Basket ==="
input double         InpBasketTPMoney    = 0;           // Close basket at this profit ($). 0 = disabled
input double         InpTPperLotPoints   = 400;         // Per-basket TP target in points (avg-price based)
input double         InpBasketSLMoney    = 0;           // Close basket at this loss ($). 0 = disabled

input group "=== Trailing (basket level) ==="
input bool           InpUseTrailing      = true;        // Trail basket profit
input double         InpTrailStartMoney  = 5.0;         // Start trailing after this profit ($)
input double         InpTrailGiveBack    = 0.40;        // Lock-in: close if profit falls to this fraction of peak

input group "=== Safety / Filters ==="
input double         InpMaxDrawdownPct   = 25.0;        // Close all & pause if equity DD% exceeds this (0=off)
input bool           InpUseTimeFilter    = false;       // Restrict trading hours
input int            InpStartHour        = 0;           // Start hour (server time)
input int            InpEndHour          = 24;          // End hour (server time)
input bool           InpCloseOnFriday    = false;       // Flatten everything Friday evening
input int            InpFridayCloseHour  = 21;          // Friday close hour (server time)

//==================================================================
//  GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;
CSymbolInfo   syminfo;

int      hFastMA  = INVALID_HANDLE;
int      hSlowMA  = INVALID_HANDLE;
int      hAtr     = INVALID_HANDLE;

double   g_point;
int      g_digits;
double   g_peakProfit = 0.0;     // for basket trailing
double   g_startEquity = 0.0;    // session high-water mark for DD
bool     g_paused = false;       // pause flag after a big drawdown hit

//==================================================================
//  INIT / DEINIT
//==================================================================
int OnInit()
  {
   if(!syminfo.Name(_Symbol))
     {
      Print("Failed to init symbol info");
      return(INIT_FAILED);
     }

   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.LogLevel(LOG_LEVEL_ERRORS);

   hFastMA = iMA(_Symbol, InpTrendTF, InpFastMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowMA = iMA(_Symbol, InpTrendTF, InpSlowMA, 0, MODE_EMA, PRICE_CLOSE);
   hAtr    = iATR(_Symbol, InpAtrTF, InpAtrPeriod);

   if(hFastMA == INVALID_HANDLE || hSlowMA == INVALID_HANDLE || hAtr == INVALID_HANDLE)
     {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
     }

   if(InpFastMA >= InpSlowMA)
      Print("WARNING: FastMA period should be < SlowMA period for a sensible trend filter.");

   g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   Print("QuantumGoldGrid initialized on ", _Symbol, " | point=", g_point, " digits=", g_digits);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(hFastMA != INVALID_HANDLE) IndicatorRelease(hFastMA);
   if(hSlowMA != INVALID_HANDLE) IndicatorRelease(hSlowMA);
   if(hAtr    != INVALID_HANDLE) IndicatorRelease(hAtr);
  }

//==================================================================
//  MAIN TICK
//==================================================================
void OnTick()
  {
   // --- Drawdown / equity guard runs every tick (protective)
   if(!ManageDrawdown())
      return; // paused / flattening

   // --- Friday flatten
   if(InpCloseOnFriday && IsFridayCloseTime())
     {
      CloseBasket("Friday flatten");
      return;
     }

   // --- Manage existing basket first (TP / SL / trailing)
   ManageBasket();

   // --- Only evaluate entries on a NEW bar of the trend timeframe (efficiency + stability)
   if(!IsNewBar(InpTrendTF))
      return;

   if(g_paused)
      return;

   if(InpUseTimeFilter && !IsWithinTradingHours())
      return;

   // --- Determine trend direction
   int dir = TrendDirection(); // +1 buy, -1 sell, 0 none
   if(dir == 0 && InpTradeWithTrend)
      return;

   // --- Spread filter
   if(CurrentSpreadPoints() > InpMaxSpreadPoints)
      return;

   // --- Grid logic
   ManageGridEntries(dir);
  }

//==================================================================
//  TREND DETECTION
//==================================================================
int TrendDirection()
  {
   double fast[2], slow[2];
   if(CopyBuffer(hFastMA, 0, 0, 2, fast) < 2) return 0;
   if(CopyBuffer(hSlowMA, 0, 0, 2, slow) < 2) return 0;

   if(fast[0] > slow[0]) return  1;  // uptrend -> buy grid
   if(fast[0] < slow[0]) return -1;  // downtrend -> sell grid
   return 0;
  }

//==================================================================
//  GRID ENTRY MANAGEMENT
//==================================================================
void ManageGridEntries(int dir)
  {
   int    count   = CountPositions();
   double step    = GridStepPrice();

   if(count >= InpMaxTrades)
      return;

   // No positions yet -> open the first one in trend direction
   if(count == 0)
     {
      if(dir > 0) OpenTrade(ORDER_TYPE_BUY, NextLot(0));
      else if(dir < 0) OpenTrade(ORDER_TYPE_SELL, NextLot(0));
      return;
     }

   // We already have a basket -> only add in the SAME direction as existing basket
   int basketDir = BasketDirection();
   if(basketDir == 0) return;

   // If trend filter is on, require the trend to still agree with the basket
   if(InpTradeWithTrend && dir != 0 && dir != basketDir)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lastEntry = LastEntryPrice(basketDir);
   if(lastEntry <= 0) return;

   // Add next grid level only when price moved 'step' against the basket
   if(basketDir > 0) // BUY basket -> add when price drops by step
     {
      if(ask <= lastEntry - step)
         OpenTrade(ORDER_TYPE_BUY, NextLot(count));
     }
   else              // SELL basket -> add when price rises by step
     {
      if(bid >= lastEntry + step)
         OpenTrade(ORDER_TYPE_SELL, NextLot(count));
     }
  }

//==================================================================
//  BASKET MANAGEMENT (TP / SL / TRAILING)
//==================================================================
void ManageBasket()
  {
   int count = CountPositions();
   if(count == 0)
     {
      g_peakProfit = 0.0;
      return;
     }

   double profit = BasketProfitMoney();

   // --- Money-based basket SL
   if(InpBasketSLMoney > 0 && profit <= -MathAbs(InpBasketSLMoney))
     {
      CloseBasket("Basket money SL");
      return;
     }

   // --- Money-based basket TP
   if(InpBasketTPMoney > 0 && profit >= InpBasketTPMoney)
     {
      CloseBasket("Basket money TP");
      return;
     }

   // --- Points-based basket TP (average price target)
   if(InpTPperLotPoints > 0)
     {
      int    dir   = BasketDirection();
      double avg   = BasketAvgPrice();
      double tpPx  = (dir > 0) ? avg + InpTPperLotPoints * g_point
                               : avg - InpTPperLotPoints * g_point;
      double cur   = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(avg > 0 && dir != 0)
        {
         if((dir > 0 && cur >= tpPx) || (dir < 0 && cur <= tpPx))
           {
            CloseBasket("Basket points TP");
            return;
           }
        }
     }

   // --- Trailing on basket profit (lock-in)
   if(InpUseTrailing)
     {
      if(profit > g_peakProfit) g_peakProfit = profit;

      if(g_peakProfit >= InpTrailStartMoney && g_peakProfit > 0)
        {
         double lockLevel = g_peakProfit * InpTrailGiveBack;
         if(profit <= lockLevel)
           {
            CloseBasket("Trailing lock-in");
            return;
           }
        }
     }
  }

//==================================================================
//  ORDER EXECUTION
//==================================================================
bool OpenTrade(ENUM_ORDER_TYPE type, double lot)
  {
   if(lot <= 0) return false;
   lot = NormalizeLot(lot);

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
      if(posinfo.Symbol() != _Symbol) continue;
      if(posinfo.Magic()  != InpMagic) continue;

      if(trade.PositionClose(ticket))
         closed++;
      else
         PrintFormat("Close failed ticket=%I64u err=%d (%s)",
                     ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
   if(closed > 0)
      PrintFormat("Basket closed (%d positions) | reason: %s", closed, reason);
   g_peakProfit = 0.0;
  }

//==================================================================
//  LOT SIZING
//==================================================================
double NextLot(int gridIndex)
  {
   double base = BaseLot();
   double lot  = base * MathPow(InpLotMultiplier, gridIndex);
   return NormalizeLot(lot);
  }

double BaseLot()
  {
   if(InpLotMode == LOT_FIXED)
      return InpFixedLot;

   // Risk-based: risk % of balance over the grid step distance (rough sizing)
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;

   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double stepPx  = GridStepPrice();
   if(tickVal <= 0 || tickSz <= 0 || stepPx <= 0)
      return InpFixedLot;

   double lossPerLot = (stepPx / tickSz) * tickVal; // approx loss per 1 lot over one grid step
   if(lossPerLot <= 0) return InpFixedLot;

   double lot = riskMoney / lossPerLot;
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
//  GRID STEP (static or ATR-dynamic)
//==================================================================
double GridStepPrice()
  {
   if(InpUseDynamicStep)
     {
      double atr[1];
      if(CopyBuffer(hAtr, 0, 0, 1, atr) == 1 && atr[0] > 0)
        {
         double dyn = atr[0] * InpAtrStepMult;
         // never let dynamic step collapse below the static minimum
         double stat = InpGridStepPoints * g_point;
         return MathMax(dyn, stat * 0.5);
        }
     }
   return InpGridStepPoints * g_point;
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
   // For a BUY basket the "last entry" is the LOWEST open price (deepest level);
   // for SELL it is the HIGHEST. This makes the grid expand correctly.
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
//  RISK / FILTERS
//==================================================================
bool ManageDrawdown()
  {
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_startEquity) g_startEquity = equity; // high-water mark

   if(InpMaxDrawdownPct > 0 && g_startEquity > 0)
     {
      double ddPct = (g_startEquity - equity) / g_startEquity * 100.0;
      if(ddPct >= InpMaxDrawdownPct)
        {
         if(CountPositions() > 0)
            CloseBasket("Max drawdown protection");
         g_paused = true;
         return false;
        }
     }

   // Auto-resume once flat
   if(g_paused && CountPositions() == 0)
     {
      g_paused = false;
      g_startEquity = equity; // reset high-water mark
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
   // wrap-around (e.g. 22 -> 6)
   return (t.hour >= InpStartHour || t.hour < InpEndHour);
  }

bool IsFridayCloseTime()
  {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   return (t.day_of_week == 5 && t.hour >= InpFridayCloseHour);
  }

//==================================================================
//  NEW BAR DETECTION
//==================================================================
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
