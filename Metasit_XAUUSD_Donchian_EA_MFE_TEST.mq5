//+------------------------------------------------------------------+
//|                            Metasit_XAUUSD_Donchian_EA.mq5         |
//|        Donchian breakout trend EA for XAUUSD (Gold)              |
//|        *** MERGED build ***                                       |
//|                                                                  |
//|  This file combines the two versions you liked:                  |
//|    - Entry + Stop Loss : taken from EA021 (the PROFITABLE one)    |
//|         => default InpSLMode = SL_DONCHIAN                        |
//|         (Buy SL = Donchian low - 0.75*ATR ; Sell = high + ...)    |
//|    - Lot sizing + partial close : taken from EA v1.50 (the one    |
//|         whose lot output / scale-out you were happy with)         |
//|         => CalcLotSize via OrderCalcProfit() (accurate on Cent)   |
//|                                                                  |
//|  So: the wide Donchian-channel stop lets winners run (profit of   |
//|  file 2), while the OrderCalcProfit sizing + 40% partial give     |
//|  the lot behaviour of file 1.  Flip InpSLMode back to SL_ATR if   |
//|  you ever want the old tight-stop behaviour of file 1.           |
//|                                                                  |
//|  *** v2.00  "Metasit" prop-safe build (The5ers 25K ready) ***     |
//|    - SL = ATR (tight) + risk 1%  => ~1% loss per trade           |
//|    - HARD CAP: skips any trade whose min-lot risk > cap          |
//|      (InpMaxRiskCapPercent) -> a single trade can NOT fail you   |
//|    - News filter asymmetric +90 / -30 min (as tuned earlier)     |
//|    - Re-entry cooldown 1 bar: manual/auto close -> recalc signal |
//|    - Partial 40% @1R kept; break-even @0.25R kept                |
//|    - Profit-target auto-stop: hit target % -> close all + stop   |
//|      (InpProfitTargetPercent, e.g. 6.0 for The5ers Step 1)       |
//|  *** v2.01 : colourful emoji push notifications ***               |
//|  *** v2.02 : InpTrailWidest (let winners run -> higher PF) ***    |
//|  *** v2.03 : EMERGENCY BRAKE - InpMaxTotalLossPercent ***         |
//|      (lose X% from start -> close all + stop; never hit the limit)|
//|  *** v2.04 : DD LOCK - InpPeakDDStopPercent ***                   |
//|      (drop X% from PEAK equity -> close all + stop; protects gains)|
//|                                                                  |
//|  Strategy summary                                                |
//|  - Market / TF : XAUUSD, signals on H4, trailing managed on M30  |
//|  - Entry       : Donchian(20) breakout, filtered by SMA(50)      |
//|                  trend direction and ADX(14) > 20                |
//|  - Stop Loss   : selectable (InpSLMode):                         |
//|                    SL_ATR      = entry -/+ mult * ATR(16)   (def) |
//|                    SL_DONCHIAN = Donchian band -/+ buffer*ATR     |
//|  - Sizing      : risk 1% of balance via OrderCalcProfit (Cent OK)|
//|  - Exit        : no fixed TP, SL only, let profit run via        |
//|                  multi-layer trailing                            |
//|  - Management  : break-even @0.25R, partial 40% @1R, multi       |
//|                  trailing layers (pick the safest stop)          |
//|  - Protection  : per-trade risk cap (skip if over), profit       |
//|                  target auto-stop, max DD pause, daily DD stop,  |
//|                  news filter +90 / -30 min (asymmetric)         |
//|  - Confidence  : 0.5x..2.0x lot scaling on last 10 trades        |
//|                  (win rate + profit factor) with 0.25 smoothing  |
//|  - Alerts      : push notifications on every event               |
//+------------------------------------------------------------------+
#property copyright "Metasit XAUUSD Donchian EA - MFE DIAGNOSTIC (backtest only)"
#property version   "2.04-mfe"
#property description "DIAGNOSTIC BUILD: logs how far trades run (MFE in R). Do NOT use on live - run in Strategy Tester only."
#property strict

#include <Trade\Trade.mqh>

//==================================================================
//  Enums for account / lot configuration (Risk Management group)
//==================================================================
// ชนิดบัญชี: มาตรฐาน หรือ Cent
enum ENUM_ACCT_MODE
{
   ACCOUNT_STANDARD = 0,   // Standard account
   ACCOUNT_CENT     = 1    // Cent account
};

// จำนวนทศนิยมของราคาสินทรัพย์ (ทองคำส่วนใหญ่ = 2 ตำแหน่ง)
enum ENUM_ASSET_MODE
{
   ASSET_2_DECIMAL = 0,    // 2 decimals (e.g. XAUUSD 1234.56)
   ASSET_3_DECIMAL = 1     // 3 decimals (e.g. 1234.567)
};

// โปรไฟล์สัมประสิทธิ์การคำนวณล็อต (K) ตามชนิด/โบรกเกอร์ของบัญชี
enum ENUM_K_MODE
{
   K_STA     = 0,          // Standard account
   K_CENT    = 1,          // Typical Cent account
   K_CENT_XM = 2           // XM-style Cent account
};

// วิธีตั้ง Stop Loss เริ่มต้น
enum ENUM_SL_MODE
{
   SL_ATR      = 0,        // SL = entry +/- (mult x ATR)   <- tight stop (old file 1)
   SL_DONCHIAN = 1         // SL = Donchian band +/- (buffer x ATR)  <- profitable (file 2)
};

//==================================================================
//  Inputs
//==================================================================
input group "=== General ==="
input long     InpMagic              = 20250117;   // Magic number
input bool     InpEnableNotifications= true;       // Send push notifications
input string   InpNotifPrefix        = "[XAU-EA] ";// Notification prefix

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES InpEntryTF      = PERIOD_H4;  // Entry / signal timeframe
input ENUM_TIMEFRAMES InpTrailTF      = PERIOD_M30; // Trailing management timeframe

input group "=== Entry filters ==="
input int      InpDonchianPeriod     = 20;         // Donchian channel period
input int      InpMAPeriod           = 50;         // Trend SMA period
input int      InpADXPeriod          = 14;         // ADX period
input double   InpADXMin             = 20.0;       // Minimum ADX to trade

input group "=== Stop Loss ==="
input ENUM_SL_MODE InpSLMode             = SL_ATR;      // SL method (ATR = tight KRV-like stop ~75pt; DONCHIAN = wide channel)
input int          InpSL_ATRPeriod       = 16;     // ATR period for SL (entry TF)
input double       InpSL_ATRMult         = 1.5;    // ATR mode: SL = mult x ATR (tight ~1% risk; tune 1.2-2.0)
input double       InpSL_DonchBufferMult = 0.75;   // Donchian mode: buffer = mult x ATR

input group "=== Risk Management ==="
input double          InpRiskPercent = 1.0;             // Risk per trade (% balance)
input ENUM_ACCT_MODE  InpAccountType = ACCOUNT_CENT;    // Account type
input ENUM_ASSET_MODE InpAssetType   = ASSET_2_DECIMAL; // Asset price decimals
input ENUM_K_MODE     InpKParameter  = K_CENT;          // Lot coefficient profile (K)
input double          InpLotStepOverride = 0.0;         // Force lot step (0 = auto/broker; e.g. 0.01)
input int             InpMaxPositions= 1;               // Max simultaneous positions
input int             InpReentryCooldownBars = 1;        // Wait N entry-TF bars after a close before re-entering (0 = off, anti-whipsaw)
input double          InpMaxRiskCapPercent = 1.7;        // SKIP a trade if min-lot would risk more than this % (0 = never skip; prop-safe guard)

input group "=== Trade management ==="
input double   InpBreakEvenR         = 0.25;       // Move SL to BE at this R
input double   InpBE_BufferPts       = 20;         // BE buffer (points beyond entry)
input double   InpPartialR           = 1.0;        // Partial close at this R
input double   InpPartialPercent     = 40.0;       // Percent of position to close
input bool     InpLockTrailUntilPartial = true;    // Lock trailing until 1R partial (true = let it breathe, fewer premature exits)

input group "=== Trailing layers (M30) ==="
input int      InpTr1_ATRPeriod      = 18;         // Layer 1 ATR period
input double   InpTr1_ATRMult        = 5.75;       // Layer 1 ATR multiplier
input int      InpTr2_ATRPeriod      = 12;         // Strong move ATR period
input double   InpTr2_ATRMult        = 2.75;       // Strong move ATR multiplier
input int      InpTr3_ATRPeriod      = 16;         // Mini strong move ATR period
input double   InpTr3_ATRMult        = 2.0;        // Mini strong move ATR multiplier
input int      InpSwingLookback      = 20;         // Swing high/low lookback (M30 bars)
input int      InpCandleBackShift    = 3;          // "3rd candle" shift for trailing
input bool     InpTrailWidest        = true;       // Trailing stop choice: true = WIDEST (let winners run, higher PF) / false = tightest

input group "=== Drawdown protection ==="
input double   InpMaxDD_Percent      = 100.0;      // [MFE-TEST off] Max drawdown -> pause EA (%)  (100 = disabled for full run)
input double   InpMaxDD_ResumeBuffer = 2.0;        // Resume when DD below (Max - buffer)
input double   InpDailyDD_Percent    = 100.0;      // [MFE-TEST off] Daily drawdown -> stop for day (%)  (100 = disabled)
input double   InpProfitTargetPercent = 0.0;       // [MFE-TEST off] Reach this % profit -> close all + STOP (0 = off)
input double   InpMaxTotalLossPercent = 0.0;       // [MFE-TEST off] EMERGENCY BRAKE (0 = off)
input double   InpPeakDDStopPercent  = 0.0;        // [MFE-TEST off] DD LOCK (0 = off)

input group "=== News filter ==="
input bool     InpEnableNewsFilter   = true;       // Avoid trading around news
input int      InpNewsMinutesBefore  = 90;         // Block window BEFORE news (min) - wide, avoid pre-news uncertainty
input int      InpNewsMinutesAfter   = 30;         // Block window AFTER news (min) - short, re-enter to catch post-news trend
input string   InpNewsCurrencies     = "USD";      // Currencies to watch (comma sep.)

input group "=== Confidence system ==="
input bool     InpEnableConfidence   = true;       // Scale lot by recent performance
input int      InpConfidenceTrades   = 10;         // Number of recent trades to assess
input double   InpConfidenceMin      = 0.5;        // Minimum lot multiplier
input double   InpConfidenceMax      = 2.0;        // Maximum lot multiplier
input double   InpConfidenceSmooth   = 0.25;       // Smoothing factor (EMA alpha)

//==================================================================
//  Globals
//==================================================================
CTrade   trade;

// indicator handles
int hMA       = INVALID_HANDLE;
int hADX      = INVALID_HANDLE;
int hATRslBuf = INVALID_HANDLE;   // entry-TF ATR(16) used for the SL buffer
int hATR1     = INVALID_HANDLE;   // trailing layer 1 (M30)
int hATR2     = INVALID_HANDLE;   // trailing layer 2 - strong move (M30)
int hATR3     = INVALID_HANDLE;   // trailing layer 3 - mini strong move (M30)

// new-bar tracking
datetime gLastEntryBar = 0;
int      gCooldownBarsLeft = 0;   // entry-TF bars still to skip after a full close (re-entry cooldown)
double   gStartBalance     = 0.0; // baseline captured at init, for the profit-target / loss-stop
bool     gTargetReached    = false; // true once InpProfitTargetPercent is hit -> stop trading
bool     gLossStopReached  = false; // true once InpMaxTotalLossPercent is hit -> stop trading
bool     gPeakDDStopReached = false; // true once InpPeakDDStopPercent (give-back from peak) is hit -> stop trading

// per-position state (parallel arrays keyed by ticket)
ulong    gPosTicket[];
double   gPosInitRisk[];   // price distance of initial risk (R), per position
double   gPosInitVol[];    // original volume
bool     gPosBEDone[];
bool     gPosPartialDone[];
double   gPosMaxFav[];     // [MFE-TEST] max favorable price distance reached, per position

// [MFE-TEST] Maximum Favorable Excursion stats (how far trades run, in R)
int      gMfeTotal = 0;                                       // closed trades counted
double   gMfeSumR  = 0.0;                                     // sum of MFE-in-R (for average)
double   gMfeBestR = 0.0;                                     // best single MFE-in-R
double   gMfeLevels[] = {0.25, 0.5, 0.7, 1.0, 1.25, 1.5, 2.0, 3.0};
int      gMfeCounts[8];                                       // trades reaching each level

// drawdown / protection state
double   gPeakEquity     = 0.0;
bool     gMaxDDPaused    = false;
datetime gDayStart       = 0;
double   gDayStartEquity = 0.0;
bool     gDailyStopped   = false;

// news state
bool     gInNews         = false;

// confidence state
double   gClosedProfit[];   // ring buffer of recent closed-trade results
double   gConfidence     = 1.0;

// accumulator for per-position realized profit (to detect full close)
ulong    gAccPos[];
double   gAccProfit[];

//+------------------------------------------------------------------+
//| Helper: send notification + log                                  |
//+------------------------------------------------------------------+
void Notify(const string msg)
{
   Print(msg);
   if(InpEnableNotifications)
      SendNotification(InpNotifPrefix + msg);
}

//+------------------------------------------------------------------+
//| Helper: read a single indicator buffer value at shift            |
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
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(30);

   hMA       = iMA (_Symbol, InpEntryTF, InpMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   hADX      = iADX(_Symbol, InpEntryTF, InpADXPeriod);
   hATRslBuf = iATR(_Symbol, InpEntryTF, InpSL_ATRPeriod);
   hATR1     = iATR(_Symbol, InpTrailTF, InpTr1_ATRPeriod);
   hATR2     = iATR(_Symbol, InpTrailTF, InpTr2_ATRPeriod);
   hATR3     = iATR(_Symbol, InpTrailTF, InpTr3_ATRPeriod);

   if(hMA==INVALID_HANDLE || hADX==INVALID_HANDLE || hATRslBuf==INVALID_HANDLE ||
      hATR1==INVALID_HANDLE || hATR2==INVALID_HANDLE || hATR3==INVALID_HANDLE)
   {
      Print("Failed to create one or more indicator handles");
      return(INIT_FAILED);
   }

   gPeakEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
   gDayStart       = 0;
   gDayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   gConfidence     = 1.0;
   gCooldownBarsLeft = 0;
   gStartBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
   gTargetReached  = false;
   gLossStopReached = false;
   gPeakDDStopReached = false;

   EventSetTimer(5);  // protection / news checks every 5 sec

   // Diagnostic: print the broker's real lot constraints so the effective
   // granularity (esp. for K_CENT_XM) can be verified in the Experts log.
   PrintFormat("LOT INFO %s | min=%.2f step=%.2f max=%.2f | effStep=%.2f | K=%s | tickVal=%.5f tickSize=%.5f contract=%.2f | %s %s",
               _Symbol,
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
               EffectiveLotStep(),
               EnumToString(InpKParameter),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE),
               AccountInfoString(ACCOUNT_CURRENCY),
               (InpAccountType==ACCOUNT_CENT ? "CENT" : "STANDARD"));

   Notify("🚀 EA started on " + _Symbol + " (entry " + EnumToString(InpEntryTF) +
          ", trail " + EnumToString(InpTrailTF) + ", SLmode " + EnumToString(InpSLMode) + ")");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(hMA!=INVALID_HANDLE)       IndicatorRelease(hMA);
   if(hADX!=INVALID_HANDLE)      IndicatorRelease(hADX);
   if(hATRslBuf!=INVALID_HANDLE) IndicatorRelease(hATRslBuf);
   if(hATR1!=INVALID_HANDLE)     IndicatorRelease(hATR1);
   if(hATR2!=INVALID_HANDLE)     IndicatorRelease(hATR2);
   if(hATR3!=INVALID_HANDLE)     IndicatorRelease(hATR3);

   PrintMFESummary();   // [MFE-TEST] dump the "how far do trades run" table
   Notify("🛑 EA stopped (reason " + IntegerToString(reason) + ")");
}

//==================================================================
//  [MFE-TEST] Print the MFE distribution table + save CSV
//==================================================================
void PrintMFESummary()
{
   Print("==================== MFE SUMMARY ====================");
   Print("ราคาวิ่งเข้าทางเราไกลสุดกี่ R ก่อนปิด (จากทั้งหมด ", gMfeTotal, " ไม้)");
   if(gMfeTotal <= 0)
   {
      Print("  (ไม่มีไม้ที่นับได้ - ลองขยายช่วงเวลา backtest)");
      Print("====================================================");
      return;
   }

   for(int k=0; k<ArraySize(gMfeLevels); k++)
   {
      double pct = 100.0 * gMfeCounts[k] / gMfeTotal;
      PrintFormat("  ถึง %.2fR : %d ไม้  (%.1f%%)", gMfeLevels[k], gMfeCounts[k], pct);
   }
   PrintFormat("  เฉลี่ย MFE = %.2f R   |   ดีสุด = %.2f R", gMfeSumR/gMfeTotal, gMfeBestR);
   Print("====================================================");

   // ---- save CSV (MQL5/Files folder) ----
   string fname = "MFE_Summary.csv";
   int fh = FileOpen(fname, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(fh != INVALID_HANDLE)
   {
      FileWrite(fh, "MFE_Level_R", "Trades_Reached", "Percent");
      for(int k=0; k<ArraySize(gMfeLevels); k++)
      {
         double pct = 100.0 * gMfeCounts[k] / gMfeTotal;
         FileWrite(fh, DoubleToString(gMfeLevels[k],2), gMfeCounts[k], DoubleToString(pct,1));
      }
      FileWrite(fh, "TOTAL_TRADES", gMfeTotal, "");
      FileWrite(fh, "AVG_MFE_R", DoubleToString(gMfeSumR/gMfeTotal,2), "");
      FileWrite(fh, "BEST_MFE_R", DoubleToString(gMfeBestR,2), "");
      FileClose(fh);
      Print("[MFE-TEST] saved -> MQL5/Files/", fname);
   }
}

//+------------------------------------------------------------------+
//| Timer: protection + news state                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   CheckDrawdownProtection();
   UpdateNewsState();
}

//+------------------------------------------------------------------+
//| Main tick                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckProfitTarget();     // close all + stop once the profit target is reached
   CheckMaxTotalLoss();     // EMERGENCY BRAKE: close all + stop if total loss limit hit
   CheckPeakDDStop();       // DD LOCK: close all + stop if give-back from peak too large
   SyncPositionState();
   ManageOpenPositions();   // trailing / BE / partial run every tick

   // Entry only on a fresh entry-TF bar
   datetime curBar = (datetime)iTime(_Symbol, InpEntryTF, 0);
   if(curBar == gLastEntryBar)
      return;
   gLastEntryBar = curBar;

   // Re-entry cooldown: after a full close, skip whole entry-TF bars before
   // trading again. Skipping a bar also forces the signal to be RECALCULATED
   // fresh on the next bar instead of blindly re-entering the same spot.
   if(gCooldownBarsLeft > 0)
   {
      gCooldownBarsLeft--;
      return;
   }

   if(!TradingAllowed())
      return;

   TryEnter();
}

//==================================================================
//  Protection: drawdown
//==================================================================
void CheckDrawdownProtection()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity > gPeakEquity)
      gPeakEquity = equity;

   // ----- Max drawdown (global pause / resume) -----
   double ddPct = 0.0;
   if(gPeakEquity > 0.0)
      ddPct = (gPeakEquity - equity) / gPeakEquity * 100.0;

   if(!gMaxDDPaused && ddPct >= InpMaxDD_Percent)
   {
      gMaxDDPaused = true;
      Notify(StringFormat("🚨 MAX DRAWDOWN %.2f%% >= %.2f%% -> EA PAUSED",
                          ddPct, InpMaxDD_Percent));
   }
   else if(gMaxDDPaused && ddPct <= (InpMaxDD_Percent - InpMaxDD_ResumeBuffer))
   {
      gMaxDDPaused = false;
      Notify(StringFormat("✅ Drawdown recovered to %.2f%% -> EA RESUMED", ddPct));
   }

   // ----- Daily drawdown -----
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != gDayStart)
   {
      gDayStart       = today;
      gDayStartEquity = equity;
      if(gDailyStopped)
         Notify("🔄 New trading day -> daily stop reset");
      gDailyStopped   = false;
   }

   if(!gDailyStopped && gDayStartEquity > 0.0)
   {
      double dailyLoss = (gDayStartEquity - equity) / gDayStartEquity * 100.0;
      if(dailyLoss >= InpDailyDD_Percent)
      {
         gDailyStopped = true;
         Notify(StringFormat("🛑 DAILY DRAWDOWN %.2f%% >= %.2f%% -> trading stopped for today",
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
      StringTrimLeft(p);
      StringTrimRight(p);
      if(StringCompare(p, ccy, false) == 0)
         return true;
   }
   return false;
}

// Returns true if a high-impact news event is within the block window.
bool IsNewsBlocking()
{
   if(!InpEnableNewsFilter)
      return false;

   datetime now  = TimeCurrent();
   datetime from = now - (datetime)(InpNewsMinutesAfter  * 60);  // past events still in "after" window
   datetime to   = now + (datetime)(InpNewsMinutesBefore * 60);  // upcoming within "before" window

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to, NULL, NULL);
   if(total <= 0)
      return false;   // calendar unavailable (e.g. tester) -> do not block

   for(int i=0; i<total; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev))
         continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;

      MqlCalendarCountry country;
      string ccy = "";
      if(CalendarCountryById(ev.country_id, country))
         ccy = country.currency;
      if(ccy != "" && !IsWatchedCurrency(ccy))
         continue;

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
      Notify("📰⛔ NEWS filter ON - high-impact event window, trading paused");
   }
   else if(!blocking && gInNews)
   {
      gInNews = false;
      Notify("📰✅ NEWS filter OFF - trading resumed");
   }
}

//==================================================================
//  Profit target: close everything and stop once equity hits target
//==================================================================
void CloseAllMyPositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)  continue;
      trade.PositionClose(t);
   }
}

void CheckProfitTarget()
{
   if(InpProfitTargetPercent <= 0.0) return;   // feature off
   if(gTargetReached)                 return;   // already triggered
   if(gStartBalance <= 0.0)           return;

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double gainPct = (equity - gStartBalance) / gStartBalance * 100.0;
   if(gainPct >= InpProfitTargetPercent)
   {
      gTargetReached = true;
      CloseAllMyPositions();
      Notify(StringFormat("🏆🎉 PROFIT TARGET %.2f%% reached (equity %.2f) -> closed all & trading STOPPED",
                          gainPct, equity));
   }
}

void CheckMaxTotalLoss()
{
   if(InpMaxTotalLossPercent <= 0.0) return;   // feature off
   if(gLossStopReached)              return;   // already triggered
   if(gStartBalance <= 0.0)          return;

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPct = (gStartBalance - equity) / gStartBalance * 100.0;
   if(lossPct >= InpMaxTotalLossPercent)
   {
      gLossStopReached = true;
      CloseAllMyPositions();
      Notify(StringFormat("🚨🛑 EMERGENCY BRAKE: loss %.2f%% (equity %.2f) -> closed all & trading STOPPED",
                          lossPct, equity));
   }
}

void CheckPeakDDStop()
{
   if(InpPeakDDStopPercent <= 0.0) return;   // feature off
   if(gPeakDDStopReached)          return;   // already triggered

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > gPeakEquity) gPeakEquity = equity;   // keep the running peak up to date
   if(gPeakEquity <= 0.0) return;

   double ddPct = (gPeakEquity - equity) / gPeakEquity * 100.0;
   if(ddPct >= InpPeakDDStopPercent)
   {
      gPeakDDStopReached = true;
      CloseAllMyPositions();
      Notify(StringFormat("🔒 DD LOCK: dropped %.2f%% from peak (equity %.2f) -> closed all & trading STOPPED",
                          ddPct, equity));
   }
}

//==================================================================
//  Trading gate
//==================================================================
bool TradingAllowed()
{
   if(gTargetReached) return false;
   if(gLossStopReached) return false;
   if(gPeakDDStopReached) return false;
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
//  Entry logic
//==================================================================
void TryEnter()
{
   // --- Donchian channel over the `period` bars preceding the just-closed bar ---
   int upIdx = iHighest(_Symbol, InpEntryTF, MODE_HIGH, InpDonchianPeriod, 2);
   int loIdx = iLowest (_Symbol, InpEntryTF, MODE_LOW,  InpDonchianPeriod, 2);
   if(upIdx < 0 || loIdx < 0)
      return;

   double upper  = iHigh (_Symbol, InpEntryTF, upIdx);
   double lower  = iLow  (_Symbol, InpEntryTF, loIdx);
   double close1 = iClose(_Symbol, InpEntryTF, 1);

   // --- filters: trend (SMA50) + ADX ---
   double ma, adx;
   if(!BufVal(hMA, 0, 1, ma))  return;
   if(!BufVal(hADX,0, 1, adx)) return;   // buffer 0 = main ADX line
   if(adx < InpADXMin)         return;

   // --- ATR(16) on the entry TF, used by both SL modes ---
   double atrSL;
   if(!BufVal(hATRslBuf, 0, 1, atrSL) || atrSL <= 0.0) return;

   bool buySignal  = (close1 > upper) && (close1 > ma);
   bool sellSignal = (close1 < lower) && (close1 < ma);

   if(buySignal)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl    = ComputeInitialSL(true, entry, lower, atrSL);
      if(sl >= entry) return;                    // sanity: SL must be below entry
      OpenTrade(ORDER_TYPE_BUY, entry, sl);
   }
   else if(sellSignal)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl    = ComputeInitialSL(false, entry, upper, atrSL);
      if(sl <= entry) return;                    // sanity: SL must be above entry
      OpenTrade(ORDER_TYPE_SELL, entry, sl);
   }
}

// Initial stop loss.
//   SL_DONCHIAN : Donchian band -/+ (buffer x ATR)  -> wide channel stop (file 2, profitable)
//   SL_ATR      : entry -/+ (InpSL_ATRMult x ATR)   -> tight, varied (file 1)
double ComputeInitialSL(const bool isBuy, const double entry, const double donchBand, const double atr)
{
   if(InpSLMode == SL_ATR)
   {
      double dist = InpSL_ATRMult * atr;
      return isBuy ? entry - dist : entry + dist;
   }
   double buf = InpSL_DonchBufferMult * atr;   // SL_DONCHIAN
   return isBuy ? donchBand - buf : donchBand + buf;
}

void OpenTrade(const ENUM_ORDER_TYPE type, const double entry, const double sl)
{
   double riskDist = MathAbs(entry - sl);
   if(riskDist <= 0.0)
      return;

   double lots = CalcLotSize(type, entry, sl);
   if(lots <= 0.0)
   {
      Print("Lot size computed as 0 - skipping entry");
      return;
   }

   bool ok = (type==ORDER_TYPE_BUY)
             ? trade.Buy (lots, _Symbol, entry, sl, 0.0, "Donchian-SL")
             : trade.Sell(lots, _Symbol, entry, sl, 0.0, "Donchian-SL");
   if(!ok)
   {
      Print("Order send failed: ", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
      return;
   }
   // notification handled in OnTradeTransaction (DEAL_ENTRY_IN)
}

//==================================================================
//  Lot sizing (risk-based, Cent aware, confidence scaled)
//==================================================================
// Coefficient (K) applied to the risk-based lot size to correct for
// broker-specific contract / tick-value reporting.
//
// With the risk formula used here (riskMoney / lossPerLot, both expressed
// in the account's OWN currency) the math is already self-consistent, so
// standard and most cent accounts use 1.0. Some servers (e.g. certain XM
// cent servers) report tick value differently and need an explicit factor.
// Adjust the K_CENT_XM value below if the lot size looks off on that broker.
// Optional extra multiplier per account profile. Sizing now uses
// OrderCalcProfit() which is already correct on cent accounts, so these
// are all 1.0 by default. Left here only as a manual tuning hook.
double GetLotCoefficient()
{
   switch(InpKParameter)
   {
      case K_STA:     return 1.0;   // standard account
      case K_CENT:    return 1.0;   // typical cent account
      case K_CENT_XM: return 1.0;   // XM-style cent account (fine 0.01 step via EffectiveLotStep)
   }
   return 1.0;
}

double CalcLotSize(const ENUM_ORDER_TYPE type, const double entry, const double sl)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);
   double riskDist  = MathAbs(entry - sl);
   if(riskDist <= 0.0 || riskMoney <= 0.0)
      return 0.0;

   // Loss (in ACCOUNT currency) for 1.0 lot if the SL is hit.
   // OrderCalcProfit() accounts for contract size and cent-account currency
   // automatically, so no broker-specific coefficient is needed and the
   // result is the TRUE 1% risk on any account type.
   double lossPerLot = 0.0;
   if(!OrderCalcProfit(type, _Symbol, 1.0, entry, sl, lossPerLot))
   {
      Print("OrderCalcProfit failed - cannot size lot");
      return 0.0;
   }
   lossPerLot = MathAbs(lossPerLot);
   if(lossPerLot <= 0.0)
      return 0.0;

   double rawLots   = riskMoney / lossPerLot;
   double k         = GetLotCoefficient();                 // 1.0 by default
   double conf      = (InpEnableConfidence ? gConfidence : 1.0);
   double lotsFinal = NormalizeVolume(rawLots * k * conf);

   // Actual money at risk at the final (broker-normalized) lot size.
   double lossAtFinal = lossPerLot * lotsFinal;
   double riskPctReal = (balance > 0.0 ? lossAtFinal / balance * 100.0 : 0.0);

   PrintFormat("SIZING bal=%.2f risk%%=%.2f riskMoney=%.2f | dist=%.2f lossPerLot=%.2f | raw=%.5f K(%s)=%.0f conf=%.2f -> final=%.2f | lossAtFinal=%.2f (=%.2f%% of bal)",
               balance, InpRiskPercent, riskMoney, riskDist, lossPerLot,
               rawLots, EnumToString(InpKParameter), k, conf, lotsFinal,
               lossAtFinal, riskPctReal);

   // Safety: warn if the broker MINIMUM lot already risks above the target.
   if(riskPctReal > InpRiskPercent * 1.5)
      Notify(StringFormat("⚠️ WARNING: min-lot %.2f risks %.2f%% (> target %.2f%%) - account too small for this SL",
                          lotsFinal, riskPctReal, InpRiskPercent));

   // PROP-SAFE HARD CAP: never take a trade that risks more than the cap.
   // Guarantees a single trade can NEVER breach the challenge loss limit.
   if(InpMaxRiskCapPercent > 0.0 && riskPctReal > InpMaxRiskCapPercent)
   {
      Notify(StringFormat("🚫 SKIP trade: min-lot %.2f risks %.2f%% > cap %.2f%% (too risky, not opened)",
                          lotsFinal, riskPctReal, InpMaxRiskCapPercent));
      return 0.0;
   }

   return lotsFinal;
}

// Effective lot rounding step.
//   - manual override (InpLotStepOverride > 0) always wins
//   - K_CENT_XM forces a fine 0.01 step so lots can be 0.11 / 0.12 / 0.13...
//     (XM cent servers have min lot 0.10 but accept 0.01 increments, so the
//      coarse broker-advertised 0.10 step would otherwise lose precision)
//   - otherwise use the broker's reported step
double EffectiveLotStep()
{
   double brokerStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(brokerStep <= 0.0) brokerStep = 0.01;

   if(InpLotStepOverride > 0.0)
      return InpLotStepOverride;

   if(InpKParameter == K_CENT_XM && brokerStep > 0.01)
      return 0.01;

   return brokerStep;
}

double NormalizeVolume(double vol)
{
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = EffectiveLotStep();
   if(step <= 0.0) step = 0.01;

   // round DOWN to the step (epsilon guards against float floor errors)
   vol = MathFloor(vol/step + 1e-9) * step;
   if(vol < minV) vol = minV;
   if(vol > maxV) vol = maxV;

   // round to step decimals
   int digits = (int)MathRound(MathLog10(1.0/step));
   if(digits < 0) digits = 0;
   vol = NormalizeDouble(vol, digits);
   return vol;
}

//==================================================================
//  Per-position state management
//==================================================================
int FindPosStateIndex(const ulong ticket)
{
   for(int i=0; i<ArraySize(gPosTicket); i++)
      if(gPosTicket[i]==ticket)
         return i;
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
   ArrayResize(gPosMaxFav,      n+1);   // [MFE-TEST]
   gPosTicket[n]      = ticket;
   gPosInitRisk[n]    = risk;
   gPosInitVol[n]     = vol;
   gPosBEDone[n]      = false;
   gPosPartialDone[n] = false;
   gPosMaxFav[n]      = 0.0;             // [MFE-TEST]
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
      gPosMaxFav[i]      = gPosMaxFav[i+1];   // [MFE-TEST]
   }
   ArrayResize(gPosTicket,      n-1);
   ArrayResize(gPosInitRisk,    n-1);
   ArrayResize(gPosInitVol,     n-1);
   ArrayResize(gPosBEDone,      n-1);
   ArrayResize(gPosPartialDone, n-1);
   ArrayResize(gPosMaxFav,      n-1);          // [MFE-TEST]
}

// Register new positions and drop closed ones from state.
void SyncPositionState()
{
   // add newly seen positions
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
   // remove states whose positions no longer exist
   for(int i=ArraySize(gPosTicket)-1; i>=0; i--)
      if(!PositionSelectByTicket(gPosTicket[i]))
      {
         RecordMFE(i);          // [MFE-TEST] log how far this trade ran before removal
         RemovePosStateAt(i);
      }
}

//==================================================================
//  [MFE-TEST] Record one closed trade's Maximum Favorable Excursion
//==================================================================
void RecordMFE(const int idx)
{
   double R = gPosInitRisk[idx];
   if(R <= 0.0) return;                 // skip trades with no measurable risk
   double mfeR = gPosMaxFav[idx] / R;   // peak favorable move, in R units

   gMfeTotal++;
   gMfeSumR += mfeR;
   if(mfeR > gMfeBestR) gMfeBestR = mfeR;
   for(int k=0; k<ArraySize(gMfeLevels); k++)
      if(mfeR >= gMfeLevels[k]) gMfeCounts[k]++;
}

//==================================================================
//  Trade management: BE, partial, multi-layer trailing
//==================================================================
void ManageOpenPositions()
{
   for(int i=ArraySize(gPosTicket)-1; i>=0; i--)
   {
      ulong ticket = gPosTicket[i];
      if(!PositionSelectByTicket(ticket))
         continue;

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

      // [MFE-TEST] track the furthest the trade has run in our favor
      if(profitDist > gPosMaxFav[i]) gPosMaxFav[i] = profitDist;

      // ---- Break-even ----
      if(!gPosBEDone[i] && profitDist >= InpBreakEvenR * R)
      {
         double buf  = InpBE_BufferPts * _Point;
         double beSL = isBuy ? open + buf : open - buf;
         if(ModifySL(ticket, isBuy, beSL, sl))
         {
            gPosBEDone[i] = true;
            sl = beSL;
            Notify(StringFormat("🛡️ Break-even set #%I64u @ %.2f", ticket, beSL));
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
               Notify(StringFormat("💰✂️ Partial close %.2f lots #%I64u @ %.2fR",
                                   closeVol, ticket, profitDist/R));
            }
            else
               Notify(StringFormat("❗ Partial FAILED #%I64u: %s",
                                   ticket, trade.ResultRetcodeDescription()));
         }
         else
         {
            // log ให้ชัดว่าทำไมข้าม (lot เล็กเกิน split)
            Notify(StringFormat("↪️ Partial SKIP #%I64u: closeVol %.2f / remain %.2f < min %.2f",
                               ticket, closeVol, vol-closeVol, minV));
            gPosPartialDone[i] = true; // cannot split further, skip
         }
      }

      // ---- Multi-layer trailing ----
      // *** ล็อค trailing ไว้จนกว่าจะถึง 1R (หลัง partial) ***
      // ก่อน 1R: มีแค่ break-even ป้องกันทุน ไม่ให้ trailing ดึง SL ออกก่อน
      // ทำให้ราคามีโอกาสวิ่งไปถึง 1R เพื่อ trigger partial ได้จริง
      bool trailAllowed = (!InpLockTrailUntilPartial) || gPosPartialDone[i];
      if(trailAllowed)
      {
         double newSL = ComputeTrailingSL(isBuy, cur);
         if(newSL > 0.0)
            ModifySL(ticket, isBuy, newSL, sl);
      }
   }
}

// Returns the most protective trailing SL among all layers, or 0 if none valid.
double ComputeTrailingSL(const bool isBuy, const double price)
{
   double candidates[];
   int    c = 0;

   double atr1, atr2, atr3;
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
   if(BufVal(hATR3,0,0,atr3) && atr3>0.0)
   {
      double s = isBuy ? price - atr3*InpTr3_ATRMult : price + atr3*InpTr3_ATRMult;
      ArrayResize(candidates, c+1); candidates[c++] = s;
   }

   // Swing high/low on the trailing TF
   if(isBuy)
   {
      int idx = iLowest(_Symbol, InpTrailTF, MODE_LOW, InpSwingLookback, 1);
      if(idx>=0) { double s=iLow(_Symbol,InpTrailTF,idx); ArrayResize(candidates,c+1); candidates[c++]=s; }
   }
   else
   {
      int idx = iHighest(_Symbol, InpTrailTF, MODE_HIGH, InpSwingLookback, 1);
      if(idx>=0) { double s=iHigh(_Symbol,InpTrailTF,idx); ArrayResize(candidates,c+1); candidates[c++]=s; }
   }

   // High/Low of the 3rd candle back
   if(isBuy)
   {
      double s = iLow(_Symbol, InpTrailTF, InpCandleBackShift);
      if(s>0.0){ ArrayResize(candidates,c+1); candidates[c++]=s; }
   }
   else
   {
      double s = iHigh(_Symbol, InpTrailTF, InpCandleBackShift);
      if(s>0.0){ ArrayResize(candidates,c+1); candidates[c++]=s; }
   }

   if(c==0) return 0.0;

   // Stop selection among the candidate layers:
   //   InpTrailWidest = false -> tightest (most protective, hugs price)
   //   InpTrailWidest = true  -> widest valid (let winners run, fewer early exits)
   // ModifySL still only ever tightens, so the SL never loosens once set.
   double best = 0.0;
   bool   have = false;
   for(int i=0;i<c;i++)
   {
      double s = candidates[i];
      if(isBuy)
      {
         if(s >= price) continue;          // must be below price
         if(!have)                                         { best=s; have=true; }
         else if(InpTrailWidest ? (s < best) : (s > best)) { best=s; }
      }
      else
      {
         if(s <= price) continue;          // must be above price
         if(!have)                                         { best=s; have=true; }
         else if(InpTrailWidest ? (s > best) : (s < best)) { best=s; }
      }
   }
   return have ? best : 0.0;
}

// Modify SL only in the favorable (tightening) direction and within stop level.
bool ModifySL(const ulong ticket, const bool isBuy, double newSL, const double curSL)
{
   if(newSL <= 0.0) return false;

   long   stopsLevel = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * _Point;
   double price      = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // respect broker minimum stop distance
   if(isBuy  && (price - newSL) < minDist) return false;
   if(!isBuy && (newSL - price) < minDist) return false;

   // only tighten (never loosen)
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

//==================================================================
//  Trade transactions: notifications + confidence tracking
//==================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong dealTicket = trans.deal;
   if(!HistoryDealSelect(dealTicket))
      return;
   if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagic)
      return;
   if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
      return;

   long   entry  = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   double price  = HistoryDealGetDouble (dealTicket, DEAL_PRICE);
   double vol    = HistoryDealGetDouble (dealTicket, DEAL_VOLUME);
   double profit = HistoryDealGetDouble (dealTicket, DEAL_PROFIT)
                 + HistoryDealGetDouble (dealTicket, DEAL_SWAP)
                 + HistoryDealGetDouble (dealTicket, DEAL_COMMISSION);
   ulong  posId  = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

   if(entry == DEAL_ENTRY_IN)
   {
      bool   dealIsBuy = (HistoryDealGetInteger(dealTicket, DEAL_TYPE)==DEAL_TYPE_BUY);
      string dir = dealIsBuy ? "🟢 OPEN BUY ⬆️" : "🔴 OPEN SELL ⬇️";
      Notify(StringFormat("%s %.2f lots @ %.2f (conf x%.2f)", dir, vol, price, gConfidence));
   }
   else if(entry == DEAL_ENTRY_OUT)
   {
      string closeTag = (profit >= 0.0) ? "✅ CLOSE 💰" : "❌ CLOSE 📉";
      Notify(StringFormat("%s %.2f lots @ %.2f  P/L %.2f", closeTag, vol, price, profit));
      AccumulateAndMaybeFinalize(posId, profit);
   }
}

// Accumulate realized P/L per position; when the position is fully closed,
// push the total as one trade result for the confidence system.
void AccumulateAndMaybeFinalize(const ulong posId, const double profit)
{
   int idx = -1;
   for(int i=0; i<ArraySize(gAccPos); i++)
      if(gAccPos[i]==posId){ idx=i; break; }

   if(idx < 0)
   {
      int n = ArraySize(gAccPos);
      ArrayResize(gAccPos, n+1);
      ArrayResize(gAccProfit, n+1);
      gAccPos[n]    = posId;
      gAccProfit[n] = profit;
      idx = n;
   }
   else
      gAccProfit[idx] += profit;

   // fully closed if the position no longer exists
   if(!PositionSelectByTicket(posId))
   {
      double total = gAccProfit[idx];
      PushClosedTrade(total);
      gCooldownBarsLeft = InpReentryCooldownBars;   // start re-entry cooldown after a full close
      // remove accumulator entry
      int n = ArraySize(gAccPos);
      for(int j=idx; j<n-1; j++){ gAccPos[j]=gAccPos[j+1]; gAccProfit[j]=gAccProfit[j+1]; }
      ArrayResize(gAccPos, n-1);
      ArrayResize(gAccProfit, n-1);
   }
}

//==================================================================
//  Confidence system
//==================================================================
void PushClosedTrade(const double profit)
{
   int n = ArraySize(gClosedProfit);
   ArrayResize(gClosedProfit, n+1);
   gClosedProfit[n] = profit;

   // keep only the most recent N
   int keep = InpConfidenceTrades;
   if(ArraySize(gClosedProfit) > keep)
   {
      int total = ArraySize(gClosedProfit);
      int drop  = total - keep;
      for(int i=0; i<keep; i++)
         gClosedProfit[i] = gClosedProfit[i+drop];
      ArrayResize(gClosedProfit, keep);
   }

   UpdateConfidence();
}

void UpdateConfidence()
{
   if(!InpEnableConfidence)
   {
      gConfidence = 1.0;
      return;
   }

   int total = ArraySize(gClosedProfit);
   if(total < 3)   // not enough history -> stay neutral (1.0x target)
   {
      gConfidence = gConfidence + InpConfidenceSmooth * (1.0 - gConfidence);
      return;
   }

   int    wins = 0;
   double grossProfit = 0.0, grossLoss = 0.0;
   for(int i=0; i<total; i++)
   {
      double p = gClosedProfit[i];
      if(p > 0){ wins++; grossProfit += p; }
      else     { grossLoss += -p; }
   }

   double winRate = (double)wins / (double)total;            // 0..1
   double pf      = (grossLoss > 0.0) ? grossProfit/grossLoss
                                      : (grossProfit>0.0 ? 3.0 : 1.0);
   double pfScore = MathMin(pf / 2.0, 1.0);                  // PF 2.0 -> full score

   double combined = 0.5*winRate + 0.5*pfScore;             // 0..1
   double target   = InpConfidenceMin +
                     combined * (InpConfidenceMax - InpConfidenceMin);

   // exponential smoothing
   gConfidence = gConfidence + InpConfidenceSmooth * (target - gConfidence);

   if(gConfidence < InpConfidenceMin) gConfidence = InpConfidenceMin;
   if(gConfidence > InpConfidenceMax) gConfidence = InpConfidenceMax;
}
//+------------------------------------------------------------------+
