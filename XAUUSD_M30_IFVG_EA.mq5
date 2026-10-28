//+------------------------------------------------------------------+
//|                                          XAUUSD_M30_IFVG_EA.mq5  |
//|        IFVG (Inverse Fair Value Gap) system for XAUUSD (Gold)    |
//|                                                                  |
//|  Strategy summary (from the KRV IFVG clip transcript)            |
//|  - FVG        : 3-bar gap. Bar 2 must be a Strong Move so that   |
//|                 High of bar 1 and Low of bar 3 are far apart     |
//|                 (gap size = the key "distance" parameter)        |
//|  - IFVG       : wait for price to CLOSE THROUGH the FVG          |
//|                 (destroy it) - the zone flips role:              |
//|                 red/bearish FVG broken up  -> support  -> BUY    |
//|                 green/bullish FVG broken dn -> resistance -> SELL|
//|  - Entry      : price pulls back into the IFVG, does NOT close   |
//|                 through it, and bounces -> enter next bar open   |
//|  - Market/TF  : XAUUSD, signals on M30 (closed bar only)         |
//|  - Trend      : EMA 60 on H1 - above = uptrend (buy only),       |
//|                 below = downtrend (sell only)                    |
//|  - HTF helper : IFVG on H1 - latest live H1 IFVG must agree      |
//|  - Stop loss  : signal (retest) bar Low - $0.5 / High + $0.5     |
//|                 = 1R (lot sizing + partial level). Pushed out to |
//|                 the broker stop level if too close               |
//|  - Break-even : profit >= ATR(16) x 1.5 -> SL to entry + 0.1R    |
//|                 (once per trade, checked every tick)             |
//|  - Partial    : at 1R close 40% of the INITIAL lot, once, SL not |
//|                 moved ("แบ่งขาย" - clip win rate 64%)            |
//|                 (rules ported from our H4 system, ATR on M30)    |
//|  - Sizing     : fixed 1% risk per trade (clip: +397% 2020-now,   |
//|                 PF 1.47, ~1,100-1,200 trades, DD ~13%)           |
//|  - Max orders : 2 at the same time (clip: "สูงสุดสองออเดอร์")    |
//|  - Guards     : risk cap, total open-risk cap, daily DD, max DD  |
//|                 (prop style), spread, news (CSV), Friday close   |
//|                                                                  |
//|  Inputs are laid out in the same order as the KRV tester screen |
//|  (names were hidden): [KRV: x] = value seen, '?' = our guess of  |
//|  what that row means. SL / TP / partial rows were not shown.     |
//|  !! -> optimise, then Walk-Forward + forward test (KRV).         |
//+------------------------------------------------------------------+
#property copyright "Metasit - IFVG EA"
#property version   "1.33"
#property strict

#include <Trade\Trade.mqh>

//==================================================================
//  Enums
//==================================================================
enum ENUM_SL_MODE
{
   SL_ZONE_EDGE   = 0,   // Beyond the far edge of the IFVG zone
   SL_RETEST_BAR  = 1,   // Beyond the retest (signal) bar high/low
   SL_WIDEST      = 2    // Whichever of the two is further away
};
enum ENUM_BREAK_MODE
{
   BREAK_BOUNDARY = 0,   // Broken Boundary
   BREAK_LINE     = 1,   // Broken IFVG Line
   BREAK_WICK     = 2    // Wick Through
};
enum ENUM_FILTER_PROFILE
{
   PROFILE_AGGRESSIVE   = 0,  // Aggressive
   PROFILE_BALANCED     = 1,  // Balanced
   PROFILE_CONSERVATIVE = 2   // Conservative
};
enum ENUM_ENTRY_LEVEL
{
   ENTRY_ZONE_EDGE  = 0,  // Zone Edge
   ENTRY_IFVG_LINE  = 1,  // IFVG Line
   ENTRY_LINE_LIMIT = 2   // IFVG Line Limit Order
};
enum ENUM_CONFIRM_MODE
{
   CONF_CLOSE_OUTSIDE = 0,  // Touch zone, close back outside it (bounce)
   CONF_CLOSE_INSIDE  = 1   // Touch zone, close anywhere not through it
};

//==================================================================
//  Inputs
//==================================================================
input group "=== General ==="
input ENUM_TIMEFRAMES InpSignalTF    = PERIOD_M30;  // Signal timeframe                    [KRV: 30 Minutes]
input long     InpMagic              = 20250801;    // Magic number                        [KRV: 20250801]

input group "=== Zone lifetime / break ==="
input int      InpZoneMaxAgeBars     = 120;         // IFVG kept alive N bars              [KRV: 120 ?]
input int      InpFVGMaxAgeBars      = 60;          // FVG must be broken within N bars    [KRV: 60 ?]
input double   InpMaxGapATR          = 0.0;         // Max gap x ATR (0 = off)             [KRV: 0 ?]
input int      InpMaxActiveZones     = 5;           // Max IFVGs waiting retest (0 = all)  [KRV: 5 ?]
input int      InpMaxSpreadPoints    = 50;          // Skip entry if spread > this (0=off) [KRV: 50 ?]
input ENUM_BREAK_MODE InpBreakMode   = BREAK_BOUNDARY; // FVG counts as broken when...     [KRV: Broken Boundary]
input bool     InpInvalidateOnClose  = true;        // Kill IFVG when a bar closes through [KRV: true ?]

input group "=== Strong Move / gap filter ==="
input ENUM_FILTER_PROFILE InpProfile = PROFILE_BALANCED; // Threshold profile (x0.75/x1/x1.25) [KRV: Balanced]
input double   InpMinGapATR          = 0.25;        // Min gap (High bar1 <-> Low bar3) x ATR [KRV: 0.25 ?]
input double   InpStrongBodyATR      = 0.5;         // Bar 2 (Strong Move) body >= x ATR   [KRV: 0.5 ?]
input double   InpStrongBodyRatio    = 0.6;         // Bar 2 body / range >= this          [KRV: 0.6 ?]
input double   InpTouchTolATR        = 0.05;        // Count as touch within x ATR         [KRV: 0.05 ?]

input group "=== Entry ==="
input ENUM_ENTRY_LEVEL InpEntryLevel = ENTRY_IFVG_LINE; // Retest level (IFVG Line = mid) [KRV: IFVG Line]
input int      InpATRPeriod          = 14;          // ATR period (scales all sizes)       [KRV: 14 ?]
input int      InpMaxRetestBars      = 5;           // Retest must come within N bars      [KRV: 5 ?]
input ENUM_CONFIRM_MODE InpConfirm   = CONF_CLOSE_INSIDE; // Retest confirmation
input bool     InpNeedDirCandle      = false;       // Retest bar must close in trade direction
input double   InpInvBodyATR         = 0.0;         // Breaking bar body >= x ATR (0 = off)
input int      InpWarmupBars         = 300;         // History bars to pre-build zones

input group "=== Trend (EMA) + higher-TF IFVG ==="
input bool     InpUseTrend           = true;        // Trade only with the EMA trend       [KRV: true]
input ENUM_TIMEFRAMES InpTrendTF     = PERIOD_H1;   // Trend + helper timeframe            [KRV: 1 Hour]
input int      InpEMAPeriod          = 60;          // EMA period                          [KRV: 60]
input int      InpHTFZoneMaxAge      = 40;          // HTF IFVG kept alive N bars          [KRV: 40 ?]
input bool     InpUseHTFIFVG         = true;        // Latest live HTF IFVG must agree

input group "=== Stop loss / Take profit ==="
input ENUM_SL_MODE InpSLMode         = SL_RETEST_BAR; // Stop loss mode (signal bar Low/High)
input double   InpSLBufferPrice      = 0.5;         // SL buffer in price ($) beyond bar Low/High
input double   InpSLBufferATR        = 0.0;         // + extra SL buffer x ATR (0 = off)
input double   InpMinSL_ATR          = 0.5;         // Min SL distance x ATR (widen, 0 = off)
input double   InpMaxSL_ATR          = 0.0;         // Skip trade if SL > x ATR (0 = off)
input double   InpTP_R               = 3.0;         // Final TP in R (0 = no TP)

input group "=== Break-even / Partial close / Trailing ==="
input double   InpBETriggerATR       = 1.5;         // BE when profit >= x ATR (0 = off)
input int      InpBEATRPeriod        = 16;          // ATR period for BE trigger (signal TF)
input double   InpBELockR            = 0.1;         // BE stop = entry + x R (locks a little)
input double   InpPartialR           = 1.0;         // Partial close at x R (0 = off)
input double   InpPartialPct         = 40.0;        // % of the INITIAL lot to close (once)
input double   InpTrailATR           = 0.0;         // Trail after BE by x ATR (0 = off)

input group "=== Risk management ==="
input double   InpRiskPercent        = 1.0;         // Risk per trade (% balance)
input double   InpMaxRiskCapPct      = 1.5;         // Skip if min lot risks > this % (0 = off)
input int      InpMaxPositions       = 2;           // Max open positions (clip: 2)
input double   InpMaxOpenRiskPct     = 0.0;         // Max total risk of open trades % (0 = off, prop: 1.0)
input double   InpMinMarginLevel     = 300.0;       // Cut lot so margin level stays >= % (0 = off)
input double   InpMaxLots            = 0.0;         // Hard max lot per trade (0 = off)

input group "=== Account guards (prop style) ==="
input double   InpDailyDDPct         = 0.0;         // Daily loss limit % (0 = off)
input double   InpMaxDDPct           = 0.0;         // Max loss % from start balance (0 = off)
input double   InpProfitTargetPct    = 0.0;         // Stop at +% from start (0 = off)
input double   InpStartBalance       = 0.0;         // Start balance (0 = balance at start)
input bool     InpCloseOnGuard       = true;        // Close positions when a guard trips

input group "=== Filters ==="
input int      InpStartHour          = 0;           // Trade from hour (server)
input int      InpEndHour            = 24;          // ...until hour (server, exclusive)
input bool     InpFridayClose        = false;       // Close all before weekend
input int      InpFridayCloseHour    = 21;          // Friday close hour (server)

input group "=== News filter (CSV works in Strategy Tester) ==="
input bool     InpUseFFNews          = false;       // Use news CSV file (works in tester + live)
input string   InpFFNewsFile         = "ff_news.csv"; // CSV in COMMON\Files: Date,Time,Currency,Impact
input string   InpFFBlockImpact      = "High";      // Impacts to use (High  or  High,Medium)
input int      InpFFTimeOffsetHours  = 0;           // Shift CSV times to server time (+/- hours)
input bool     InpEnableNewsFilter   = false;       // Also use MT5 calendar (live only)
input string   InpNewsCurrencies     = "USD";       // Currencies to watch (comma sep.)
input bool     InpNewsBlockEntry     = true;        // No new entry near news (+ cancel pending)
input int      InpNewsMinutesBefore  = 60;          //     ...minutes before news
input int      InpNewsMinutesAfter   = 60;          //     ...minutes after news
input bool     InpNewsClosePositions = false;       // Close open trades before news
input int      InpNewsCloseMinutes   = 30;          //     ...this many minutes before news

input group "=== Misc ==="
input string   InpComment            = "IFVG";      // Order comment
input bool     InpDrawZones          = true;        // Draw IFVG zones on chart
input bool     InpNotify             = true;        // Push notifications (live only)

//==================================================================
//  Zone engine (one instance per timeframe)
//==================================================================
#define ZS_FVG      0   // plain FVG, waiting to be broken
#define ZS_ACTIVE   1   // IFVG, waiting for retest (tradeable)
#define ZS_DEAD     2   // gone (expired / closed through)
#define ZS_USED     3   // IFVG still holding but no longer tradeable

struct Zone
{
   double   top;
   double   bottom;
   int      fvgDir;     // +1 bullish FVG, -1 bearish FVG (original direction)
   int      dir;        // after inversion: +1 support (BUY), -1 resistance (SELL)
   datetime t0;         // time of the oldest bar of the 3-bar pattern
   datetime invTime;    // time of the bar that broke the FVG
   int      state;
   int      age;        // bars since FVG (ZS_FVG) or since inversion
   int      retestAge;  // bars since inversion while ZS_ACTIVE
};

double ProfileMult()
{
   if(InpProfile == PROFILE_AGGRESSIVE)   return 0.75;
   if(InpProfile == PROFILE_CONSERVATIVE) return 1.25;
   return 1.0;
}

class CIFVGEngine
{
public:
   ENUM_TIMEFRAMES   tf;
   int               hATR;
   Zone              z[];
   datetime          lastOpen;
   bool              draw;
   string            tag;
   int               zoneMaxAge;
   Zone              sigZone;    // zone that gave the retest signal on the last bar
   Zone              newInv[];   // zones inverted on the last bar (limit-order mode)

   bool Init(const ENUM_TIMEFRAMES t, const bool d, const string tg, const int maxAge)
   {
      tf = t; draw = d; tag = tg; lastOpen = 0; zoneMaxAge = maxAge;
      ArrayResize(newInv, 0);
      ArrayResize(z, 0);
      hATR = iATR(_Symbol, tf, InpATRPeriod);
      return (hATR != INVALID_HANDLE);
   }

   void Deinit()
   {
      if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
      if(draw) ObjectsDeleteAll(0, tag);
   }

   double ATRAt(const int s)
   {
      double b[1];
      if(CopyBuffer(hATR, 0, s, 1, b) != 1) return 0.0;
      return b[0];
   }

   // Direction of the most recently inverted IFVG that is still holding (0 = none)
   int Bias()
   {
      datetime best = 0; int dir = 0;
      for(int i = 0; i < ArraySize(z); i++)
         if((z[i].state == ZS_ACTIVE || z[i].state == ZS_USED) && z[i].invTime > best)
         { best = z[i].invTime; dir = z[i].dir; }
      return dir;
   }

   // Pre-build zones from history without trading. Returns false if data not ready.
   bool Warmup(const int bars)
   {
      int avail = iBars(_Symbol, tf);
      if(avail < 50 || ATRAt(1) <= 0.0) return false;
      int from = MathMin(bars, avail - InpATRPeriod - 5);
      ArrayResize(z, 0);                     // may be retried if the other TF wasn't ready
      if(draw) ObjectsDeleteAll(0, tag);
      for(int s = from; s >= 1; s--) ProcessBar(s);
      lastOpen = iTime(_Symbol, tf, 0);
      return true;
   }

   // Call every tick. On a new bar processes the just-closed bar.
   // Returns retest signal direction (+1/-1/0); the zone is in sigZone.
   int Update()
   {
      ArrayResize(newInv, 0);
      datetime t = iTime(_Symbol, tf, 0);
      if(t == 0 || t == lastOpen) return 0;
      lastOpen = t;
      return ProcessBar(1);
   }

   // Process closed bar at shift s (order matters: retest -> inversion -> new FVG,
   // so a bar can never break and retest the same zone)
   int ProcessBar(const int s)
   {
      int sigIdx = -1;
      int sigDir = 0;
      ArrayResize(newInv, 0);
      double o = iOpen(_Symbol, tf, s), h = iHigh(_Symbol, tf, s);
      double l = iLow(_Symbol, tf, s),  c = iClose(_Symbol, tf, s);
      datetime bt = iTime(_Symbol, tf, s);
      double atr = ATRAt(s);
      if(atr <= 0.0) return 0;
      double tol = InpTouchTolATR * atr;

      for(int i = 0; i < ArraySize(z); i++)
      {
         if(z[i].state == ZS_DEAD) continue;

         //--- live IFVGs: retest / invalidation / ageing
         if(z[i].state == ZS_ACTIVE || z[i].state == ZS_USED)
         {
            z[i].age++;
            bool broken = InpInvalidateOnClose && (z[i].dir > 0 ? c < z[i].bottom : c > z[i].top);
            if(broken || z[i].age > zoneMaxAge)
            {
               z[i].state = ZS_DEAD;
               CloseBox(i, bt);
               continue;
            }
            if(z[i].state != ZS_ACTIVE) continue;

            z[i].retestAge++;
            double mid   = (z[i].top + z[i].bottom) / 2.0;
            double lvl   = (InpEntryLevel == ENTRY_ZONE_EDGE ? (z[i].dir > 0 ? z[i].top : z[i].bottom) : mid);
            bool touched = (z[i].dir > 0 ? l <= lvl + tol : h >= lvl - tol);
            bool confirm = (InpConfirm == CONF_CLOSE_OUTSIDE
                            ? (z[i].dir > 0 ? c > z[i].top : c < z[i].bottom)
                            : true);   // not broken already checked above
            bool dirBar  = !InpNeedDirCandle || (z[i].dir > 0 ? c > o : c < o);

            if(touched && confirm && dirBar)
            {
               z[i].state = ZS_USED;
               // several zones on the same bar -> take the most recent inversion
               if(sigIdx < 0 || z[i].invTime > z[sigIdx].invTime)
               { sigIdx = i; sigDir = z[i].dir; }
            }
            else if(z[i].retestAge > InpMaxRetestBars)
               z[i].state = ZS_USED;   // too late to trade, still counts for bias
            continue;
         }

         //--- plain FVG: wait for a close through it (inversion)
         z[i].age++;
         if(z[i].age > InpFVGMaxAgeBars) { z[i].state = ZS_DEAD; continue; }
         double fmid = (z[i].top + z[i].bottom) / 2.0;
         bool inv = false;
         if(InpBreakMode == BREAK_BOUNDARY)  inv = (z[i].fvgDir < 0 ? c > z[i].top : c < z[i].bottom);
         else if(InpBreakMode == BREAK_LINE) inv = (z[i].fvgDir < 0 ? c > fmid : c < fmid);
         else                                inv = (z[i].fvgDir < 0 ? h > z[i].top : l < z[i].bottom);
         if(inv && InpInvBodyATR > 0.0 && MathAbs(c - o) < InpInvBodyATR * atr) inv = false;
         if(inv)
         {
            z[i].dir       = -z[i].fvgDir;
            z[i].state     = ZS_ACTIVE;
            z[i].invTime   = bt;
            z[i].age       = 0;
            z[i].retestAge = 0;
            DrawBox(i, bt);
            int n = ArraySize(newInv);
            ArrayResize(newInv, n + 1);
            newInv[n] = z[i];
         }
      }

      if(sigIdx >= 0) sigZone = z[sigIdx];   // copy before Compact() shifts indices
      LimitActive();
      DetectFVG(s);
      Compact();
      return sigDir;
   }

   // Keep only the newest InpMaxActiveZones IFVGs tradeable
   void LimitActive()
   {
      if(InpMaxActiveZones <= 0) return;
      int cnt = 0;
      for(int i = 0; i < ArraySize(z); i++) if(z[i].state == ZS_ACTIVE) cnt++;
      while(cnt > InpMaxActiveZones)
      {
         int old = -1;
         for(int i = 0; i < ArraySize(z); i++)
            if(z[i].state == ZS_ACTIVE && (old < 0 || z[i].invTime < z[old].invTime)) old = i;
         if(old < 0) break;
         z[old].state = ZS_USED;
         cnt--;
      }
   }

   // New FVG: bars s (newest = "bar 3"), s+1 (Strong Move), s+2 (oldest = "bar 1")
   void DetectFVG(const int s)
   {
      double atr = ATRAt(s + 2);
      if(atr <= 0.0) return;
      double h1 = iHigh(_Symbol, tf, s + 2), l1 = iLow(_Symbol, tf, s + 2);
      double h3 = iHigh(_Symbol, tf, s),     l3 = iLow(_Symbol, tf, s);
      double o2 = iOpen(_Symbol, tf, s + 1), c2 = iClose(_Symbol, tf, s + 1);
      double r2 = iHigh(_Symbol, tf, s + 1) - iLow(_Symbol, tf, s + 1);
      double body = MathAbs(c2 - o2);
      if(r2 <= 0.0) return;
      double pm = ProfileMult();
      if(body < InpStrongBodyATR * pm * atr || body / r2 < MathMin(InpStrongBodyRatio * pm, 0.95)) return;

      int dir = 0; double top = 0, bot = 0;
      if(c2 > o2 && l3 > h1)      { dir = +1; bot = h1; top = l3; }   // bullish FVG
      else if(c2 < o2 && h3 < l1) { dir = -1; bot = h3; top = l1; }   // bearish FVG
      if(dir == 0) return;

      double gap = top - bot;
      if(gap < InpMinGapATR * pm * atr) return;
      if(InpMaxGapATR > 0.0 && gap > InpMaxGapATR * atr) return;

      int n = ArraySize(z);
      ArrayResize(z, n + 1);
      z[n].top = top; z[n].bottom = bot; z[n].fvgDir = dir; z[n].dir = 0;
      z[n].t0 = iTime(_Symbol, tf, s + 2); z[n].invTime = 0;
      z[n].state = ZS_FVG; z[n].age = 0; z[n].retestAge = 0;
   }

   void Compact()
   {
      int n = ArraySize(z), k = 0;
      for(int i = 0; i < n; i++)
         if(z[i].state != ZS_DEAD) { if(k != i) z[k] = z[i]; k++; }
      if(k != n) ArrayResize(z, k);
   }

   string BoxName(const int i) { return tag + IntegerToString((long)z[i].t0); }

   void DrawBox(const int i, const datetime t)
   {
      if(!draw) return;
      string nm = BoxName(i);
      datetime t2 = t + PeriodSeconds(tf) * InpMaxRetestBars;
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, z[i].t0, z[i].top, t2, z[i].bottom);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, z[i].dir > 0 ? clrDodgerBlue : clrTomato);
      ObjectSetInteger(0, nm, OBJPROP_FILL, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, nm, OBJPROP_TOOLTIP, z[i].dir > 0 ? "IFVG support" : "IFVG resistance");
   }

   void CloseBox(const int i, const datetime t)
   {
      if(!draw) return;
      string nm = BoxName(i);
      if(ObjectFind(0, nm) >= 0) ObjectSetInteger(0, nm, OBJPROP_TIME, 1, t);
   }
};

//==================================================================
//  Globals
//==================================================================
CTrade       trade;
CIFVGEngine  gSig;
CIFVGEngine  gHTF;
int          hEMA        = INVALID_HANDLE;
int          hBEATR      = INVALID_HANDLE;
bool         gWarm       = false;
int          gDayKey     = -1;
double       gDayStartBal= 0.0;
double       gStartBal   = 0.0;
bool         gDailyHit   = false;
bool         gStopped    = false;
datetime     gLastGVClean= 0;

// news events loaded from CSV (server time, sorted ascending)
datetime     gFFTime[];
int          gFFCount    = 0;
datetime     gLastNewsClose = 0;   // event time we already closed positions for

#define TF_BE       1   // per-trade flag: break-even done
#define TF_PARTIAL  2   // per-trade flag: partial close done
#define TF_NOSL_MSG 4   // per-trade flag: "no SL" warning already printed

//==================================================================
//  Init / Deinit
//==================================================================
int OnInit()
{
   // netting merges / offsets positions: an opposite signal just shrinks the open trade
   // (that deal shows no SL), max-2-orders and per-trade partial close break -> hedging only
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Alert("IFVG EA needs a HEDGING account - this account is NETTING. "
            "Open a demo with 'Use hedge in trading' ticked.");
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(!gSig.Init(InpSignalTF, InpDrawZones, "IFVG_SIG_", InpZoneMaxAgeBars)) return INIT_FAILED;
   if(InpUseHTFIFVG && !gHTF.Init(InpTrendTF, false, "IFVG_HTF_", InpHTFZoneMaxAge)) return INIT_FAILED;
   if(InpUseTrend)
   {
      hEMA = iMA(_Symbol, InpTrendTF, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(hEMA == INVALID_HANDLE) return INIT_FAILED;
   }
   if(InpBETriggerATR > 0.0)
   {
      hBEATR = iATR(_Symbol, InpSignalTF, InpBEATRPeriod);
      if(hBEATR == INVALID_HANDLE) return INIT_FAILED;
   }
   LoadFFNews();
   // prop accounts can carry a stop-out in money (= max-loss rule) that the tester copies
   bool soMoney = (AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE) == ACCOUNT_STOPOUT_MODE_MONEY);
   PrintFormat("Account stop-out: call %.2f / stop-out %.2f %s",
               AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL), AccountInfoDouble(ACCOUNT_MARGIN_SO_SO),
               soMoney ? "(MONEY - equity level)" : "(% margin level)");
   gStartBal = (InpStartBalance > 0.0 ? InpStartBalance : AccountInfoDouble(ACCOUNT_BALANCE));
   gWarm = false;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   gSig.Deinit();
   if(InpUseHTFIFVG) gHTF.Deinit();
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hBEATR != INVALID_HANDLE) IndicatorRelease(hBEATR);
}

//==================================================================
//  Main loop
//==================================================================
void OnTick()
{
   if(!gWarm)
   {
      if(!gSig.Warmup(InpWarmupBars)) return;
      if(InpUseHTFIFVG && !gHTF.Warmup(InpWarmupBars)) return;
      gWarm = true;
      return;
   }

   bool canTrade = GuardsOK();
   ManagePositions();
   ManageNewsClose();
   bool newsBlock = ((InpUseFFNews || InpEnableNewsFilter) && InpNewsBlockEntry && IsNewsBlocking());
   if(newsBlock && CountOrders() > 0) DeleteOrders();   // don't let a limit fill into news

   // engines must see every bar even when we are not allowed to trade
   if(InpUseHTFIFVG) gHTF.Update();
   int dir = gSig.Update();
   if(!canTrade || newsBlock) return;

   // limit mode: pending order at the IFVG line as soon as the FVG is broken
   if(InpEntryLevel == ENTRY_LINE_LIMIT)
   {
      for(int k = 0; k < ArraySize(gSig.newInv); k++)
         if(EntryAllowed(gSig.newInv[k].dir)) OpenTrade(gSig.newInv[k].dir, gSig.newInv[k], true);
      return;
   }
   if(dir != 0 && EntryAllowed(dir)) OpenTrade(dir, gSig.sigZone, false);
}

bool EntryAllowed(const int dir)
{
   if(InpMaxPositions > 0 && CountPositions() + CountOrders() >= InpMaxPositions) return false;
   if(!InSession()) return false;
   if(InpMaxSpreadPoints > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPoints)
   { Print("Skip: spread too wide"); return false; }
   if(InpUseTrend && TrendDir() != dir) return false;
   if(InpUseHTFIFVG && gHTF.Bias() != dir) return false;
   return true;
}

//==================================================================
//  Filters
//==================================================================
int TrendDir()
{
   double ema[1];
   if(CopyBuffer(hEMA, 0, 1, 1, ema) != 1) return 0;
   double c = iClose(_Symbol, InpTrendTF, 1);
   if(c > ema[0]) return +1;
   if(c < ema[0]) return -1;
   return 0;
}

bool InSession()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   if(InpFridayClose && t.day_of_week == 5 && t.hour >= InpFridayCloseHour) return false;
   if(InpStartHour <= InpEndHour) return (t.hour >= InpStartHour && t.hour < InpEndHour);
   return (t.hour >= InpStartHour || t.hour < InpEndHour);   // overnight window
}

//==================================================================
//  Trade entry
//==================================================================
void OpenTrade(const int dir, const Zone &zn, const bool limit)
{
   double atr   = gSig.ATRAt(1);
   double buf   = InpSLBufferPrice + InpSLBufferATR * atr;
   double mkt   = (dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                           : SymbolInfoDouble(_Symbol, SYMBOL_BID));
   double entry = (limit ? NormalizeDouble((zn.top + zn.bottom) / 2.0, _Digits) : mkt);
   if(limit && (dir > 0 ? mkt <= entry : mkt >= entry))
   { Print("Skip: price already at/through the IFVG line"); return; }
   double barL  = iLow(_Symbol, InpSignalTF, 1), barH = iHigh(_Symbol, InpSignalTF, 1);

   double slZone = (dir > 0 ? zn.bottom - buf : zn.top + buf);
   double slBar  = (limit ? slZone : (dir > 0 ? barL - buf : barH + buf));
   double sl = slZone;
   if(InpSLMode == SL_RETEST_BAR) sl = slBar;
   if(InpSLMode == SL_WIDEST)     sl = (dir > 0 ? MathMin(slZone, slBar) : MathMax(slZone, slBar));

   double dist = (dir > 0 ? entry - sl : sl - entry);
   if(dist <= 0.0) { Print("Skip: price already beyond SL"); return; }
   if(dist < InpMinSL_ATR * atr)
   {
      dist = InpMinSL_ATR * atr;
      sl = (dir > 0 ? entry - dist : entry + dist);
   }
   if(InpMaxSL_ATR > 0.0 && dist > InpMaxSL_ATR * atr)
   { PrintFormat("Skip: SL %.2f > %.1f ATR", dist, InpMaxSL_ATR); return; }

   // SL closer than the broker stop level -> push it out to the minimum allowed
   double stopLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(limit && MathAbs(mkt - entry) < stopLvl) { Print("Skip: limit too close to price"); return; }
   double ref = (limit ? entry : (dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                          : SymbolInfoDouble(_Symbol, SYMBOL_ASK)));
   if(stopLvl > 0.0 && (dir > 0 ? ref - sl : sl - ref) < stopLvl)
   {
      sl   = (dir > 0 ? ref - stopLvl - _Point : ref + stopLvl + _Point);
      dist = (dir > 0 ? entry - sl : sl - entry);
   }

   double tp = 0.0;
   if(InpTP_R > 0.0) tp = (dir > 0 ? entry + InpTP_R * dist : entry - InpTP_R * dist);
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   ENUM_ORDER_TYPE type = (dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double lots = CalcLotSize(type, entry, sl);
   if(lots <= 0.0) return;
   lots = FitMargin(type, lots, entry);   // tight SL -> big lot -> stop out (test died 2020-12-30)
   if(lots <= 0.0) return;

   if(InpMaxOpenRiskPct > 0.0)
   {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double newRisk = RiskMoney(type, lots, entry, sl);
      double total = (bal > 0.0 ? (OpenRiskMoney() + newRisk) / bal * 100.0 : 0.0);
      if(total > InpMaxOpenRiskPct + 1e-6)
      {
         PrintFormat("Skip: total open risk would be %.2f%% (> %.2f%%)", total, InpMaxOpenRiskPct);
         return;
      }
   }

   bool ok;
   if(limit)
      ok = (dir > 0 ? trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment)
                    : trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment));
   else
   {
      bool slInOrder = ((SymbolInfoInteger(_Symbol, SYMBOL_ORDER_MODE) & SYMBOL_ORDER_SL) != 0);
      double osl = (slInOrder ? sl : 0.0), otp = (slInOrder ? tp : 0.0);
      ok = (dir > 0 ? trade.Buy(lots, _Symbol, 0.0, osl, otp, InpComment)
                    : trade.Sell(lots, _Symbol, 0.0, osl, otp, InpComment));
      // SL/TP not allowed in the order -> attached by EnsureStop() from the saved 1R
   }
   if(ok)
   {
      // position identifier = order ticket (market or pending) -> remember 1R + start lot
      SaveTradeState((long)trade.ResultOrder(), dist, lots, 0);
      Notify(StringFormat("%s%s %.2f @ %.2f SL %.2f TP %.2f | zone %.2f-%.2f",
                          dir > 0 ? "BUY" : "SELL", limit ? " LIMIT" : "",
                          lots, entry, sl, tp, zn.bottom, zn.top));
      DrawArrow(dir, entry);
   }
   else
      PrintFormat("Order failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
}

//==================================================================
//  Position management: partial close + BE + trailing + Friday close
//==================================================================
void ManagePositions()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   bool friday = (InpFridayClose && t.day_of_week == 5 && t.hour >= InpFridayCloseHour);

   // pending IFVG-line orders live only for InpMaxRetestBars bars
   int expSec = PeriodSeconds(InpSignalTF) * MathMax(InpMaxRetestBars, 1);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ot = OrderGetTicket(i);
      if(ot == 0 || !IsMyOrder()) continue;
      if(friday || TimeCurrent() - (datetime)OrderGetInteger(ORDER_TIME_SETUP) >= expSec)
         trade.OrderDelete(ot);
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !IsMine()) continue;
      if(friday) { trade.PositionClose(tk); continue; }

      bool   buy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      long   id   = PositionGetInteger(POSITION_IDENTIFIER);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      double px   = (buy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
      double profit = (buy ? px - open : open - px);

      double R, v0; int fl;
      if(!LoadTradeState(id, R, v0, fl))
      {
         // state lost (e.g. opened by an older version) -> rebuild from the current SL
         bool slLosing = (sl > 0.0 && (buy ? sl < open : sl > open));
         R = (slLosing ? MathAbs(open - sl) : 0.0);
         v0 = vol;
         fl = (slLosing ? 0 : TF_BE | TF_PARTIAL);
         SaveTradeState(id, R, v0, fl);
      }
      int flOld = fl;

      //--- never run without a stop: attach the planned SL/TP if the position has none
      if(sl <= 0.0)
      {
         if(R <= 0.0 || (fl & TF_BE) != 0)
         {
            if((fl & TF_NOSL_MSG) == 0)
            {
               Notify(StringFormat("WARNING: position %I64d has no SL and no saved 1R - set one manually", id));
               SaveTradeState(id, R, v0, fl | TF_NOSL_MSG);
            }
            continue;
         }
         double nsl = NormalizeDouble(buy ? open - R : open + R, _Digits);
         double ntp = tp;
         if(ntp <= 0.0 && InpTP_R > 0.0)
            ntp = NormalizeDouble(buy ? open + InpTP_R * R : open - InpTP_R * R, _Digits);
         if(!StopOK(buy, nsl, px))
         {
            Notify(StringFormat("Price already beyond planned SL %.2f - closing position %I64d", nsl, id));
            trade.PositionClose(tk);
            continue;
         }
         if(trade.PositionModify(tk, nsl, ntp))
         {
            Notify(StringFormat("SL attached %.2f TP %.2f to position %I64d", nsl, ntp, id));
            sl = nsl; tp = ntp;
         }
         else
         {
            PrintFormat("SL attach failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
            continue;
         }
      }

      //--- Break-even: profit >= ATR x mult -> SL to entry + 0.1R (once)
      if((fl & TF_BE) == 0 && InpBETriggerATR > 0.0 && R > 0.0)
      {
         double a = BEATR();
         if(a > 0.0 && profit >= InpBETriggerATR * a)
         {
            double be = NormalizeDouble(buy ? open + InpBELockR * R : open - InpBELockR * R, _Digits);
            bool better = (sl <= 0.0 || (buy ? be > sl : be < sl));
            if(!better) fl |= TF_BE;
            else if(StopOK(buy, be, px) && trade.PositionModify(tk, be, tp))
            { fl |= TF_BE; sl = be; }
         }
      }

      //--- Partial close: at x R close % of the INITIAL lot (once, SL untouched)
      if((fl & TF_PARTIAL) == 0 && InpPartialR > 0.0 && InpPartialPct > 0.0 && R > 0.0
         && profit >= InpPartialR * R)
      {
         double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double raw  = v0 * InpPartialPct / 100.0;
         double part = MathMin(NormalizeVolume(raw), vol);
         if(raw < minV - 1e-9 || vol - part < minV - 1e-9)
         {
            PrintFormat("Partial skipped: lot %.2f too small to split", vol);
            fl |= TF_PARTIAL;
         }
         else if(trade.PositionClosePartial(tk, part))
            fl |= TF_PARTIAL;
      }

      if(fl != flOld) SaveTradeState(id, R, v0, fl);

      //--- optional trailing after BE
      if((fl & TF_BE) != 0 && InpTrailATR > 0.0)
      {
         double atr = gSig.ATRAt(1);
         if(atr <= 0.0) continue;
         double nsl = NormalizeDouble(buy ? px - InpTrailATR * atr : px + InpTrailATR * atr, _Digits);
         if((buy ? nsl > sl + _Point : nsl < sl - _Point) && StopOK(buy, nsl, px))
            trade.PositionModify(tk, nsl, tp);
      }
   }

   if(TimeCurrent() - gLastGVClean >= 3600) { CleanTradeState(); gLastGVClean = TimeCurrent(); }
}

double BEATR()
{
   if(hBEATR == INVALID_HANDLE) return 0.0;
   double b[1];
   if(CopyBuffer(hBEATR, 0, 1, 1, b) != 1) return 0.0;
   return b[0];
}

// New SL respects the broker stop level relative to the current price
bool StopOK(const bool buy, const double nsl, const double px)
{
   double stopLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   return (buy ? px - nsl >= stopLvl : nsl - px >= stopLvl);
}

//==================================================================
//  Per-trade state in GlobalVariables (survives MT5 restart):
//  1R distance, initial lot, done-flags - keyed by position id
//==================================================================
string StatePrefix() { return "IFVG_" + IntegerToString(InpMagic) + "_"; }

void SaveTradeState(const long id, const double R, const double v0, const int fl)
{
   if(id <= 0) return;
   string p = StatePrefix() + IntegerToString(id) + "_";
   GlobalVariableSet(p + "R", R);
   GlobalVariableSet(p + "V", v0);
   GlobalVariableSet(p + "F", fl);
}

bool LoadTradeState(const long id, double &R, double &v0, int &fl)
{
   string p = StatePrefix() + IntegerToString(id) + "_";
   if(!GlobalVariableCheck(p + "R")) return false;
   R  = GlobalVariableGet(p + "R");
   v0 = GlobalVariableGet(p + "V");
   fl = (int)GlobalVariableGet(p + "F");
   return true;
}

// Remove state of trades that are no longer open / pending
void CleanTradeState()
{
   string pre = StatePrefix();
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
   {
      string nm = GlobalVariableName(i);
      if(StringFind(nm, pre) != 0 || StringSubstr(nm, StringLen(nm) - 2) != "_R") continue;
      string idStr = StringSubstr(nm, StringLen(pre), StringLen(nm) - StringLen(pre) - 2);
      long id = StringToInteger(idStr);
      if(IsLiveId(id)) continue;
      GlobalVariableDel(pre + idStr + "_R");
      GlobalVariableDel(pre + idStr + "_V");
      GlobalVariableDel(pre + idStr + "_F");
   }
}

bool IsLiveId(const long id)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_IDENTIFIER) == id) return true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if((long)OrderGetTicket(i) == id) return true;
   return false;
}

bool IsMine()
{
   return (PositionGetString(POSITION_SYMBOL) == _Symbol &&
           PositionGetInteger(POSITION_MAGIC) == InpMagic);
}

bool IsMyOrder()
{
   return (OrderGetString(ORDER_SYMBOL) == _Symbol &&
           OrderGetInteger(ORDER_MAGIC) == InpMagic);
}

int CountOrders()
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderGetTicket(i) > 0 && IsMyOrder()) n++;
   return n;
}

int CountPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && IsMine()) n++;
   return n;
}

void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk > 0 && IsMine()) trade.PositionClose(tk);
   }
   DeleteOrders();
}

void DeleteOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ot = OrderGetTicket(i);
      if(ot > 0 && IsMyOrder()) trade.OrderDelete(ot);
   }
}

// Money lost if a trade of 'lots' goes from entry to sl (0 if sl is at/after entry)
double RiskMoney(const ENUM_ORDER_TYPE type, const double lots, const double entry, const double sl)
{
   if(sl <= 0.0) return 0.0;
   if(type == ORDER_TYPE_BUY ? sl >= entry : sl <= entry) return 0.0;
   double p = 0.0;
   if(!OrderCalcProfit(type, _Symbol, lots, entry, sl, p)) return 0.0;
   return MathAbs(p);
}

// Risk still on the table: open positions + pending orders (trades at BE count 0)
double OpenRiskMoney()
{
   double sum = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0 || !IsMine()) continue;
      ENUM_ORDER_TYPE t = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      sum += RiskMoney(t, PositionGetDouble(POSITION_VOLUME),
                       PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL));
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderGetTicket(i) == 0 || !IsMyOrder()) continue;
      long ot = OrderGetInteger(ORDER_TYPE);
      bool buy = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP);
      sum += RiskMoney(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, OrderGetDouble(ORDER_VOLUME_CURRENT),
                       OrderGetDouble(ORDER_PRICE_OPEN), OrderGetDouble(ORDER_SL));
   }
   return sum;
}

//==================================================================
//  Account guards (daily DD / max DD / profit target)
//==================================================================
bool GuardsOK()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   int key = t.year * 1000 + t.day_of_year;
   if(key != gDayKey)
   {
      gDayKey = key;
      gDayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
      gDailyHit = false;
   }
   if(gStopped) return false;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpMaxDDPct > 0.0 && eq <= gStartBal * (1.0 - InpMaxDDPct / 100.0))
   {
      gStopped = true;
      if(InpCloseOnGuard) CloseAll();
      Notify(StringFormat("MAX DD hit (equity %.2f) - EA stopped", eq));
      return false;
   }
   if(InpProfitTargetPct > 0.0 && eq >= gStartBal * (1.0 + InpProfitTargetPct / 100.0))
   {
      gStopped = true;
      CloseAll();
      Notify(StringFormat("PROFIT TARGET hit (equity %.2f) - EA stopped", eq));
      return false;
   }
   if(InpDailyDDPct > 0.0 && !gDailyHit && eq <= gDayStartBal * (1.0 - InpDailyDDPct / 100.0))
   {
      gDailyHit = true;
      if(InpCloseOnGuard) CloseAll();
      Notify(StringFormat("DAILY DD hit (equity %.2f) - pause until tomorrow", eq));
   }
   return !gDailyHit;
}

//==================================================================
//  Lot sizing (risk % of balance, works on Cent accounts)
//==================================================================
double CalcLotSize(const ENUM_ORDER_TYPE type, const double entry, const double sl)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);
   if(MathAbs(entry - sl) <= 0.0 || riskMoney <= 0.0) return 0.0;

   double lossPerLot = 0.0;
   if(!OrderCalcProfit(type, _Symbol, 1.0, entry, sl, lossPerLot))
   {
      Print("OrderCalcProfit failed - cannot size lot");
      return 0.0;
   }
   lossPerLot = MathAbs(lossPerLot);
   if(lossPerLot <= 0.0) return 0.0;

   double lots = NormalizeVolume(riskMoney / lossPerLot);
   double riskPct = (balance > 0.0 ? lossPerLot * lots / balance * 100.0 : 0.0);
   if(InpMaxRiskCapPct > 0.0 && riskPct > InpMaxRiskCapPct)
   {
      PrintFormat("Skip: %.2f lots would risk %.2f%% (> cap %.2f%%)", lots, riskPct, InpMaxRiskCapPct);
      return 0.0;
   }
   return lots;
}

// Shrink lot so the margin level after the trade stays >= InpMinMarginLevel (0 lot = skip)
double FitMargin(const ENUM_ORDER_TYPE type, double lots, const double price)
{
   if(InpMaxLots > 0.0 && lots > InpMaxLots) lots = NormalizeVolume(InpMaxLots);
   if(InpMinMarginLevel <= 0.0) return lots;

   double perLot = 0.0;
   if(!OrderCalcMargin(type, _Symbol, 1.0, price, perLot) || perLot <= 0.0) return lots;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double used   = AccountInfoDouble(ACCOUNT_MARGIN);
   double room   = equity / (InpMinMarginLevel / 100.0) - used;   // margin we may still add
   double maxLot = room / perLot;
   if(lots <= maxLot) return lots;

   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   double cut = MathFloor(maxLot / step + 1e-9) * step;
   if(cut < minV)
   {
      PrintFormat("Skip: not enough margin (level would drop below %.0f%%)", InpMinMarginLevel);
      return 0.0;
   }
   PrintFormat("Lot cut %.2f -> %.2f to keep margin level >= %.0f%% (risk now below target)",
               lots, cut, InpMinMarginLevel);
   return NormalizeVolume(cut);
}

double NormalizeVolume(double vol)
{
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;

   vol = MathFloor(vol / step + 1e-9) * step;
   if(vol < minV) vol = minV;
   if(vol > maxV) vol = maxV;

   int digits = (int)MathRound(MathLog10(1.0 / step));
   if(digits < 0) digits = 0;
   return NormalizeDouble(vol, digits);
}

//==================================================================
//  News filter (ported from XAUUSD_H4_BodyBreak_EA)
//  - CSV file (Common\Files, e.g. from FF_News_Exporter): works in tester
//  - MT5 economic calendar: live only (empty in tester)
//==================================================================
bool InList(const string list, const string val)
{
   string parts[];
   int n = StringSplit(list, ',', parts);
   for(int i = 0; i < n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p); StringTrimRight(p);
      if(StringCompare(p, val, false) == 0) return true;
   }
   return false;
}

// "yyyy.mm.dd" + "HH:MM" -> server time (with offset). 0 = header / bad row.
datetime ParseNewsTime(string dateStr, string timeStr)
{
   StringTrimLeft(dateStr); StringTrimRight(dateStr);
   StringTrimLeft(timeStr); StringTrimRight(timeStr);
   if(StringLen(dateStr) < 8) return 0;
   if(StringLen(timeStr) < 4) timeStr = "00:00";   // all-day / tentative
   datetime t = StringToTime(dateStr + " " + timeStr);
   if(t <= 0) return 0;
   return t + (datetime)(InpFFTimeOffsetHours * 3600);
}

void LoadFFNews()
{
   gFFCount = 0;
   ArrayResize(gFFTime, 0);
   if(!InpUseFFNews) return;

   // FILE_COMMON: the tester sandbox and the live terminal both see Common\Files
   int fh = FileOpen(InpFFNewsFile, FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
   {
      Notify("NEWS file NOT found: " + InpFFNewsFile + " (put it in Common\\Files) - CSV news OFF");
      return;
   }

   while(!FileIsEnding(fh))
   {
      string c1 = FileReadString(fh);
      if(c1 == "" && FileIsLineEnding(fh)) continue;
      string c2 = FileReadString(fh);
      string c3 = FileReadString(fh);
      string c4 = FileReadString(fh);
      while(!FileIsLineEnding(fh) && !FileIsEnding(fh)) FileReadString(fh); // extra cols (Title)

      datetime t = ParseNewsTime(c1, c2);
      if(t <= 0) continue;
      StringTrimLeft(c3); StringTrimRight(c3);
      StringTrimLeft(c4); StringTrimRight(c4);
      if(!InList(InpNewsCurrencies, c3) || !InList(InpFFBlockImpact, c4)) continue;

      ArrayResize(gFFTime, gFFCount + 1);
      gFFTime[gFFCount++] = t;
   }
   FileClose(fh);
   ArraySort(gFFTime);

   if(gFFCount > 0)
      Notify(StringFormat("NEWS loaded: %d events (%s) from %s | %s -> %s",
                          gFFCount, InpFFBlockImpact, InpFFNewsFile,
                          TimeToString(gFFTime[0], TIME_DATE),
                          TimeToString(gFFTime[gFFCount - 1], TIME_DATE)));
   else
      Notify("NEWS file loaded but 0 matching events - check currency/impact columns");
}

// First loaded event time in [from, to], or 0 if none (binary search).
datetime FFNewsAt(const datetime from, const datetime to)
{
   int lo = 0, hi = gFFCount;
   while(lo < hi)
   {
      int mid = (lo + hi) / 2;
      if(gFFTime[mid] < from) lo = mid + 1; else hi = mid;
   }
   if(lo < gFFCount && gFFTime[lo] <= to) return gFFTime[lo];
   return 0;
}

bool IsNewsBlocking()
{
   datetime now  = TimeCurrent();
   datetime from = now - (datetime)(InpNewsMinutesAfter  * 60);
   datetime to   = now + (datetime)(InpNewsMinutesBefore * 60);

   if(FFNewsAt(from, to) > 0) return true;
   if(!InpEnableNewsFilter || MQLInfoInteger(MQL_TESTER)) return false;

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to, NULL, NULL);
   for(int i = 0; i < total; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)  continue;

      MqlCalendarCountry country;
      if(CalendarCountryById(ev.country_id, country) && !InList(InpNewsCurrencies, country.currency))
         continue;
      return true;
   }
   return false;
}

// Close open trades shortly before a CSV news event (checked every tick).
void ManageNewsClose()
{
   if(!InpNewsClosePositions || gFFCount == 0) return;
   datetime now = TimeCurrent();
   datetime ev  = FFNewsAt(now, now + (datetime)(InpNewsCloseMinutes * 60));
   if(ev == 0 || ev == gLastNewsClose) return;
   gLastNewsClose = ev;
   if(CountPositions() + CountOrders() == 0) return;

   Notify(StringFormat("NEWS at %s - closing open trades", TimeToString(ev, TIME_DATE | TIME_MINUTES)));
   CloseAll();
}

//==================================================================
//  Misc
//==================================================================
void Notify(const string msg)
{
   string full = "[XAU-IFVG] " + msg;
   Print(full);
   if(InpNotify && !MQLInfoInteger(MQL_TESTER)) SendNotification(full);
}

void DrawArrow(const int dir, const double price)
{
   if(!InpDrawZones) return;
   datetime t = TimeCurrent();
   string nm = "IFVG_ENTRY_" + IntegerToString((long)t);
   ObjectCreate(0, nm, dir > 0 ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0, t, price);
}
//+------------------------------------------------------------------+
