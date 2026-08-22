//+------------------------------------------------------------------+
//|                          Metasit_ElliottWave_DualSwing_EA.mq5     |
//|        Elliott Wave Dual Swing Trading Strategy (Buy + Sell)      |
//|                                                                   |
//|  Step 1  Input setup      : ADX multi-TF, dual ZigZag, wave ratio |
//|                             rules, TP/SL mode, entry mode, step   |
//|                             trailing stop                          |
//|  Step 2  ADX validation   : optional 3-timeframe ADX gate         |
//|  Step 3  Swing detection  : Major ZigZag (P0/P1/P2) + Minor       |
//|                             ZigZag (1-2-3-4-5 / a-b-c) + drawing  |
//|  Step 4  Phase 1 check    : impulse rules on waves 1..5           |
//|  Step 5  Phase 2 check    : correction rules a-b-c (6-7-c)        |
//|  Step 6  Execution        : Market confirmation entry or multi    |
//|                             Limit ladder + TP/SL + trailing       |
//|                                                                   |
//|  Both directions share ONE rule engine: every price comparison is |
//|  normalised through "dir" (+1 = long setup, -1 = short setup), so |
//|  the short side cannot drift out of sync with the long side.      |
//+------------------------------------------------------------------+
#property copyright "Metasit - Elliott Wave Dual Swing"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//==================================================================
//  Enums
//==================================================================
enum ENUM_EW_DIRECTION
{
   EW_DIR_BUY  = 0,        // Buy only
   EW_DIR_SELL = 1,        // Sell only
   EW_DIR_BOTH = 2         // Both (one side at a time, no hedging)
};

enum ENUM_EW_ENTRY_MODE
{
   EW_ENTRY_MARKET  = 0,   // Mode 1: Market entry after reversal confirmation
   EW_ENTRY_PENDING = 1    // Mode 2: Multi Limit ladder on Fib of P0->P1
};

enum ENUM_EW_TP_MODE
{
   EW_TP_FIB    = 0,       // Fibonacci extension of P0->P1 projected from P2
   EW_TP_POINTS = 1        // Custom fixed points
};

enum ENUM_EW_SL_MODE
{
   EW_SL_WAVE   = 0,       // Wave level (beyond P2 or beyond Fib 78.5%)
   EW_SL_POINTS = 1        // Custom fixed points
};

enum ENUM_EW_SL_ANCHOR
{
   EW_SLA_P2   = 0,        // Beyond P2
   EW_SLA_FIB  = 1         // Beyond the Fib retracement level (default 78.5%)
};

//==================================================================
//  Step 1 : Inputs
//==================================================================
input group "=== General ==="
input long              InpMagic            = 20260822;      // Magic number
input ENUM_EW_DIRECTION InpDirection        = EW_DIR_BOTH;   // Trade direction
input ENUM_TIMEFRAMES   InpWorkTF           = PERIOD_CURRENT;// Working timeframe for wave analysis
input int               InpBarsToScan       = 1500;          // Bars scanned by the ZigZag engines
input int               InpMaxSpreadPoints  = 60;            // Skip entries if spread > this (0 = off)
input int               InpMaxPositions     = 3;             // Max simultaneous positions
input bool              InpAllowOpposite    = false;         // Allow a new setup while the opposite side is open
input bool              InpEnableNotify     = true;          // Send push notifications
input string            InpNotifPrefix      = "[EW-DUAL] "; // Notification prefix

input group "=== Step 1 : ADX Multi-TF filter ==="
input bool              InpUseAdxFilter     = true;          // Enable ADX filter (off = always PASS)
input ENUM_TIMEFRAMES   InpAdxTF1           = PERIOD_H4;     // ADX timeframe 1
input int               InpAdxLen1          = 14;            // ADX length 1
input double            InpAdxThreshold1    = 20.0;          // ADX threshold 1 (ADX >)
input ENUM_TIMEFRAMES   InpAdxTF2           = PERIOD_H1;     // ADX timeframe 2
input int               InpAdxLen2          = 14;            // ADX length 2
input double            InpAdxThreshold2    = 20.0;          // ADX threshold 2 (ADX >)
input ENUM_TIMEFRAMES   InpAdxTF3           = PERIOD_M15;    // ADX timeframe 3
input int               InpAdxLen3          = 14;            // ADX length 3
input double            InpAdxThreshold3    = 20.0;          // ADX threshold 3 (ADX >)

input group "=== Step 1 : Dual ZigZag ==="
input int               InpMajorDepth       = 24;            // Major swing: depth (bars each side)
input int               InpMajorDeviation   = 800;           // Major swing: min deviation (points)
input int               InpMinorDepth       = 6;             // Minor swing: depth (bars each side)
input int               InpMinorDeviation   = 200;           // Minor swing: min deviation (points)

input group "=== Step 1 : Elliott wave ratio rules ==="
input double            InpWave2MaxRetrPct  = 87.5;          // Wave 2: max retracement of wave 1 (%)
input double            InpWave4MaxOverlapPct = 60.0;        // Wave 4: max overlap into wave 2 area (%)
input double            InpP2MaxRetrPct     = 78.5;          // P2: max retracement of P0->P1 (%)
input double            InpP2MinRetrPct     = 61.8;          // P2: min retracement of P0->P1 (%) (entry zone)
input bool              InpRequireBuyZone   = true;          // Require P2 inside the min..max retracement zone

input group "=== Step 1 : Take Profit ==="
input ENUM_EW_TP_MODE   InpTPMode           = EW_TP_FIB;     // Take Profit mode
input double            InpTPFibExtension   = 161.8;         // Fib extension of P0->P1 from P2 (%)
input int               InpTPPoints         = 5000;          // Custom TP distance (points)

input group "=== Step 1 : Stop Loss ==="
input ENUM_EW_SL_MODE   InpSLMode           = EW_SL_WAVE;    // Stop Loss mode
input ENUM_EW_SL_ANCHOR InpSLAnchor         = EW_SLA_P2;     // Wave level anchor
input double            InpSLFibPct         = 78.5;          // Fib level used when anchor = Fib (%)
input int               InpSLBufferPoints   = 300;           // Buffer beyond the wave level (points)
input int               InpSLPoints         = 2000;          // Custom SL distance (points)

input group "=== Step 1 : Entry strategy ==="
input ENUM_EW_ENTRY_MODE InpEntryMode       = EW_ENTRY_MARKET;// Entry mode
input bool              InpEntryOnBreak     = false;         // Mode 1: enter on break of the reversal bar extreme
input bool              InpUsePinBar        = true;          // Mode 1: accept pin bar / shooting star
input bool              InpUseEngulfing     = true;          // Mode 1: accept engulfing
input bool              InpUseHigherHigh    = true;          // Mode 1: accept HH+HL (buy) / LH+LL (sell)
input int               InpReversalZonePts  = 1500;          // Mode 1: max distance of the signal bar extreme from P2 (points)
input int               InpPendingCount     = 3;             // Mode 2: number of Limit orders (1-3)
input double            InpPendingFib1      = 61.8;          // Mode 2: Fib % of order 1
input double            InpPendingFib2      = 78.6;          // Mode 2: Fib % of order 2
input double            InpPendingFib3      = 81.0;          // Mode 2: Fib % of order 3
input int               InpPendingExpiryBars= 60;            // Mode 2: cancel pendings after N bars (0 = never)
input bool              InpSplitRisk        = true;          // Mode 2: split risk % across the ladder

input group "=== Step 1 : Risk ==="
input double            InpRiskPercent      = 1.0;           // Risk per setup (% of balance)
input double            InpFixedLots        = 0.0;           // Fixed lots (>0 overrides risk %)
input double            InpLotStepOverride  = 0.0;           // Force lot step (0 = broker)

input group "=== Step 1 : Step trailing stop ==="
input bool              InpUseStepTrail     = true;          // Enable step trailing stop
input int               InpTrailTriggerPts  = 500;           // Trigger distance (points in profit)
input int               InpTrailLockPts     = 300;           // Initial locked profit (points)
input int               InpTrailStepPts     = 200;           // Step move distance (points)

input group "=== Step 3 : Visual ==="
input bool              InpDrawSwings       = true;          // Draw swings on the chart
input bool              InpShowPanel        = true;          // Show status panel (chart comment)
input color             InpBuyColor         = clrDodgerBlue; // Major swing colour (buy setup)
input color             InpSellColor        = clrTomato;     // Major swing colour (sell setup)
input color             InpMinorColor       = clrOrange;     // Minor swing colour
input color             InpLabelColor       = clrWhite;      // Label colour
input int               InpMajorWidth       = 3;             // Major swing line width
input int               InpMinorWidth       = 1;             // Minor swing line width

//==================================================================
//  Types
//==================================================================
struct SPivot
{
   datetime time;       // bar time of the extremum
   double   price;      // extremum price
   int      idx;        // chronological index inside the scanned window
   bool     isHigh;     // true = swing high, false = swing low
   bool     confirmed;  // false = provisional (still forming)
};

struct SSetup
{
   int      dir;          // +1 = long setup, -1 = short setup
   bool     majorOK;      // P0/P1/P2 found
   bool     phase1;       // Step 4 passed
   bool     phase2;       // Step 5 passed
   bool     zoneOK;       // P2 inside the retracement zone
   bool     cEqualsP2;    // minor wave c ends at the major P2
   double   p0, p1, p2;
   datetime t0, t1, t2;
   double   wPrice[6];    // P0, w1, w2, w3, w4, w5(=P1)
   datetime wTime[6];
   double   cPrice[3];    // a, b, c
   datetime cTime[3];
   double   retrPct;      // retracement of P0->P1 at P2
   string   note;         // reason of the last rejection
};

//==================================================================
//  Globals
//==================================================================
CTrade           trade;
ENUM_TIMEFRAMES  gTF          = PERIOD_CURRENT;
int              hAdx[3]      = {INVALID_HANDLE, INVALID_HANDLE, INVALID_HANDLE};
double           gAdxVal[3]   = {0.0, 0.0, 0.0};
bool             gAdxPass     = false;

SSetup           gSetup;
SPivot           gMajor[];
SPivot           gMinor[];
string           gNoteBuy     = "";
string           gNoteSell    = "";

datetime         gLastBar     = 0;
datetime         gDoneSigM1   = 0;      // P2 time already traded (mode 1)
int              gDoneDirM1   = 0;
datetime         gDoneSigM2   = 0;      // P1 time already laddered (mode 2)
int              gDoneDirM2   = 0;
datetime         gPendingSig  = 0;      // P1 time of the live pending ladder
datetime         gPendingTime = 0;      // when the ladder was placed
double           gPendingP0   = 0.0;    // invalidation level of the live ladder
int              gPendingDir  = 0;      // direction of the live ladder
double           gBreakTrigger= 0.0;    // armed "break of the reversal extreme" price
datetime         gBreakArmed  = 0;      // P2 time the trigger belongs to
int              gBreakDir    = 0;      // direction of the armed trigger
string           gPrefix      = "EWDS_";

//==================================================================
//  Small helpers
//==================================================================
void Notify(const string msg)
{
   Print(msg);
   if(InpEnableNotify)
      SendNotification(InpNotifPrefix + msg);
}

double PointSize()
{
   double p = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (p > 0.0 ? p : 0.01);
}

double Ask() { return SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
double Bid() { return SymbolInfoDouble(_Symbol, SYMBOL_BID); }

// entry side price for a direction: buy pays the ask, sell hits the bid
double SidePrice(const int dir) { return (dir > 0 ? Ask() : Bid()); }

double NormPrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

long StopsLevelPoints()
{
   long lvl = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(lvl < 0) lvl = 0;
   return lvl;
}

string DirName(const int dir) { return (dir > 0 ? "BUY" : "SELL"); }

//==================================================================
//  Init / Deinit
//==================================================================
int OnInit()
{
   gTF = (InpWorkTF == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : InpWorkTF);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(30);

   if(InpUseAdxFilter)
   {
      hAdx[0] = iADX(_Symbol, InpAdxTF1, (int)MathMax(2, InpAdxLen1));
      hAdx[1] = iADX(_Symbol, InpAdxTF2, (int)MathMax(2, InpAdxLen2));
      hAdx[2] = iADX(_Symbol, InpAdxTF3, (int)MathMax(2, InpAdxLen3));
      for(int i=0; i<3; i++)
         if(hAdx[i] == INVALID_HANDLE)
         {
            Print("Failed to create ADX handle #", i);
            return(INIT_FAILED);
         }
   }

   if(InpMajorDepth < 2 || InpMinorDepth < 2)
   {
      Print("Depth must be >= 2 for both ZigZag engines");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpMinorDepth >= InpMajorDepth)
      Print("WARNING: minor depth >= major depth - the two swings will look alike");

   ResetSetup(gSetup, 1);
   Notify("Elliott Wave Dual Swing EA started on " + _Symbol +
          " (" + EnumToString(gTF) + ", " + DirectionName() + ")");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int i=0; i<3; i++)
      if(hAdx[i] != INVALID_HANDLE)
         IndicatorRelease(hAdx[i]);

   ObjectsDeleteAll(0, gPrefix);
   if(InpShowPanel) Comment("");
   ChartRedraw();
   Print("Elliott Wave Dual Swing EA stopped (reason ", reason, ")");
}

string DirectionName()
{
   switch(InpDirection)
   {
      case EW_DIR_BUY:  return "Buy only";
      case EW_DIR_SELL: return "Sell only";
      default:          return "Both";
   }
}

void ResetSetup(SSetup &s, const int dir)
{
   s.dir       = dir;
   s.majorOK   = false;
   s.phase1    = false;
   s.phase2    = false;
   s.zoneOK    = false;
   s.cEqualsP2 = false;
   s.p0 = 0.0; s.p1 = 0.0; s.p2 = 0.0;
   s.t0 = 0;   s.t1 = 0;   s.t2 = 0;
   s.retrPct = 0.0;
   s.note = "no data";
   for(int i=0; i<6; i++) { s.wPrice[i] = 0.0; s.wTime[i] = 0; }
   for(int i=0; i<3; i++) { s.cPrice[i] = 0.0; s.cTime[i] = 0; }
}

//==================================================================
//  Main loop
//==================================================================
void OnTick()
{
   // Step 6c - trailing runs on every tick
   ManageStepTrailing();

   // Mode 1 with "enter on break of the reversal bar extreme"
   CheckArmedBreakout();

   datetime curBar = (datetime)iTime(_Symbol, gTF, 0);
   if(curBar == gLastBar)
      return;
   gLastBar = curBar;

   // Step 2 - ADX validation
   gAdxPass = AdxValid();

   // Step 3/4/5 - swings, impulse, correction
   AnalyzeStructure();

   if(InpDrawSwings) DrawStructure();
   if(InpShowPanel)  ShowPanel();

   // Step 6 - housekeeping first, then execution
   ManagePendingLadder();

   if(!TradingAllowed(gSetup.dir))
      return;

   if(InpEntryMode == EW_ENTRY_PENDING)
      TryPlacePendingLadder();
   else
      TryMarketEntry();
}

bool TradingAllowed(const int dir)
{
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))          return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))return false;
   if(!gAdxPass)                                   return false;
   if(CountMyPositions(0) >= InpMaxPositions)      return false;

   // never open a setup against live exposure unless explicitly allowed
   if(!InpAllowOpposite && dir != 0)
      if(CountMyPositions(-dir) > 0 || CountMyPendings(-dir) > 0)
         return false;

   if(InpMaxSpreadPoints > 0)
   {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPoints) return false;
   }
   return true;
}

// dir: +1 = longs, -1 = shorts, 0 = any
int CountMyPositions(const int dir)
{
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)  continue;
      if(dir != 0)
      {
         long type = PositionGetInteger(POSITION_TYPE);
         int  pdir = (type == POSITION_TYPE_BUY ? 1 : -1);
         if(pdir != dir) continue;
      }
      cnt++;
   }
   return cnt;
}

int CountMyPendings(const int dir)
{
   int cnt = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)  continue;
      if(dir != 0)
      {
         long type = OrderGetInteger(ORDER_TYPE);
         int  odir = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP ||
                      type == ORDER_TYPE_BUY ? 1 : -1);
         if(odir != dir) continue;
      }
      cnt++;
   }
   return cnt;
}

//==================================================================
//  Step 2 : ADX validation
//==================================================================
bool AdxValid()
{
   if(!InpUseAdxFilter)
   {
      gAdxVal[0] = gAdxVal[1] = gAdxVal[2] = 0.0;
      return true;                       // filter off -> PASS
   }

   double thr[3];
   thr[0] = InpAdxThreshold1;
   thr[1] = InpAdxThreshold2;
   thr[2] = InpAdxThreshold3;

   bool pass = true;
   for(int i=0; i<3; i++)
   {
      double buf[];
      if(CopyBuffer(hAdx[i], 0, 1, 1, buf) < 1)   // MAIN line of the last closed bar
      {
         gAdxVal[i] = 0.0;
         pass = false;
         continue;
      }
      gAdxVal[i] = buf[0];
      if(gAdxVal[i] <= thr[i]) pass = false;
   }
   return pass;
}

//==================================================================
//  Step 3 : ZigZag engine (self contained, no iCustom dependency)
//==================================================================
// Builds an alternating high/low pivot list in chronological order.
// The last element may be provisional (the swing that is still forming),
// which is what lets P2 be recognised while it develops.
bool BuildZigZag(const ENUM_TIMEFRAMES tf, const int depth, const int deviationPts,
                 const int barsToScan, SPivot &piv[])
{
   ArrayFree(piv);

   int total = Bars(_Symbol, tf);
   int n     = (int)MathMin(barsToScan, total);
   if(n < depth*2 + 10) return false;

   double   hi[], lo[];
   datetime tm[];
   ArraySetAsSeries(hi, false);
   ArraySetAsSeries(lo, false);
   ArraySetAsSeries(tm, false);

   if(CopyHigh(_Symbol, tf, 0, n, hi) < n) return false;
   if(CopyLow (_Symbol, tf, 0, n, lo) < n) return false;
   if(CopyTime(_Symbol, tf, 0, n, tm) < n) return false;

   double devPrice = deviationPts * PointSize();
   int    count    = 0;

   for(int i = depth; i <= n-1-depth; i++)
   {
      bool isH = true, isL = true;
      for(int k = i-depth; k <= i+depth && (isH || isL); k++)
      {
         if(k == i) continue;
         if(k < i)                              // left side: strict
         {
            if(hi[k] >  hi[i]) isH = false;
            if(lo[k] <  lo[i]) isL = false;
         }
         else                                   // right side: ties reject
         {
            if(hi[k] >= hi[i]) isH = false;
            if(lo[k] <= lo[i]) isL = false;
         }
      }
      if(!isH && !isL) continue;

      // an outside bar can flag both - keep the one that alternates
      bool takeHigh;
      if(isH && isL)
         takeHigh = (count > 0 ? !piv[count-1].isHigh : true);
      else
         takeHigh = isH;

      SPivot c;
      c.time      = tm[i];
      c.price     = (takeHigh ? hi[i] : lo[i]);
      c.idx       = i;
      c.isHigh    = takeHigh;
      c.confirmed = true;

      if(count == 0)
      {
         ArrayResize(piv, 1);
         piv[0] = c;
         count  = 1;
         continue;
      }

      if(c.isHigh == piv[count-1].isHigh)
      {
         // same direction -> keep the more extreme of the two
         if((c.isHigh  && c.price > piv[count-1].price) ||
            (!c.isHigh && c.price < piv[count-1].price))
            piv[count-1] = c;
      }
      else
      {
         if(MathAbs(c.price - piv[count-1].price) < devPrice)
            continue;                            // swing too small
         ArrayResize(piv, count+1);
         piv[count] = c;
         count++;
      }
   }

   if(count == 0) return false;

   // provisional pivot: running extreme from the last confirmed pivot to bar 0
   int    startIdx = piv[count-1].idx + 1;
   bool   wantHigh = !piv[count-1].isHigh;
   int    bestIdx  = -1;
   double bestVal  = 0.0;

   for(int i = startIdx; i <= n-1; i++)
   {
      double v = (wantHigh ? hi[i] : lo[i]);
      if(bestIdx < 0 || (wantHigh && v > bestVal) || (!wantHigh && v < bestVal))
      {
         bestIdx = i;
         bestVal = v;
      }
   }
   if(bestIdx >= 0 && MathAbs(bestVal - piv[count-1].price) >= devPrice)
   {
      SPivot p;
      p.time      = tm[bestIdx];
      p.price     = bestVal;
      p.idx       = bestIdx;
      p.isHigh    = wantHigh;
      p.confirmed = false;
      ArrayResize(piv, count+1);
      piv[count]  = p;
   }
   return true;
}

// Collect the pivots of an inner leg, boundaries included.
int CollectPivots(const SPivot &src[], const datetime from, const datetime to, SPivot &dst[])
{
   ArrayFree(dst);
   int cnt = 0;
   for(int i = 0; i < ArraySize(src); i++)
   {
      if(src[i].time < from || src[i].time > to) continue;
      ArrayResize(dst, cnt+1);
      dst[cnt] = src[i];
      cnt++;
   }
   return cnt;
}

// Reduce an alternating pivot list down to "target" elements by dropping the
// least significant interior pair - this folds sub-divisions back into the
// parent 5-wave / 3-wave count instead of rejecting the whole setup.
int SimplifySequence(SPivot &seq[], const int target)
{
   int n = ArraySize(seq);
   while(n > target && n >= 4)
   {
      int    bestI   = -1;
      double bestAmp = 0.0;
      for(int i = 1; i <= n-3; i++)              // keep both boundary pivots
      {
         double amp = MathAbs(seq[i+1].price - seq[i].price);
         if(bestI < 0 || amp < bestAmp)
         {
            bestI   = i;
            bestAmp = amp;
         }
      }
      if(bestI < 0) break;

      for(int k = bestI; k <= n-3; k++)
         seq[k] = seq[k+2];
      n -= 2;
      ArrayResize(seq, n);
   }
   return n;
}

// Minor pivots rarely land on exactly the same bar as the major extremes, so
// the leg is collected with a tolerance window and then trimmed back to the
// expected shape (first pivot type / last pivot type).
void TrimEnds(SPivot &seq[], const bool firstIsHigh, const bool lastIsHigh)
{
   int n = ArraySize(seq);
   int start = 0;
   while(start < n && seq[start].isHigh != firstIsHigh) start++;
   if(start >= n)
   {
      ArrayFree(seq);
      return;
   }
   if(start > 0)
   {
      for(int k = 0; k + start < n; k++) seq[k] = seq[k+start];
      n -= start;
      ArrayResize(seq, n);
   }
   while(n > 0 && seq[n-1].isHigh != lastIsHigh)
   {
      n--;
      ArrayResize(seq, n);
   }
}

datetime LegTolerance(const int depth)
{
   return (datetime)(PeriodSeconds(gTF) * (depth + 1));
}

bool AlternatesFrom(const SPivot &seq[], const bool firstIsHigh)
{
   for(int i = 0; i < ArraySize(seq); i++)
   {
      bool want = (i % 2 == 0 ? firstIsHigh : !firstIsHigh);
      if(seq[i].isHigh != want) return false;
   }
   return true;
}

//==================================================================
//  Step 3/4/5 : structure analysis
//==================================================================
// How complete a setup is - used to pick a side in EW_DIR_BOTH mode.
int SetupScore(const SSetup &s)
{
   if(s.phase2)  return 3;
   if(s.phase1)  return 2;
   if(s.majorOK) return 1;
   return 0;
}

void AnalyzeStructure()
{
   SSetup empty;
   ResetSetup(empty, 1);

   if(!BuildZigZag(gTF, InpMajorDepth, InpMajorDeviation, InpBarsToScan, gMajor))
   {
      empty.note = "major zigzag: not enough bars";
      gSetup = empty; gNoteBuy = empty.note; gNoteSell = empty.note;
      return;
   }
   if(!BuildZigZag(gTF, InpMinorDepth, InpMinorDeviation, InpBarsToScan, gMinor))
   {
      empty.note = "minor zigzag: not enough bars";
      gSetup = empty; gNoteBuy = empty.note; gNoteSell = empty.note;
      return;
   }

   SSetup sBuy, sSell;
   bool   doBuy  = (InpDirection == EW_DIR_BUY  || InpDirection == EW_DIR_BOTH);
   bool   doSell = (InpDirection == EW_DIR_SELL || InpDirection == EW_DIR_BOTH);

   ResetSetup(sBuy, 1);
   ResetSetup(sSell, -1);
   if(doBuy)  AnalyzeDirection(sBuy);
   if(doSell) AnalyzeDirection(sSell);

   gNoteBuy  = (doBuy  ? sBuy.note  : "disabled");
   gNoteSell = (doSell ? sSell.note : "disabled");

   if(!doSell)      gSetup = sBuy;
   else if(!doBuy)  gSetup = sSell;
   else
   {
      int scoreB = SetupScore(sBuy);
      int scoreS = SetupScore(sSell);
      if(scoreB > scoreS)      gSetup = sBuy;
      else if(scoreS > scoreB) gSetup = sSell;
      else                     gSetup = (sSell.t2 > sBuy.t2 ? sSell : sBuy);
   }
}

// Runs the whole rule chain for one direction (+1 long / -1 short).
void AnalyzeDirection(SSetup &s)
{
   if(!FindMajorSwing(s)) return;
   if(!CheckPhase1(s))    return;
   CheckPhase2(s);
}

// Major swing (long) : ... low(P0) -> high(P1) -> low(P2, may still be forming)
// Major swing (short): ... high(P0) -> low(P1) -> high(P2)
bool FindMajorSwing(SSetup &s)
{
   const int dir = s.dir;
   int n = ArraySize(gMajor);
   if(n < 3)
   {
      s.note = "major pivots < 3";
      return false;
   }

   int i2 = n-1;
   // for a long setup P2 is a low, for a short setup P2 is a high
   if(gMajor[i2].isHigh != (dir < 0))
   {
      s.note = "last major pivot is on the wrong side - waiting for the pullback";
      return false;
   }
   int i1 = i2-1;
   int i0 = i1-1;
   if(gMajor[i1].isHigh == gMajor[i2].isHigh || gMajor[i0].isHigh != gMajor[i2].isHigh)
   {
      s.note = "major pivots do not alternate";
      return false;
   }

   s.p0 = gMajor[i0].price; s.t0 = gMajor[i0].time;
   s.p1 = gMajor[i1].price; s.t1 = gMajor[i1].time;
   s.p2 = gMajor[i2].price; s.t2 = gMajor[i2].time;

   double range = dir * (s.p1 - s.p0);          // always positive when valid
   if(range <= 0.0)
   {
      s.note = "major swing P0->P1 runs the wrong way";
      return false;
   }
   if(dir * (s.p2 - s.p0) <= 0.0)
   {
      s.note = "P2 broke past P0 - structure invalid";
      return false;
   }

   s.retrPct = dir * (s.p1 - s.p2) / range * 100.0;
   if(s.retrPct > InpP2MaxRetrPct)
   {
      s.note = StringFormat("P2 retracement %.1f%% > max %.1f%%", s.retrPct, InpP2MaxRetrPct);
      return false;
   }
   s.zoneOK = (s.retrPct >= InpP2MinRetrPct && s.retrPct <= InpP2MaxRetrPct);

   s.majorOK = true;
   s.note    = "major swing OK";
   return true;
}

// Step 4 : impulse 1-2-3-4-5 between P0 and P1
bool CheckPhase1(SSetup &s)
{
   const int  dir      = s.dir;
   const bool startsHi = (dir < 0);            // short impulse starts at a high

   SPivot seg[];
   datetime tol = LegTolerance(InpMinorDepth);
   CollectPivots(gMinor, s.t0 - tol, s.t1 + tol, seg);
   TrimEnds(seg, startsHi, !startsHi);
   int c = ArraySize(seg);
   if(c < 6)
   {
      s.note = StringFormat("minor pivots in P0->P1 = %d (need 6) - loosen the minor zigzag", c);
      return false;
   }

   double tolPrice = 2.0 * InpMinorDeviation * PointSize();
   if(dir * seg[0].price   > dir * s.p0 + tolPrice ||
      dir * seg[c-1].price < dir * s.p1 - tolPrice)
   {
      s.note = "minor leg does not start at P0 / end at P1";
      return false;
   }

   c = SimplifySequence(seg, 6);
   if(c != 6 || !AlternatesFrom(seg, startsHi))
   {
      s.note = "minor structure in P0->P1 is not a clean 5-wave";
      return false;
   }

   for(int i=0; i<6; i++)
   {
      s.wPrice[i] = seg[i].price;
      s.wTime[i]  = seg[i].time;
   }

   double w0 = s.wPrice[0];   // start of wave 1 (P0 area)
   double w1 = s.wPrice[1];   // end of wave 1
   double w2 = s.wPrice[2];   // end of wave 2
   double w3 = s.wPrice[3];   // end of wave 3
   double w4 = s.wPrice[4];   // end of wave 4
   double w5 = s.wPrice[5];   // end of wave 5 (P1 area)

   double len1 = dir * (w1 - w0);
   double len3 = dir * (w3 - w2);
   double len5 = dir * (w5 - w4);
   if(len1 <= 0.0 || len3 <= 0.0 || len5 <= 0.0)
   {
      s.note = "impulse legs do not all run with the trend";
      return false;
   }

   // wave 2: does not break the start of wave 1, retracement within limit
   if(dir * (w2 - w0) <= 0.0)
   {
      s.note = "wave 2 broke past the start of wave 1";
      return false;
   }
   double retr2 = dir * (w1 - w2) / len1 * 100.0;
   if(retr2 > InpWave2MaxRetrPct)
   {
      s.note = StringFormat("wave 2 retracement %.1f%% > max %.1f%%", retr2, InpWave2MaxRetrPct);
      return false;
   }

   // wave 3: exceeds the end of wave 1 and is not the shortest of 1/3/5
   if(dir * (w3 - w1) <= 0.0)
   {
      s.note = "wave 3 did not exceed the end of wave 1";
      return false;
   }
   if(len3 < len1 && len3 < len5)
   {
      s.note = "wave 3 is the shortest of waves 1/3/5";
      return false;
   }

   // wave 4: stays out of wave 2 territory, overlap within limit
   if(dir * (w4 - w2) <= 0.0)
   {
      s.note = "wave 4 dropped into wave 2 territory";
      return false;
   }
   double zone = dir * (w1 - w2);               // wave 2 area measured from the wave 1 end
   if(zone > 0.0)
   {
      double overlap = dir * (w1 - w4) / zone * 100.0;
      if(overlap > InpWave4MaxOverlapPct)
      {
         s.note = StringFormat("wave 4 overlap %.1f%% > max %.1f%%", overlap, InpWave4MaxOverlapPct);
         return false;
      }
   }

   // wave 5 end must be the swing extreme (P1)
   if(dir * (w5 - w3) <= 0.0)
   {
      s.note = "wave 5 did not exceed the end of wave 3";
      return false;
   }

   s.phase1 = true;
   s.note   = "Phase 1 (1-2-3-4-5) OK";
   return true;
}

// Step 5 : correction a-b-c (waves 6-7-c) between P1 and P2
bool CheckPhase2(SSetup &s)
{
   const int  dir     = s.dir;
   const bool aIsHigh = (dir < 0);             // short correction bounces up: a is a high

   SPivot seg[];
   datetime tol = LegTolerance(InpMinorDepth);
   CollectPivots(gMinor, s.t1 + 1, s.t2 + tol, seg);

   // the leg must run a - b - c; drop P1 itself if it slipped inside
   TrimEnds(seg, aIsHigh, aIsHigh);
   int c = ArraySize(seg);
   if(c < 3)
   {
      s.note = StringFormat("minor pivots in P1->P2 = %d (need 3: a-b-c)", c);
      return false;
   }
   c = SimplifySequence(seg, 3);
   if(c != 3 || !AlternatesFrom(seg, aIsHigh))
   {
      s.note = "correction leg is not a clean a-b-c";
      return false;
   }

   for(int i=0; i<3; i++)
   {
      s.cPrice[i] = seg[i].price;
      s.cTime[i]  = seg[i].time;
   }

   double a  = s.cPrice[0];   // wave 6
   double b  = s.cPrice[1];   // wave 7
   double cc = s.cPrice[2];   // wave c = P2

   if(dir * (a - s.wPrice[4]) <= 0.0)
   {
      s.note = "wave a ran past the wave 4 extreme";
      return false;
   }
   if(dir * (b - s.p1) >= 0.0)
   {
      s.note = "wave b is not a lower high / higher low vs P1";
      return false;
   }
   if(dir * (cc - s.p0) <= 0.0)
   {
      s.note = "wave c broke past P0";
      return false;
   }
   double range = dir * (s.p1 - s.p0);
   double retrC = dir * (s.p1 - cc) / range * 100.0;
   if(retrC > InpP2MaxRetrPct)
   {
      s.note = StringFormat("wave c retracement %.1f%% > max %.1f%%", retrC, InpP2MaxRetrPct);
      return false;
   }

   // does wave c actually end on the major P2?
   double tolP = MathMax(InpMinorDeviation, 1) * PointSize();
   s.cEqualsP2 = (MathAbs(cc - s.p2) <= tolP);

   s.phase2 = true;
   s.note   = (s.cEqualsP2 ? "Phase 2 OK - c = P2 (entry zone)" : "Phase 2 OK");
   return true;
}

//==================================================================
//  Step 6 : reversal confirmation (Mode 1)
//==================================================================
bool ReversalSignal(const SSetup &s, string &desc)
{
   const int dir = s.dir;
   desc = "";

   double o1 = iOpen (_Symbol, gTF, 1), c1 = iClose(_Symbol, gTF, 1);
   double h1 = iHigh (_Symbol, gTF, 1), l1 = iLow  (_Symbol, gTF, 1);
   double o2 = iOpen (_Symbol, gTF, 2), c2 = iClose(_Symbol, gTF, 2);
   double h2 = iHigh (_Symbol, gTF, 2), l2 = iLow  (_Symbol, gTF, 2);
   if(o1 <= 0.0 || o2 <= 0.0) return false;

   // the signal bar has to sit at the P2 zone
   double zone    = InpReversalZonePts * PointSize();
   double extreme = (dir > 0 ? l1 : h1);
   if(MathAbs(extreme - s.p2) > zone)
      return false;

   double body  = MathAbs(c1 - o1);
   double range = h1 - l1;
   if(range <= 0.0) return false;

   if(InpUsePinBar)
   {
      // buy  : long lower wick, close in the upper third
      // sell : long upper wick, close in the lower third
      double wick = (dir > 0 ? MathMin(o1, c1) - l1 : h1 - MathMax(o1, c1));
      bool   closeOK = (dir > 0 ? (c1 >= h1 - range/3.0) : (c1 <= l1 + range/3.0));
      if(wick >= 2.0 * body && closeOK)
      {
         desc = (dir > 0 ? "pin bar" : "shooting star");
         return true;
      }
   }
   if(InpUseEngulfing)
   {
      bool engulf = (dir > 0 ? (c2 < o2 && c1 > o1 && c1 >= o2 && o1 <= c2)
                             : (c2 > o2 && c1 < o1 && c1 <= o2 && o1 >= c2));
      if(engulf)
      {
         desc = (dir > 0 ? "bullish engulfing" : "bearish engulfing");
         return true;
      }
   }
   if(InpUseHigherHigh)
   {
      bool shift = (dir > 0 ? (h1 > h2 && l1 > l2 && c1 > o1)
                            : (h1 < h2 && l1 < l2 && c1 < o1));
      if(shift)
      {
         desc = (dir > 0 ? "higher high / higher low" : "lower high / lower low");
         return true;
      }
   }
   return false;
}

void TryMarketEntry()
{
   const int dir = gSetup.dir;
   if(!gSetup.phase1 || !gSetup.phase2) return;
   if(InpRequireBuyZone && !gSetup.zoneOK) return;
   if(gSetup.t2 == gDoneSigM1 && dir == gDoneDirM1) return;   // already traded

   string desc;
   if(!ReversalSignal(gSetup, desc)) return;

   if(InpEntryOnBreak)
   {
      gBreakTrigger = (dir > 0 ? iHigh(_Symbol, gTF, 1) : iLow(_Symbol, gTF, 1));
      gBreakArmed   = gSetup.t2;
      gBreakDir     = dir;
      Notify(StringFormat("%s P2 reversal (%s) - armed break entry at %.2f",
                          DirName(dir), desc, gBreakTrigger));
      return;
   }

   double entry = SidePrice(dir);
   double sl    = ComputeSL(gSetup, entry);
   double tp    = ComputeTP(gSetup, entry);
   if(OpenMarketOrder(dir, sl, tp, "EW P2 " + desc))
   {
      gDoneSigM1 = gSetup.t2;
      gDoneDirM1 = dir;
   }
}

void CheckArmedBreakout()
{
   if(gBreakTrigger <= 0.0 || gBreakDir == 0) return;

   const int dir = gBreakDir;
   if(gBreakArmed != gSetup.t2 || dir != gSetup.dir ||
      (gDoneSigM1 == gSetup.t2 && gDoneDirM1 == dir))
   {
      gBreakTrigger = 0.0;                          // structure moved on
      gBreakDir     = 0;
      return;
   }
   if(!TradingAllowed(dir)) return;

   double price = SidePrice(dir);
   if(dir * (price - gBreakTrigger) <= 0.0) return; // not through the trigger yet

   double sl = ComputeSL(gSetup, price);
   double tp = ComputeTP(gSetup, price);
   if(OpenMarketOrder(dir, sl, tp, "EW P2 break"))
   {
      gDoneSigM1    = gSetup.t2;
      gDoneDirM1    = dir;
      gBreakTrigger = 0.0;
      gBreakDir     = 0;
   }
}

//==================================================================
//  Step 6 : TP / SL levels
//==================================================================
double ComputeSL(const SSetup &s, const double entry)
{
   const int dir = s.dir;
   double buf = InpSLBufferPoints * PointSize();

   if(InpSLMode == EW_SL_POINTS)
      return NormPrice(entry - dir * InpSLPoints * PointSize());

   double rng      = dir * (s.p1 - s.p0);
   double fibLevel = s.p1 - dir * (InpSLFibPct/100.0) * rng;
   double level    = (InpSLAnchor == EW_SLA_FIB ? fibLevel : s.p2);

   // a pending order can sit BEYOND the chosen wave level (e.g. the 81% rung
   // while P2 is only at 65%) - step out to the next structural level
   if(dir * (level - entry) >= 0.0)
   {
      level = (dir > 0 ? MathMin(fibLevel, s.p2) : MathMax(fibLevel, s.p2));
      if(dir * (level - entry) >= 0.0) level = s.p0;
   }

   double sl = level - dir * buf;
   // never on the wrong side of the entry
   if(dir * (entry - sl) <= 0.0)
      sl = entry - dir * MathMax(buf, PointSize()*10);
   return NormPrice(sl);
}

double ComputeTP(const SSetup &s, const double entry)
{
   const int dir = s.dir;

   if(InpTPMode == EW_TP_POINTS)
   {
      if(InpTPPoints <= 0) return 0.0;
      return NormPrice(entry + dir * InpTPPoints * PointSize());
   }

   double rng = dir * (s.p1 - s.p0);
   if(rng <= 0.0) return 0.0;

   // project the extension from whichever is further into the pullback:
   // the P2 extreme or the actual order price
   double anchor = (dir > 0 ? MathMin(s.p2, entry) : MathMax(s.p2, entry));
   double tp     = anchor + dir * (InpTPFibExtension/100.0) * rng;
   if(dir * (tp - entry) <= 0.0) return 0.0;
   return NormPrice(tp);
}

//==================================================================
//  Step 6 : order execution
//==================================================================
bool OpenMarketOrder(const int dir, double sl, double tp, const string comment)
{
   long   stops   = StopsLevelPoints();
   double minDist = stops * PointSize();
   double price   = SidePrice(dir);

   if(sl > 0.0 && dir * (price - sl) < minDist)
      sl = NormPrice(price - dir * (minDist + PointSize()));
   if(tp > 0.0 && dir * (tp - price) < minDist)
      tp = 0.0;
   if(dir * (price - sl) <= 0.0)
   {
      Print("SL is on the wrong side of the entry - entry skipped");
      return false;
   }

   double lots = CalcLots(dir, price, sl, 1);
   if(lots <= 0.0) return false;

   bool ok = (dir > 0 ? trade.Buy (lots, _Symbol, 0.0, sl, tp, comment)
                      : trade.Sell(lots, _Symbol, 0.0, sl, tp, comment));
   if(!ok)
   {
      Print("Order failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
   }
   Notify(StringFormat("%s %.2f lots @ %.2f SL %.2f TP %.2f | %s",
                       DirName(dir), lots, trade.ResultPrice(), sl, tp, comment));
   return true;
}

void TryPlacePendingLadder()
{
   const int dir = gSetup.dir;
   if(!gSetup.phase1) return;                              // impulse must be complete
   if(gSetup.t1 == gDoneSigM2 && dir == gDoneDirM2) return; // ladder already placed
   if(CountMyPendings(0) > 0) return;

   int cnt = InpPendingCount;
   if(cnt < 1) cnt = 1;
   if(cnt > 3) cnt = 3;

   double fib[3];
   fib[0] = InpPendingFib1;
   fib[1] = InpPendingFib2;
   fib[2] = InpPendingFib3;

   double rng = dir * (gSetup.p1 - gSetup.p0);
   if(rng <= 0.0) return;

   long   stops   = StopsLevelPoints();
   double minDist = stops * PointSize();
   double cur     = SidePrice(dir);
   int    placed  = 0;

   for(int i=0; i<cnt; i++)
   {
      // the ladder may sit deeper than the P2 rule (e.g. 81%) on purpose:
      // only a level at/beyond P0 is structurally impossible
      if(fib[i] <= 0.0 || fib[i] >= 100.0)
      {
         PrintFormat("Pending #%d skipped: fib %.1f%% must be inside 0..100%%", i+1, fib[i]);
         continue;
      }
      double price = NormPrice(gSetup.p1 - dir * (fib[i]/100.0) * rng);
      if(dir * (price - gSetup.p0) <= 0.0) continue;   // past the invalidation level
      if(dir * (cur - price) < minDist)     continue;  // too close / already passed

      double sl = ComputeSL(gSetup, price);
      double tp = ComputeTP(gSetup, price);
      if(dir * (price - sl) <= 0.0) continue;
      if(tp > 0.0 && dir * (tp - price) < minDist) tp = 0.0;

      double lots = CalcLots(dir, price, sl, (InpSplitRisk ? cnt : 1));
      if(lots <= 0.0) continue;

      string cm = StringFormat("EW %sLimit %.1f%%", (dir > 0 ? "Buy" : "Sell"), fib[i]);
      bool ok = (dir > 0
                 ? trade.BuyLimit (lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cm)
                 : trade.SellLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cm));
      if(!ok)
      {
         Print("Limit order failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
         continue;
      }
      placed++;
      Notify(StringFormat("%s LIMIT %.2f lots @ %.2f (fib %.1f%%) SL %.2f TP %.2f",
                          DirName(dir), lots, price, fib[i], sl, tp));
   }

   if(placed > 0)
   {
      gDoneSigM2   = gSetup.t1;
      gDoneDirM2   = dir;
      gPendingSig  = gSetup.t1;
      gPendingP0   = gSetup.p0;
      gPendingDir  = dir;
      gPendingTime = (datetime)iTime(_Symbol, gTF, 0);
   }
}

void ManagePendingLadder()
{
   if(CountMyPendings(0) == 0) return;

   string reason = "";

   // structure invalidated: price closed past the P0 of THIS ladder
   if(gPendingP0 > 0.0 && gPendingDir != 0 &&
      gPendingDir * (iClose(_Symbol, gTF, 1) - gPendingP0) < 0.0)
      reason = "price closed past P0";

   // a new major swing appeared - the ladder belongs to the old one
   if(reason == "" && gSetup.majorOK && gPendingSig != 0 &&
      (gSetup.t1 != gPendingSig || gSetup.dir != gPendingDir))
      reason = "new major swing";

   // age limit
   if(reason == "" && InpPendingExpiryBars > 0 && gPendingTime > 0)
   {
      int barsOld = Bars(_Symbol, gTF, gPendingTime, (datetime)iTime(_Symbol, gTF, 0));
      if(barsOld > InpPendingExpiryBars)
         reason = StringFormat("expired after %d bars", barsOld);
   }

   if(reason == "") return;
   CancelMyPendings(reason);
}

void CancelMyPendings(const string reason)
{
   int killed = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)  continue;
      if(trade.OrderDelete(t)) killed++;
   }
   if(killed > 0)
   {
      gPendingSig  = 0;
      gPendingTime = 0;
      gPendingP0   = 0.0;
      gPendingDir  = 0;
      Notify(StringFormat("Cancelled %d pending order(s): %s", killed, reason));
   }
}

//==================================================================
//  Position sizing
//==================================================================
double CalcLots(const int dir, const double entry, const double sl, const int splitCount)
{
   if(InpFixedLots > 0.0)
      return NormalizeVolume(InpFixedLots);

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskPct   = InpRiskPercent / (splitCount > 0 ? splitCount : 1);
   double riskMoney = balance * (riskPct / 100.0);
   if(riskMoney <= 0.0 || dir * (entry - sl) <= 0.0) return 0.0;

   double lossPerLot = 0.0;
   ENUM_ORDER_TYPE ot = (dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(!OrderCalcProfit(ot, _Symbol, 1.0, entry, sl, lossPerLot))
   {
      Print("OrderCalcProfit failed - cannot size the lot");
      return 0.0;
   }
   lossPerLot = MathAbs(lossPerLot);
   if(lossPerLot <= 0.0) return 0.0;

   double lots = NormalizeVolume(riskMoney / lossPerLot);
   PrintFormat("SIZING %s bal=%.2f risk=%.2f%% dist=%.2f lossPerLot=%.2f -> lots=%.2f",
               DirName(dir), balance, riskPct, MathAbs(entry-sl), lossPerLot, lots);
   return lots;
}

double EffectiveLotStep()
{
   if(InpLotStepOverride > 0.0) return InpLotStepOverride;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return (step > 0.0 ? step : 0.01);
}

double NormalizeVolume(double vol)
{
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = EffectiveLotStep();
   if(step <= 0.0) step = 0.01;

   vol = MathFloor(vol/step + 1e-9) * step;
   if(vol < minV) vol = minV;
   if(vol > maxV) vol = maxV;

   int digits = (int)MathRound(MathLog10(1.0/step));
   if(digits < 0) digits = 0;
   return NormalizeDouble(vol, digits);
}

//==================================================================
//  Step 6 : step trailing stop
//  +Trigger points in profit -> lock +Lock points, then step the SL
//  by +Step points for every further +Step points of profit.
//==================================================================
void ManageStepTrailing()
{
   if(!InpUseStepTrail) return;
   if(InpTrailTriggerPts <= 0 || InpTrailLockPts <= 0) return;

   double point   = PointSize();
   long   stops   = StopsLevelPoints();
   double minDist = stops * point;

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)  continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      int    dir  = (type == POSITION_TYPE_BUY ? 1 : -1);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double cur  = (dir > 0 ? Bid() : Ask());

      double profitPts = dir * (cur - open) / point;
      if(profitPts < InpTrailTriggerPts) continue;

      double lockPts = InpTrailLockPts;
      if(InpTrailStepPts > 0)
      {
         double steps = MathFloor((profitPts - InpTrailTriggerPts) / InpTrailStepPts);
         if(steps > 0) lockPts += steps * InpTrailStepPts;
      }
      if(lockPts >= profitPts) lockPts = profitPts - 1;      // never past the market
      if(lockPts <= 0) continue;

      double newSL = NormPrice(open + dir * lockPts * point);

      if(dir * (cur - newSL) < minDist) continue;            // broker stop distance
      if(sl > 0.0 && dir * (newSL - sl) <= point*0.5) continue; // only ever tighten

      if(trade.PositionModify(ticket, newSL, tp))
         Notify(StringFormat("TRAIL %s #%I64u SL -> %.2f (locked +%.0f pts, profit %.0f pts)",
                             DirName(dir), ticket, newSL, lockPts, profitPts));
   }
}

//==================================================================
//  Step 3 : chart drawing
//==================================================================
void DrawLine(const string name, const datetime t1, const double p1,
              const datetime t2, const double p2, const color clr,
              const int width, const ENUM_LINE_STYLE style)
{
   string obj = gPrefix + name;
   ObjectDelete(0, obj);
   if(!ObjectCreate(0, obj, OBJ_TREND, 0, t1, p1, t2, p2)) return;
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, obj, OBJPROP_STYLE, style);
   ObjectSetInteger(0, obj, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, obj, OBJPROP_BACK, true);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
}

void DrawLabel(const string name, const datetime t, const double p,
               const string text, const color clr, const int size,
               const ENUM_ANCHOR_POINT anchor)
{
   string obj = gPrefix + name;
   ObjectDelete(0, obj);
   if(!ObjectCreate(0, obj, OBJ_TEXT, 0, t, p)) return;
   ObjectSetString (0, obj, OBJPROP_TEXT, text);
   ObjectSetString (0, obj, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
}

void DrawStructure()
{
   ObjectsDeleteAll(0, gPrefix);
   if(!gSetup.majorOK)
   {
      ChartRedraw();
      return;
   }

   const int   dir      = gSetup.dir;
   const color majorClr = (dir > 0 ? InpBuyColor : InpSellColor);
   // P0 / P2 sit at the pullback side, P1 at the impulse side
   const ENUM_ANCHOR_POINT anchorExt = (dir > 0 ? ANCHOR_UPPER : ANCHOR_LOWER);
   const ENUM_ANCHOR_POINT anchorTop = (dir > 0 ? ANCHOR_LOWER : ANCHOR_UPPER);

   // --- major swing : thick lines + P0 / P1 / P2 labels
   DrawLine("MAJ_01", gSetup.t0, gSetup.p0, gSetup.t1, gSetup.p1,
            majorClr, InpMajorWidth, STYLE_SOLID);
   DrawLine("MAJ_12", gSetup.t1, gSetup.p1, gSetup.t2, gSetup.p2,
            majorClr, InpMajorWidth, STYLE_SOLID);

   DrawLabel("LBL_P0", gSetup.t0, gSetup.p0, "P0", majorClr, 11, anchorExt);
   DrawLabel("LBL_P1", gSetup.t1, gSetup.p1, "P1", majorClr, 11, anchorTop);
   DrawLabel("LBL_P2", gSetup.t2, gSetup.p2,
             StringFormat("P2 (%.1f%%) %s", gSetup.retrPct, DirName(dir)),
             majorClr, 11, anchorExt);

   // --- minor impulse : thin dashed lines + 1..5
   if(gSetup.phase1)
   {
      string tag[6] = {"", "1", "2", "3", "4", "5"};
      for(int i=0; i<5; i++)
         DrawLine(StringFormat("MIN_I%d", i),
                  gSetup.wTime[i], gSetup.wPrice[i],
                  gSetup.wTime[i+1], gSetup.wPrice[i+1],
                  InpMinorColor, InpMinorWidth, STYLE_DASH);
      for(int i=1; i<6; i++)
         DrawLabel(StringFormat("MIN_L%d", i), gSetup.wTime[i], gSetup.wPrice[i],
                   tag[i], InpLabelColor, 9,
                   (gSetup.wPrice[i] > gSetup.wPrice[i-1] ? ANCHOR_LOWER : ANCHOR_UPPER));
   }

   // --- minor correction : a-b-c
   if(gSetup.phase2)
   {
      DrawLine("MIN_CA", gSetup.t1, gSetup.p1, gSetup.cTime[0], gSetup.cPrice[0],
               InpMinorColor, InpMinorWidth, STYLE_DOT);
      DrawLine("MIN_CB", gSetup.cTime[0], gSetup.cPrice[0], gSetup.cTime[1], gSetup.cPrice[1],
               InpMinorColor, InpMinorWidth, STYLE_DOT);
      DrawLine("MIN_CC", gSetup.cTime[1], gSetup.cPrice[1], gSetup.cTime[2], gSetup.cPrice[2],
               InpMinorColor, InpMinorWidth, STYLE_DOT);

      DrawLabel("MIN_LA", gSetup.cTime[0], gSetup.cPrice[0], "a (6)", InpLabelColor, 9, anchorExt);
      DrawLabel("MIN_LB", gSetup.cTime[1], gSetup.cPrice[1], "b (7)", InpLabelColor, 9, anchorTop);
      DrawLabel("MIN_LC", gSetup.cTime[2], gSetup.cPrice[2], "c",     InpLabelColor, 9, anchorExt);

      // Step 5 special label
      if(gSetup.cEqualsP2)
         DrawLabel("MIN_CP2", gSetup.cTime[2],
                   gSetup.cPrice[2] - dir * InpSLBufferPoints * PointSize(),
                   StringFormat("c = P2 (%s Zone)", (dir > 0 ? "Buy" : "Sell")),
                   clrLime, 11, anchorExt);
   }

   // --- entry zone reference levels
   datetime tRight = (datetime)iTime(_Symbol, gTF, 0) + PeriodSeconds(gTF)*10;
   if(gSetup.phase1)
   {
      double rng = dir * (gSetup.p1 - gSetup.p0);
      double zNear = gSetup.p1 - dir * (InpP2MinRetrPct/100.0) * rng;
      double zFar  = gSetup.p1 - dir * (InpP2MaxRetrPct/100.0) * rng;
      DrawLine("ZONE_HI", gSetup.t1, zNear, tRight, zNear, clrSeaGreen, 1, STYLE_DOT);
      DrawLine("ZONE_LO", gSetup.t1, zFar,  tRight, zFar,  clrSeaGreen, 1, STYLE_DOT);
      DrawLabel("ZONE_TX", tRight, zFar,
                StringFormat("%s zone %.1f%% - %.1f%%", DirName(dir),
                             InpP2MinRetrPct, InpP2MaxRetrPct),
                clrSeaGreen, 9, ANCHOR_LEFT_UPPER);
   }
   ChartRedraw();
}

void ShowPanel()
{
   string adx;
   if(!InpUseAdxFilter)
      adx = "ADX filter: OFF (auto PASS)";
   else
      adx = StringFormat("ADX %s %.1f/%.0f | %s %.1f/%.0f | %s %.1f/%.0f -> %s",
                         EnumToString(InpAdxTF1), gAdxVal[0], InpAdxThreshold1,
                         EnumToString(InpAdxTF2), gAdxVal[1], InpAdxThreshold2,
                         EnumToString(InpAdxTF3), gAdxVal[2], InpAdxThreshold3,
                         (gAdxPass ? "PASS" : "BLOCK"));

   string txt = "=== Elliott Wave Dual Swing ===\n";
   txt += adx + "\n";
   txt += StringFormat("Mode: %s | TF: %s | Allowed: %s\n",
                       (InpEntryMode == EW_ENTRY_MARKET ? "1 Market (confirmation)"
                                                        : "2 Pending Limit ladder"),
                       EnumToString(gTF), DirectionName());
   txt += StringFormat("Active side: %s\n", DirName(gSetup.dir));

   if(gSetup.majorOK)
      txt += StringFormat("P0 %.2f  P1 %.2f  P2 %.2f  (retr %.1f%%)\n",
                          gSetup.p0, gSetup.p1, gSetup.p2, gSetup.retrPct);
   else
      txt += "Major swing: not formed\n";

   txt += StringFormat("Phase 1: %s | Phase 2: %s%s | Zone: %s\n",
                       (gSetup.phase1 ? "OK" : "-"),
                       (gSetup.phase2 ? "OK" : "-"),
                       (gSetup.cEqualsP2 ? "  [c = P2]" : ""),
                       (gSetup.zoneOK ? "inside" : "outside"));
   txt += StringFormat("BUY  : %s\n", gNoteBuy);
   txt += StringFormat("SELL : %s\n", gNoteSell);
   txt += StringFormat("Positions %d (B%d/S%d) | Pendings %d\n",
                       CountMyPositions(0), CountMyPositions(1), CountMyPositions(-1),
                       CountMyPendings(0));
   Comment(txt);
}
//+------------------------------------------------------------------+
