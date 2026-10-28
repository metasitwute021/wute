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
//|  - Stop loss  : KRV keeps it secret -> selectable modes here     |
//|  - Exit       : partial close ("แบ่งขาย") + move SL to BE,       |
//|                 runner to final TP (clip: win rate 64% because   |
//|                 of the partial close)                            |
//|  - Sizing     : fixed 1% risk per trade (clip: +397% 2020-now,   |
//|                 PF 1.47, ~1,100-1,200 trades, DD ~13%)           |
//|  - Max orders : 2 at the same time (clip: "สูงสุดสองออเดอร์")    |
//|  - Guards     : risk cap, daily DD, max DD (prop style), spread, |
//|                 Friday close                                     |
//|                                                                  |
//|  !! Gap size / strong-move / SL values are NOT given in the clip |
//|  !! -> optimise them, then Walk-Forward + forward test (KRV).    |
//+------------------------------------------------------------------+
#property copyright "Metasit - IFVG EA"
#property version   "1.00"
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
enum ENUM_CONFIRM_MODE
{
   CONF_CLOSE_OUTSIDE = 0,  // Touch zone, close back outside it (bounce)
   CONF_CLOSE_INSIDE  = 1   // Touch zone, close anywhere not through it
};

//==================================================================
//  Inputs
//==================================================================
input group "=== General ==="
input long     InpMagic              = 20261028;    // Magic number
input string   InpComment            = "IFVG";      // Order comment
input bool     InpDrawZones          = true;        // Draw IFVG zones on chart
input bool     InpNotify             = false;       // Push notifications (live only)

input group "=== FVG detection (signal TF) ==="
input ENUM_TIMEFRAMES InpSignalTF    = PERIOD_M30;  // Signal timeframe
input int      InpATRPeriod          = 14;          // ATR period (scales all sizes)
input double   InpMinGapATR          = 0.25;        // Min gap (High bar1 <-> Low bar3) x ATR
input double   InpMaxGapATR          = 2.5;         // Max gap x ATR (0 = off)
input double   InpStrongBodyATR      = 0.8;         // Bar 2 (Strong Move) body >= x ATR
input double   InpStrongBodyRatio    = 0.55;        // Bar 2 body / range >= this
input int      InpFVGMaxAgeBars      = 48;          // FVG must be broken within N bars

input group "=== Inversion & retest ==="
input double   InpInvBodyATR         = 0.0;         // Breaking bar body >= x ATR (0 = off)
input int      InpMaxRetestBars      = 24;          // Retest must come within N bars of inversion
input int      InpZoneMaxAgeBars     = 96;          // IFVG kept alive N bars (for HTF bias)
input ENUM_CONFIRM_MODE InpConfirm   = CONF_CLOSE_OUTSIDE; // Retest confirmation
input bool     InpNeedDirCandle      = false;       // Retest bar must close in trade direction
input double   InpTouchTolATR        = 0.0;         // Count as touch within x ATR of zone
input int      InpWarmupBars         = 300;         // History bars to pre-build zones

input group "=== Trend filter (EMA) ==="
input bool     InpUseTrend           = true;        // Trade only with the EMA trend
input ENUM_TIMEFRAMES InpTrendTF     = PERIOD_H1;   // Trend timeframe
input int      InpEMAPeriod          = 60;          // EMA period (clip: EMA 60)

input group "=== Higher-TF IFVG helper ==="
input bool     InpUseHTFIFVG         = true;        // Latest live HTF IFVG must agree
input ENUM_TIMEFRAMES InpHTF         = PERIOD_H1;   // Helper timeframe (clip: H1)

input group "=== Stop loss / Take profit ==="
input ENUM_SL_MODE InpSLMode         = SL_ZONE_EDGE; // Stop loss mode
input double   InpSLBufferATR        = 0.20;        // SL buffer x ATR
input double   InpMinSL_ATR          = 0.50;        // Min SL distance x ATR (widen to this)
input double   InpMaxSL_ATR          = 3.0;         // Skip trade if SL > x ATR (0 = off)
input double   InpTP_R               = 3.0;         // Final TP in R (0 = no TP, runner trails)

input group "=== Partial close / Break-even / Trailing ==="
input double   InpPartialR           = 1.0;         // Partial close at x R (0 = off)
input double   InpPartialPct         = 50.0;        // % volume to close at partial
input bool     InpMoveBE             = true;        // Move SL to BE at partial level
input double   InpBEOffsetPts        = 20;          // BE offset (points, locks small profit)
input double   InpTrailATR           = 0.0;         // Trail runner by x ATR after BE (0 = off)

input group "=== Risk management ==="
input double   InpRiskPercent        = 1.0;         // Risk per trade (% balance)
input double   InpMaxRiskCapPct      = 1.5;         // Skip if min lot risks > this % (0 = off)
input int      InpMaxPositions       = 2;           // Max open positions (clip: 2)

input group "=== Account guards (prop style) ==="
input double   InpDailyDDPct         = 0.0;         // Daily loss limit % (0 = off)
input double   InpMaxDDPct           = 0.0;         // Max loss % from start balance (0 = off)
input double   InpProfitTargetPct    = 0.0;         // Stop at +% from start (0 = off)
input double   InpStartBalance       = 0.0;         // Start balance (0 = balance at start)
input bool     InpCloseOnGuard       = true;        // Close positions when a guard trips

input group "=== Filters ==="
input int      InpMaxSpreadPoints    = 60;          // Skip entry if spread > this (0 = off)
input int      InpStartHour          = 0;           // Trade from hour (server)
input int      InpEndHour            = 24;          // ...until hour (server, exclusive)
input bool     InpFridayClose        = false;       // Close all before weekend
input int      InpFridayCloseHour    = 21;          // Friday close hour (server)

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

class CIFVGEngine
{
public:
   ENUM_TIMEFRAMES   tf;
   int               hATR;
   Zone              z[];
   datetime          lastOpen;
   bool              draw;
   string            tag;

   bool Init(const ENUM_TIMEFRAMES t, const bool d, const string tg)
   {
      tf = t; draw = d; tag = tg; lastOpen = 0;
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
      int idx;
      for(int s = from; s >= 1; s--) ProcessBar(s, idx);
      lastOpen = iTime(_Symbol, tf, 0);
      return true;
   }

   // Call every tick. On a new bar processes the just-closed bar.
   // Returns signal direction (+1/-1/0) and zone index in sigIdx.
   int Update(int &sigIdx)
   {
      sigIdx = -1;
      datetime t = iTime(_Symbol, tf, 0);
      if(t == 0 || t == lastOpen) return 0;
      lastOpen = t;
      return ProcessBar(1, sigIdx);
   }

   // Process closed bar at shift s (order matters: retest -> inversion -> new FVG,
   // so a bar can never break and retest the same zone)
   int ProcessBar(const int s, int &sigIdx)
   {
      sigIdx = -1;
      int sigDir = 0;
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
            bool broken = (z[i].dir > 0 ? c < z[i].bottom : c > z[i].top);
            if(broken || z[i].age > InpZoneMaxAgeBars)
            {
               z[i].state = ZS_DEAD;
               CloseBox(i, bt);
               continue;
            }
            if(z[i].state != ZS_ACTIVE) continue;

            z[i].retestAge++;
            bool touched = (z[i].dir > 0 ? l <= z[i].top + tol : h >= z[i].bottom - tol);
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
         bool inv = (z[i].fvgDir < 0 ? c > z[i].top : c < z[i].bottom);
         if(inv && InpInvBodyATR > 0.0 && MathAbs(c - o) < InpInvBodyATR * atr) inv = false;
         if(inv)
         {
            z[i].dir       = -z[i].fvgDir;
            z[i].state     = ZS_ACTIVE;
            z[i].invTime   = bt;
            z[i].age       = 0;
            z[i].retestAge = 0;
            DrawBox(i, bt);
         }
      }

      DetectFVG(s);
      Compact();
      return sigDir;
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
      if(body < InpStrongBodyATR * atr || body / r2 < InpStrongBodyRatio) return;

      int dir = 0; double top = 0, bot = 0;
      if(c2 > o2 && l3 > h1)      { dir = +1; bot = h1; top = l3; }   // bullish FVG
      else if(c2 < o2 && h3 < l1) { dir = -1; bot = h3; top = l1; }   // bearish FVG
      if(dir == 0) return;

      double gap = top - bot;
      if(gap < InpMinGapATR * atr) return;
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
bool         gWarm       = false;
int          gDayKey     = -1;
double       gDayStartBal= 0.0;
double       gStartBal   = 0.0;
bool         gDailyHit   = false;
bool         gStopped    = false;
ulong        gPartialDone[];   // tickets already partially closed

//==================================================================
//  Init / Deinit
//==================================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(!gSig.Init(InpSignalTF, InpDrawZones, "IFVG_SIG_")) return INIT_FAILED;
   if(InpUseHTFIFVG && !gHTF.Init(InpHTF, false, "IFVG_HTF_")) return INIT_FAILED;
   if(InpUseTrend)
   {
      hEMA = iMA(_Symbol, InpTrendTF, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(hEMA == INVALID_HANDLE) return INIT_FAILED;
   }
   gStartBal = (InpStartBalance > 0.0 ? InpStartBalance : AccountInfoDouble(ACCOUNT_BALANCE));
   gWarm = false;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   gSig.Deinit();
   if(InpUseHTFIFVG) gHTF.Deinit();
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
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

   // engines must see every bar even when we are not allowed to trade
   int dummy, sigIdx;
   if(InpUseHTFIFVG) gHTF.Update(dummy);
   int dir = gSig.Update(sigIdx);
   if(dir == 0 || sigIdx < 0 || !canTrade) return;

   //--- filters
   if(CountPositions() >= InpMaxPositions && InpMaxPositions > 0) return;
   if(!InSession()) return;
   if(InpMaxSpreadPoints > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPoints)
   { Print("Skip: spread too wide"); return; }
   if(InpUseTrend && TrendDir() != dir) return;
   if(InpUseHTFIFVG && gHTF.Bias() != dir) return;

   OpenTrade(dir, gSig.z[sigIdx]);
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
void OpenTrade(const int dir, const Zone &zn)
{
   double atr   = gSig.ATRAt(1);
   double buf   = InpSLBufferATR * atr;
   double entry = (dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                           : SymbolInfoDouble(_Symbol, SYMBOL_BID));
   double barL  = iLow(_Symbol, InpSignalTF, 1), barH = iHigh(_Symbol, InpSignalTF, 1);

   double slZone = (dir > 0 ? zn.bottom - buf : zn.top + buf);
   double slBar  = (dir > 0 ? barL - buf : barH + buf);
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

   double stopLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(dist < stopLvl) { Print("Skip: SL inside broker stop level"); return; }

   double tp = 0.0;
   if(InpTP_R > 0.0) tp = (dir > 0 ? entry + InpTP_R * dist : entry - InpTP_R * dist);
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   ENUM_ORDER_TYPE type = (dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double lots = CalcLotSize(type, entry, sl);
   if(lots <= 0.0) return;

   bool ok = (dir > 0 ? trade.Buy(lots, _Symbol, 0.0, sl, tp, InpComment)
                      : trade.Sell(lots, _Symbol, 0.0, sl, tp, InpComment));
   if(ok)
   {
      Notify(StringFormat("%s %.2f @ %.2f SL %.2f TP %.2f | zone %.2f-%.2f",
                          dir > 0 ? "BUY" : "SELL", lots, entry, sl, tp, zn.bottom, zn.top));
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

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !IsMine()) continue;
      if(friday) { trade.PositionClose(tk); continue; }

      bool   buy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      double px   = (buy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
      if(sl <= 0.0) continue;

      // SL already at/after entry, or ticket in the list -> partial/BE done
      bool beDone = (buy ? sl >= open : sl <= open) || IsPartialDone(tk);
      if(!beDone && InpPartialR > 0.0)
      {
         double R = MathAbs(open - sl);
         bool hit = (buy ? px >= open + InpPartialR * R : px <= open - InpPartialR * R);
         if(hit)
         {
            if(InpPartialPct > 0.0)
            {
               double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               double part = NormalizeVolume(vol * InpPartialPct / 100.0);
               if(part >= minV && vol - part >= minV - 1e-9)
                  trade.PositionClosePartial(tk, part);
            }
            if(InpMoveBE)
            {
               double be = (buy ? open + InpBEOffsetPts * _Point : open - InpBEOffsetPts * _Point);
               trade.PositionModify(tk, NormalizeDouble(be, _Digits), tp);
            }
            MarkPartialDone(tk);
         }
         continue;
      }

      if(beDone && InpTrailATR > 0.0)
      {
         double atr = gSig.ATRAt(1);
         if(atr <= 0.0) continue;
         double nsl = NormalizeDouble(buy ? px - InpTrailATR * atr : px + InpTrailATR * atr, _Digits);
         if(buy ? nsl > sl + _Point : nsl < sl - _Point)
            trade.PositionModify(tk, nsl, tp);
      }
   }
}

bool IsMine()
{
   return (PositionGetString(POSITION_SYMBOL) == _Symbol &&
           PositionGetInteger(POSITION_MAGIC) == InpMagic);
}

bool IsPartialDone(const ulong tk)
{
   for(int i = ArraySize(gPartialDone) - 1; i >= 0; i--)
      if(gPartialDone[i] == tk) return true;
   return false;
}

void MarkPartialDone(const ulong tk)
{
   int n = ArraySize(gPartialDone);
   if(n >= 200) { ArrayRemove(gPartialDone, 0, 100); n = ArraySize(gPartialDone); }
   ArrayResize(gPartialDone, n + 1);
   gPartialDone[n] = tk;
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
