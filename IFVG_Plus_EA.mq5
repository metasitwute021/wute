//+------------------------------------------------------------------+
//|                                              IFVG_Plus_EA.mq5     |
//|        Inversion Fair Value Gap (IFVG+) Expert Advisor            |
//|                                                                  |
//|  Concept (transcribed from the strategy video):                  |
//|  - A Fair Value Gap (FVG) is a 3-candle imbalance where the      |
//|    middle candle is so strong that the wicks of candle 1 and     |
//|    candle 3 do NOT overlap, leaving a price "gap".               |
//|  - A BEARISH FVG forms when  Low[c1] > High[c3]  (gap down).     |
//|    The zone is [High[c3] .. Low[c1]].                            |
//|  - INVERSION ("IFVG"): when a later candle CLOSES back through   |
//|    the gap (a close above the bearish-gap top), the gap flips    |
//|    from resistance to support -> BUY signal.                     |
//|  - The "+" = extra confirmation filters: displacement (impulse   |
//|    candle >= ATR x mult), trend bias (EMA), and trading session. |
//|                                                                  |
//|  - Entry  : on confirmed inversion of a qualified FVG.           |
//|  - SL     : structural - below the 3rd candle (buy) / above it   |
//|             (sell), with a small buffer. NO fixed take-profit.   |
//|  - Exit   : profit runs via multi-layer trailing (safest stop).  |
//|  - Sizing : risk % of balance vs. SL distance (cent-account OK). |
//|  - Guards : max DD pause, daily DD stop, high-impact news filter.|
//+------------------------------------------------------------------+
#property copyright "IFVG+ EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//==================================================================
//  Inputs
//==================================================================
input group "=== General ==="
input long     InpMagic              = 770311;     // Magic number
input bool     InpEnableNotifications= true;       // Send push notifications
input string   InpNotifPrefix        = "[IFVG+] "; // Notification prefix

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES InpEntryTF      = PERIOD_M15; // Entry / signal timeframe
input ENUM_TIMEFRAMES InpTrailTF      = PERIOD_M5;  // Trailing management timeframe

input group "=== IFVG detection ==="
input int      InpScanBars           = 200;        // How many bars back to scan / keep FVGs
input int      InpFVGMaxAgeBars       = 40;        // Discard an FVG if not inverted within N bars
input double   InpMinGapPoints        = 50;        // Minimum gap size (points) to qualify
input bool     InpUseDisplacement     = true;      // Require strong impulse (middle candle)
input int      InpDispATRPeriod       = 14;        // ATR period for displacement test
input double   InpDispATRMult         = 1.2;       // Middle candle range >= ATR x this
input bool     InpRequireCloseInvert  = true;      // Inversion must be a CLOSE through the gap
input bool     InpAllowBuy            = true;      // Trade bearish-FVG inversions (BUY)
input bool     InpAllowSell           = true;      // Trade bullish-FVG inversions (SELL)

input group "=== '+' trend / session filters ==="
input bool     InpUseTrendFilter      = true;      // Only trade with EMA trend bias
input int      InpTrendEMAPeriod       = 50;       // Trend EMA period (entry TF)
input bool     InpUseSession          = false;     // Restrict to a trading session
input int      InpSessionStartHour     = 12;       // Session start hour (server time)
input int      InpSessionEndHour       = 20;       // Session end hour (server time)

input group "=== Visualization ==="
input bool     InpDrawZones          = true;       // Draw FVG boxes on the chart
input color    InpBearColor          = clrTomato;  // Bearish FVG box (waits for BUY)
input color    InpBullColor          = clrDodgerBlue; // Bullish FVG box (waits for SELL)
input bool     InpFillZones          = true;       // Fill boxes (vs. outline only)
input bool     InpDrawEntryArrows    = true;       // Mark entries with arrows

input group "=== Risk / sizing ==="
input double   InpRiskPercent        = 1.0;        // Risk per trade (% balance)
input double   InpSL_BufferPoints    = 30;         // SL buffer beyond the 3rd candle (points)
input int      InpMaxPositions       = 1;          // Max simultaneous positions

input group "=== Trade management ==="
input double   InpBreakEvenR         = 0.50;       // Move SL to BE at this R
input double   InpBE_BufferPts       = 20;         // BE buffer (points beyond entry)
input double   InpPartialR           = 1.0;        // Partial close at this R
input double   InpPartialPercent     = 40.0;       // Percent of position to close

input group "=== Trailing layers ==="
input int      InpTr1_ATRPeriod      = 18;         // Layer 1 ATR period
input double   InpTr1_ATRMult        = 4.0;        // Layer 1 ATR multiplier
input int      InpTr2_ATRPeriod      = 12;         // Strong move ATR period
input double   InpTr2_ATRMult        = 2.5;        // Strong move ATR multiplier
input int      InpSwingLookback      = 15;         // Swing high/low lookback (trail TF bars)
input int      InpCandleBackShift    = 3;          // "3rd candle" shift for trailing

input group "=== Drawdown protection ==="
input double   InpMaxDD_Percent      = 20.0;       // Max drawdown -> pause EA (%)
input double   InpMaxDD_ResumeBuffer = 2.0;        // Resume when DD below (Max - buffer)
input double   InpDailyDD_Percent    = 1.5;        // Daily drawdown -> stop for day (%)

input group "=== News filter ==="
input bool     InpEnableNewsFilter   = true;       // Avoid trading around news
input int      InpNewsMinutesBefore  = 30;         // Block window before news (min)
input int      InpNewsMinutesAfter   = 30;         // Block window after news (min)
input string   InpNewsCurrencies     = "USD,XAU";  // Currencies to watch (comma sep.)

//==================================================================
//  Globals
//==================================================================
CTrade   trade;

int hEMA      = INVALID_HANDLE;   // trend EMA (entry TF)
int hATRdisp  = INVALID_HANDLE;   // displacement ATR (entry TF)
int hATR1     = INVALID_HANDLE;   // trailing layer 1
int hATR2     = INVALID_HANDLE;   // trailing layer 2

datetime gLastEntryBar = 0;

// ---- Active (not-yet-inverted) Fair Value Gaps ----
// type: +1 = bearish FVG (waits for upward inversion -> BUY)
//       -1 = bullish FVG (waits for downward inversion -> SELL)
struct FVGZone
{
   int      type;        // +1 bearish / -1 bullish
   double   top;         // upper edge of the gap
   double   bottom;      // lower edge of the gap
   double   protLevel;   // structural SL reference (extreme of the 3-candle trio)
   datetime formedTime;  // bar time of the 3rd (newest) candle
   int      ageBars;     // bars since formation
   string   objName;     // chart rectangle object name ("" if not drawn)
};
FVGZone  gZones[];

#define IFVG_PREFIX "IFVG_"   // chart-object name prefix

// per-position state
ulong    gPosTicket[];
double   gPosInitRisk[];
double   gPosInitVol[];
bool     gPosBEDone[];
bool     gPosPartialDone[];

// drawdown / protection state
double   gPeakEquity     = 0.0;
bool     gMaxDDPaused    = false;
datetime gDayStart       = 0;
double   gDayStartEquity = 0.0;
bool     gDailyStopped   = false;

// news state
bool     gInNews         = false;

//+------------------------------------------------------------------+
//| Helper: notify + log                                             |
//+------------------------------------------------------------------+
void Notify(const string msg)
{
   Print(msg);
   if(InpEnableNotifications)
      SendNotification(InpNotifPrefix + msg);
}

//+------------------------------------------------------------------+
//| Helper: read one indicator buffer value at shift                 |
//+------------------------------------------------------------------+
bool BufVal(const int handle, const int buffer, const int shift, double &out)
{
   double tmp[];
   if(CopyBuffer(handle, buffer, shift, 1, tmp) < 1)
      return false;
   out = tmp[0];
   return true;
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(30);

   hEMA     = iMA (_Symbol, InpEntryTF, InpTrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hATRdisp = iATR(_Symbol, InpEntryTF, InpDispATRPeriod);
   hATR1    = iATR(_Symbol, InpTrailTF, InpTr1_ATRPeriod);
   hATR2    = iATR(_Symbol, InpTrailTF, InpTr2_ATRPeriod);

   if(hEMA==INVALID_HANDLE || hATRdisp==INVALID_HANDLE ||
      hATR1==INVALID_HANDLE || hATR2==INVALID_HANDLE)
   {
      Print("Failed to create one or more indicator handles");
      return(INIT_FAILED);
   }

   gPeakEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
   gDayStart       = 0;
   gDayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   DeleteAllObjects();   // clear any leftovers from a previous run

   EventSetTimer(5);

   Notify("EA started on " + _Symbol + " (entry " + EnumToString(InpEntryTF) +
          ", trail " + EnumToString(InpTrailTF) + ")");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteAllObjects();
   if(hEMA!=INVALID_HANDLE)     IndicatorRelease(hEMA);
   if(hATRdisp!=INVALID_HANDLE) IndicatorRelease(hATRdisp);
   if(hATR1!=INVALID_HANDLE)    IndicatorRelease(hATR1);
   if(hATR2!=INVALID_HANDLE)    IndicatorRelease(hATR2);
   Notify("EA stopped (reason " + IntegerToString(reason) + ")");
}

//+------------------------------------------------------------------+
//| Timer: protection + news                                         |
//+------------------------------------------------------------------+
void OnTimer()
{
   CheckDrawdownProtection();
   UpdateNewsState();
}

//+------------------------------------------------------------------+
//| Tick                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   SyncPositionState();
   ManageOpenPositions();   // trailing / BE / partial every tick

   // Work once per closed entry-TF bar
   datetime curBar = (datetime)iTime(_Symbol, InpEntryTF, 0);
   if(curBar == gLastEntryBar)
      return;
   gLastEntryBar = curBar;

   AgeAndPruneZones();      // age existing FVGs, drop expired ones
   DetectNewFVG();          // did a new FVG just complete on the closed bar?
   ScanForInversion();      // did price just invert any stored FVG? -> entry
   ExtendZones();           // grow active FVG boxes to the current bar
   if(InpDrawZones || InpDrawEntryArrows)
      ChartRedraw(0);
}

//==================================================================
//  IFVG ENGINE
//==================================================================

// Increment age, remove FVGs that are too old or already filled/violated.
void AgeAndPruneZones()
{
   double close1 = iClose(_Symbol, InpEntryTF, 1);
   for(int i=ArraySize(gZones)-1; i>=0; i--)
   {
      gZones[i].ageBars++;

      bool drop = false;
      if(gZones[i].ageBars > InpFVGMaxAgeBars)
         drop = true;

      // A bearish FVG (waiting for BUY) is invalidated if price collapses far
      // below the gap bottom without inverting; mirror for bullish.
      if(gZones[i].type > 0 && close1 < gZones[i].protLevel)
         drop = true;
      if(gZones[i].type < 0 && close1 > gZones[i].protLevel)
         drop = true;

      if(drop)
         RemoveZoneAt(i);
   }
}

// Detect a Fair Value Gap that just COMPLETED on the last closed bar.
// Candle trio (series shift, higher = older):
//   c3 (newest)  = shift 1   (just closed)
//   c2 (middle)  = shift 2   (the impulse)
//   c1 (oldest)  = shift 3
void DetectNewFVG()
{
   double h1 = iHigh(_Symbol, InpEntryTF, 1);   // c3 high
   double l1 = iLow (_Symbol, InpEntryTF, 1);   // c3 low
   double h3 = iHigh(_Symbol, InpEntryTF, 3);   // c1 high
   double l3 = iLow (_Symbol, InpEntryTF, 3);   // c1 low

   // middle (impulse) candle range for the displacement test
   double mHigh = iHigh(_Symbol, InpEntryTF, 2);
   double mLow  = iLow (_Symbol, InpEntryTF, 2);
   double mRange = mHigh - mLow;

   double atrDisp = 0.0;
   BufVal(hATRdisp, 0, 2, atrDisp);
   bool dispOK = (!InpUseDisplacement) ||
                 (atrDisp > 0.0 && mRange >= atrDisp * InpDispATRMult);

   double minGap = InpMinGapPoints * _Point;

   // ----- Bearish FVG: Low[c1] > High[c3]  -> zone [High[c3] .. Low[c1]] -----
   if(l3 > h1)
   {
      double gap = l3 - h1;
      if(gap >= minGap && dispOK)
      {
         double protLow = MathMin(MathMin(l1, mLow), l3);  // lowest of the trio
         AddZone(+1, l3 /*top*/, h1 /*bottom*/, protLow);
      }
   }

   // ----- Bullish FVG: High[c1] < Low[c3]  -> zone [High[c1] .. Low[c3]] -----
   if(h3 < l1)
   {
      double gap = l1 - h3;
      if(gap >= minGap && dispOK)
      {
         double protHigh = MathMax(MathMax(h1, mHigh), h3); // highest of the trio
         AddZone(-1, l1 /*top*/, h3 /*bottom*/, protHigh);
      }
   }
}

// Check every stored FVG for an inversion close; fire one entry if conditions hold.
void ScanForInversion()
{
   if(!TradingAllowed())
      return;

   double close1 = iClose(_Symbol, InpEntryTF, 1);

   for(int i=ArraySize(gZones)-1; i>=0; i--)
   {
      FVGZone z = gZones[i];

      // need at least one bar after formation before it can invert
      if(z.ageBars < 1)
         continue;

      bool inverted = false;
      ENUM_ORDER_TYPE dir = ORDER_TYPE_BUY;

      if(z.type > 0)   // bearish gap -> upward inversion -> BUY
      {
         double ref = InpRequireCloseInvert ? close1
                                            : iHigh(_Symbol, InpEntryTF, 1);
         if(ref > z.top && InpAllowBuy)
         {
            inverted = true;
            dir = ORDER_TYPE_BUY;
         }
      }
      else             // bullish gap -> downward inversion -> SELL
      {
         double ref = InpRequireCloseInvert ? close1
                                            : iLow(_Symbol, InpEntryTF, 1);
         if(ref < z.bottom && InpAllowSell)
         {
            inverted = true;
            dir = ORDER_TYPE_SELL;
         }
      }

      if(!inverted)
         continue;

      if(!PassesPlusFilters(dir))
      {
         RemoveZoneAt(i);   // inverted but filtered out -> consume it
         continue;
      }

      // structural SL = beyond the 3-candle extreme + buffer
      double buf = InpSL_BufferPoints * _Point;
      double slPrice = (dir==ORDER_TYPE_BUY) ? z.protLevel - buf
                                             : z.protLevel + buf;

      double entryPx = (dir==ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      OpenTrade(dir, slPrice);
      DrawEntryArrow(dir, entryPx);
      RemoveZoneAt(i);       // one shot per gap
      return;                // one entry per bar
   }
}

// "+" confirmation: trend bias (EMA) and session window.
bool PassesPlusFilters(const ENUM_ORDER_TYPE dir)
{
   if(InpUseTrendFilter)
   {
      double ema;
      if(!BufVal(hEMA, 0, 1, ema)) return false;
      double close1 = iClose(_Symbol, InpEntryTF, 1);
      if(dir==ORDER_TYPE_BUY  && close1 < ema) return false;
      if(dir==ORDER_TYPE_SELL && close1 > ema) return false;
   }

   if(InpUseSession)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      bool inSession = (InpSessionStartHour <= InpSessionEndHour)
                       ? (h >= InpSessionStartHour && h < InpSessionEndHour)
                       : (h >= InpSessionStartHour || h < InpSessionEndHour);
      if(!inSession) return false;
   }
   return true;
}

//==================================================================
//  FVG list helpers
//==================================================================
void AddZone(const int type, const double top, const double bottom, const double prot)
{
   int n = ArraySize(gZones);
   ArrayResize(gZones, n+1);
   datetime formed     = (datetime)iTime(_Symbol, InpEntryTF, 1);
   gZones[n].type       = type;
   gZones[n].top        = top;
   gZones[n].bottom     = bottom;
   gZones[n].protLevel  = prot;
   gZones[n].formedTime = formed;
   gZones[n].ageBars    = 0;
   gZones[n].objName    = DrawZone(type, top, bottom, formed);
}

void RemoveZoneAt(const int idx)
{
   int n = ArraySize(gZones);
   if(idx<0 || idx>=n) return;
   if(gZones[idx].objName != "")
      ObjectDelete(0, gZones[idx].objName);
   for(int i=idx; i<n-1; i++)
      gZones[i] = gZones[i+1];
   ArrayResize(gZones, n-1);
}

//==================================================================
//  Chart visualization
//==================================================================
// Create a rectangle for a freshly detected FVG. Returns object name.
string DrawZone(const int type, const double top, const double bottom,
                const datetime formed)
{
   if(!InpDrawZones) return "";

   // the trio started 2 bars before the newest (formation) candle
   datetime t1 = (datetime)iTime(_Symbol, InpEntryTF, 3);
   datetime t2 = formed;   // extended forward each bar while active

   string name = StringFormat("%s%d_%I64d", IFVG_PREFIX, type, (long)formed);
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   color col = (type > 0) ? InpBearColor : InpBullColor;
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bottom))
      return "";
   ObjectSetInteger(0, name, OBJPROP_COLOR,     col);
   ObjectSetInteger(0, name, OBJPROP_FILL,      InpFillZones);
   ObjectSetInteger(0, name, OBJPROP_BACK,      true);
   ObjectSetInteger(0, name, OBJPROP_STYLE,     STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   return name;
}

// Stretch every active zone's right edge to the current bar.
void ExtendZones()
{
   if(!InpDrawZones) return;
   datetime now = (datetime)iTime(_Symbol, InpEntryTF, 0);
   for(int i=0; i<ArraySize(gZones); i++)
   {
      if(gZones[i].objName == "") continue;
      ObjectSetInteger(0, gZones[i].objName, OBJPROP_TIME, 1, now);
   }
}

// Drop an arrow where an entry was triggered.
void DrawEntryArrow(const ENUM_ORDER_TYPE dir, const double price)
{
   if(!InpDrawEntryArrows) return;
   datetime t   = (datetime)iTime(_Symbol, InpEntryTF, 0);
   string   nm  = StringFormat("%sENTRY_%I64d", IFVG_PREFIX, (long)t);
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);

   bool isBuy = (dir==ORDER_TYPE_BUY);
   ObjectCreate(0, nm, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, isBuy ? 233 : 234); // up / down arrow
   ObjectSetInteger(0, nm, OBJPROP_COLOR,     isBuy ? clrLime : clrRed);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH,     2);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR,    isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,false);
}

// Remove every object this EA created.
void DeleteAllObjects()
{
   ObjectsDeleteAll(0, IFVG_PREFIX);
}

//==================================================================
//  Protection: drawdown
//==================================================================
void CheckDrawdownProtection()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > gPeakEquity)
      gPeakEquity = equity;

   double ddPct = (gPeakEquity > 0.0) ? (gPeakEquity - equity)/gPeakEquity*100.0 : 0.0;

   if(!gMaxDDPaused && ddPct >= InpMaxDD_Percent)
   {
      gMaxDDPaused = true;
      Notify(StringFormat("MAX DRAWDOWN %.2f%% >= %.2f%% -> EA PAUSED", ddPct, InpMaxDD_Percent));
   }
   else if(gMaxDDPaused && ddPct <= (InpMaxDD_Percent - InpMaxDD_ResumeBuffer))
   {
      gMaxDDPaused = false;
      Notify(StringFormat("Drawdown recovered to %.2f%% -> EA RESUMED", ddPct));
   }

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != gDayStart)
   {
      gDayStart       = today;
      gDayStartEquity = equity;
      if(gDailyStopped) Notify("New trading day -> daily stop reset");
      gDailyStopped   = false;
   }

   if(!gDailyStopped && gDayStartEquity > 0.0)
   {
      double dailyLoss = (gDayStartEquity - equity)/gDayStartEquity*100.0;
      if(dailyLoss >= InpDailyDD_Percent)
      {
         gDailyStopped = true;
         Notify(StringFormat("DAILY DRAWDOWN %.2f%% >= %.2f%% -> trading stopped for today",
                            dailyLoss, InpDailyDD_Percent));
      }
   }
}

//==================================================================
//  Protection: news filter
//==================================================================
bool IsWatchedCurrency(const string ccy)
{
   string parts[];
   int n = StringSplit(InpNewsCurrencies, ',', parts);
   for(int i=0; i<n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p); StringTrimRight(p);
      if(StringCompare(p, ccy, false) == 0)
         return true;
   }
   return false;
}

bool IsNewsBlocking()
{
   if(!InpEnableNewsFilter) return false;

   datetime now  = TimeCurrent();
   datetime from = now - (datetime)(InpNewsMinutesAfter * 60);
   datetime to   = now + (datetime)(InpNewsMinutesBefore * 60);

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to, NULL, NULL);
   if(total <= 0) return false;   // calendar unavailable (tester) -> don't block

   for(int i=0; i<total; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)  continue;

      MqlCalendarCountry country;
      string ccy = "";
      if(CalendarCountryById(ev.country_id, country))
         ccy = country.currency;
      if(ccy != "" && !IsWatchedCurrency(ccy)) continue;

      datetime evTime = values[i].time;
      if(evTime >= now - InpNewsMinutesAfter*60 && evTime <= now + InpNewsMinutesBefore*60)
         return true;
   }
   return false;
}

void UpdateNewsState()
{
   bool blocking = IsNewsBlocking();
   if(blocking && !gInNews)
   {
      gInNews = true;
      Notify("NEWS filter ON - high-impact event window, trading paused");
   }
   else if(!blocking && gInNews)
   {
      gInNews = false;
      Notify("NEWS filter OFF - trading resumed");
   }
}

//==================================================================
//  Trading gate
//==================================================================
bool TradingAllowed()
{
   if(gMaxDDPaused)  return false;
   if(gDailyStopped) return false;
   if(gInNews)       return false;
   if(CountMyPositions() >= InpMaxPositions) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   return true;
}

int CountMyPositions()
{
   int cnt = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)==InpMagic &&
         PositionGetString(POSITION_SYMBOL)==_Symbol)
         cnt++;
   }
   return cnt;
}

//==================================================================
//  Order open  (SL passed explicitly; no fixed TP)
//==================================================================
void OpenTrade(const ENUM_ORDER_TYPE type, const double slPrice)
{
   double price = (type==ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                         : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double riskDist = MathAbs(price - slPrice);
   if(riskDist <= 0.0)
   {
      Print("Invalid SL distance - skipping entry");
      return;
   }

   // respect broker minimum stop distance
   long   stopsLevel = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * _Point;
   if(riskDist < minDist)
   {
      double buf = minDist - riskDist;
      if(type==ORDER_TYPE_BUY) riskDist += buf; // widen to legal distance
      else                     riskDist += buf;
   }
   double sl = (type==ORDER_TYPE_BUY) ? price - riskDist : price + riskDist;

   double lots = CalcLotSize(riskDist);
   if(lots <= 0.0)
   {
      Print("Lot size computed as 0 - skipping entry");
      return;
   }

   sl = NormalizeDouble(sl, _Digits);
   bool ok = (type==ORDER_TYPE_BUY) ? trade.Buy(lots, _Symbol, price, sl, 0.0, "IFVG+")
                                    : trade.Sell(lots, _Symbol, price, sl, 0.0, "IFVG+");
   if(!ok)
   {
      Print("Order send failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return;
   }
   Notify(StringFormat("OPEN %s %.2f lots @ %.2f  SL %.2f  (risk %.0f pts)",
          (type==ORDER_TYPE_BUY?"BUY":"SELL"), lots, price, sl, riskDist/_Point));
}

//==================================================================
//  Lot sizing (risk-based, cent-account aware)
//==================================================================
double CalcLotSize(const double riskDist)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || riskDist <= 0.0)
      return 0.0;

   double lossPerLot = (riskDist / tickSize) * tickValue;
   if(lossPerLot <= 0.0) return 0.0;

   double lots = riskMoney / lossPerLot;
   return NormalizeVolume(lots);
}

double NormalizeVolume(double vol)
{
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;

   vol = MathFloor(vol/step) * step;
   if(vol < minV) vol = minV;
   if(vol > maxV) vol = maxV;

   int digits = (int)MathRound(MathLog10(1.0/step));
   if(digits < 0) digits = 0;
   return NormalizeDouble(vol, digits);
}

//==================================================================
//  Per-position state
//==================================================================
int FindPosStateIndex(const ulong ticket)
{
   for(int i=0; i<ArraySize(gPosTicket); i++)
      if(gPosTicket[i]==ticket) return i;
   return -1;
}

void AddPosState(const ulong ticket, const double risk, const double vol)
{
   int n = ArraySize(gPosTicket);
   ArrayResize(gPosTicket,      n+1);
   ArrayResize(gPosInitRisk,    n+1);
   ArrayResize(gPosInitVol,     n+1);
   ArrayResize(gPosBEDone,      n+1);
   ArrayResize(gPosPartialDone, n+1);
   gPosTicket[n]      = ticket;
   gPosInitRisk[n]    = risk;
   gPosInitVol[n]     = vol;
   gPosBEDone[n]      = false;
   gPosPartialDone[n] = false;
}

void RemovePosStateAt(const int idx)
{
   int n = ArraySize(gPosTicket);
   if(idx<0 || idx>=n) return;
   for(int i=idx; i<n-1; i++)
   {
      gPosTicket[i]      = gPosTicket[i+1];
      gPosInitRisk[i]    = gPosInitRisk[i+1];
      gPosInitVol[i]     = gPosInitVol[i+1];
      gPosBEDone[i]      = gPosBEDone[i+1];
      gPosPartialDone[i] = gPosPartialDone[i+1];
   }
   ArrayResize(gPosTicket,      n-1);
   ArrayResize(gPosInitRisk,    n-1);
   ArrayResize(gPosInitVol,     n-1);
   ArrayResize(gPosBEDone,      n-1);
   ArrayResize(gPosPartialDone, n-1);
}

void SyncPositionState()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)  continue;

      if(FindPosStateIndex(t) < 0)
      {
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl   = PositionGetDouble(POSITION_SL);
         double risk = (sl>0.0) ? MathAbs(open - sl) : 0.0;
         double vol  = PositionGetDouble(POSITION_VOLUME);
         AddPosState(t, risk, vol);
      }
   }
   for(int i=ArraySize(gPosTicket)-1; i>=0; i--)
      if(!PositionSelectByTicket(gPosTicket[i]))
         RemovePosStateAt(i);
}

//==================================================================
//  Trade management: BE, partial, trailing
//==================================================================
void ManageOpenPositions()
{
   for(int i=ArraySize(gPosTicket)-1; i>=0; i--)
   {
      ulong ticket = gPosTicket[i];
      if(!PositionSelectByTicket(ticket)) continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      double R    = gPosInitRisk[i];
      if(R <= 0.0) continue;

      bool   isBuy = (type==POSITION_TYPE_BUY);
      double cur   = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitDist = isBuy ? (cur - open) : (open - cur);

      // ---- Break-even ----
      if(!gPosBEDone[i] && profitDist >= InpBreakEvenR * R)
      {
         double buf  = InpBE_BufferPts * _Point;
         double beSL = isBuy ? open + buf : open - buf;
         if(ModifySL(ticket, isBuy, beSL, sl))
         {
            gPosBEDone[i] = true;
            sl = beSL;
            Notify(StringFormat("Break-even set #%I64u @ %.2f", ticket, beSL));
         }
      }

      // ---- Partial close ----
      if(!gPosPartialDone[i] && profitDist >= InpPartialR * R)
      {
         double closeVol = NormalizeVolume(gPosInitVol[i] * (InpPartialPercent/100.0));
         double minV     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(closeVol >= minV && (vol - closeVol) >= minV)
         {
            if(trade.PositionClosePartial(ticket, closeVol))
            {
               gPosPartialDone[i] = true;
               Notify(StringFormat("Partial close %.2f lots #%I64u @ 1R", closeVol, ticket));
            }
         }
         else gPosPartialDone[i] = true;
      }

      // ---- Trailing ----
      double newSL = ComputeTrailingSL(isBuy, cur);
      if(newSL > 0.0)
         ModifySL(ticket, isBuy, newSL, sl);
   }
}

// Most protective trailing SL among layers, or 0 if none valid.
double ComputeTrailingSL(const bool isBuy, const double price)
{
   double candidates[];
   int    c = 0;

   double atr1, atr2;
   if(BufVal(hATR1,0,0,atr1) && atr1>0.0)
   {
      double s = isBuy ? price - atr1*InpTr1_ATRMult : price + atr1*InpTr1_ATRMult;
      ArrayResize(candidates, c+1); candidates[c++] = s;
   }
   if(BufVal(hATR2,0,0,atr2) && atr2>0.0)
   {
      double s = isBuy ? price - atr2*InpTr2_ATRMult : price + atr2*InpTr2_ATRMult;
      ArrayResize(candidates, c+1); candidates[c++] = s;
   }

   if(isBuy)
   {
      int idx = iLowest(_Symbol, InpTrailTF, MODE_LOW, InpSwingLookback, 1);
      if(idx>=0){ double s=iLow(_Symbol,InpTrailTF,idx); ArrayResize(candidates,c+1); candidates[c++]=s; }
      double s3 = iLow(_Symbol, InpTrailTF, InpCandleBackShift);
      if(s3>0.0){ ArrayResize(candidates,c+1); candidates[c++]=s3; }
   }
   else
   {
      int idx = iHighest(_Symbol, InpTrailTF, MODE_HIGH, InpSwingLookback, 1);
      if(idx>=0){ double s=iHigh(_Symbol,InpTrailTF,idx); ArrayResize(candidates,c+1); candidates[c++]=s; }
      double s3 = iHigh(_Symbol, InpTrailTF, InpCandleBackShift);
      if(s3>0.0){ ArrayResize(candidates,c+1); candidates[c++]=s3; }
   }

   if(c==0) return 0.0;

   double best = 0.0; bool have = false;
   for(int i=0;i<c;i++)
   {
      double s = candidates[i];
      if(isBuy)
      {
         if(s >= price) continue;
         if(!have || s > best){ best=s; have=true; }
      }
      else
      {
         if(s <= price) continue;
         if(!have || s < best){ best=s; have=true; }
      }
   }
   return have ? best : 0.0;
}

// Tighten-only SL modify, respecting broker stop distance.
bool ModifySL(const ulong ticket, const bool isBuy, double newSL, const double curSL)
{
   if(newSL <= 0.0) return false;

   long   stopsLevel = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * _Point;
   double price      = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(isBuy  && (price - newSL) < minDist) return false;
   if(!isBuy && (newSL - price) < minDist) return false;

   if(curSL > 0.0)
   {
      if(isBuy  && newSL <= curSL + _Point) return false;
      if(!isBuy && newSL >= curSL - _Point) return false;
   }

   newSL = NormalizeDouble(newSL, _Digits);
   if(!PositionSelectByTicket(ticket)) return false;
   double tp = PositionGetDouble(POSITION_TP);
   return trade.PositionModify(ticket, newSL, tp);
}
//+------------------------------------------------------------------+
