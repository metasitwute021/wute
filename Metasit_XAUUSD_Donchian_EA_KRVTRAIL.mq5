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
//|  *** v2.05 : BE buffer 200pt -> locks small win (~$6), not $0 ***  |
//|  *** v2.06 : KRV confidence gate (no scale-up on weak streak) ***  |
//|  *** v2.07 : live-ready - Weekend Guard ON, conf OFF, Partial 2R ***|
//|  *** v2.08 : KRV V19 Momentum Candle Filter (close near extreme) ***|
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
#property copyright "Metasit XAUUSD Donchian EA - prop-safe build"
#property version   "2.20k"
#property strict
//+------------------------------------------------------------------+
//|  *** KRV LOSS-CUT TRAIL edition (experiment, separate file) ***  |
//|  Reverse-engineered from KRV V.19: its trailing stop is active   |
//|  from ENTRY (even while the trade is losing), pulling the SL      |
//|  toward the recent structure so a wrong-way trade is cut early    |
//|  (or rescued to breakeven) instead of riding to the full SL.      |
//|  This is why KRV keeps DD low WITHOUT hard-stop brakes.           |
//|    InpTrailFromEntry  = trail from entry (not only in profit)     |
//|    InpLossCutTightest = when underwater, hug price (tightest)     |
//|    InpLossCutATRMult  = keep X*ATR room while losing (KRV-smart)  |
//|  InpTrailFromEntry=false -> behaves exactly like the base EA.     |
//|  Base EA and exam build are untouched.                            |
//+------------------------------------------------------------------+

#define EA_VERSION "2.20"

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
input group "⚙️  GENERAL"
input long     InpMagic              = 20250117;   // 🔑 Magic number (EA id)
input bool     InpEnableNotifications= true;       // 🔔 Push notifications ON/OFF
input string   InpNotifPrefix        = "[XAU-EA] ";// 🏷️ Notification prefix
input bool     InpStatusReport       = true;       // 📊 send a "why no trade" status each entry bar (proves EA is alive)

input group "⏰  TIMEFRAMES"
input ENUM_TIMEFRAMES InpEntryTF      = PERIOD_H4;  // 📈 Entry / signal timeframe
input ENUM_TIMEFRAMES InpTrailTF      = PERIOD_M30; // 🔧 Trailing / manage timeframe

input group "🎯  ENTRY FILTERS"
input int      InpDonchianPeriod     = 20;         // Donchian breakout period
input int      InpMAPeriod           = 50;         // Trend SMA period
input int      InpADXPeriod          = 14;         // ADX period
input double   InpADXMin             = 20.0;       // Min ADX (trend strength)
input bool     InpUseMomentumFilter  = true;       // ✅ Momentum filter: entry candle closes near its extreme
input double   InpMomentumPct        = 30.0;       // ↳ close must be in top/bottom this % of candle

input group "🛑  STOP LOSS"
input ENUM_SL_MODE InpSLMode             = SL_ATR;      // SL method: ATR (tight) / Donchian (wide)
input int          InpSL_ATRPeriod       = 16;     // SL ATR period
input double       InpSL_ATRMult         = 1.5;    // SL = this x ATR (tune 1.2-2.0)
input double       InpSL_DonchBufferMult = 0.75;   // Donchian mode buffer (x ATR)

input group "💰  RISK MANAGEMENT"
input double          InpRiskPercent = 1.0;             // 💵 Risk per trade (% balance)
input ENUM_ACCT_MODE  InpAccountType = ACCOUNT_CENT;    // Account type (Cent / Standard)
input ENUM_ASSET_MODE InpAssetType   = ASSET_2_DECIMAL; // Asset price decimals
input ENUM_K_MODE     InpKParameter  = K_CENT;          // Lot coefficient (K)
input double          InpLotStepOverride = 0.0;         // Force lot step (0 = auto/broker)
input int             InpMaxPositions= 1;               // Max open positions
input int             InpReentryCooldownBars = 1;       // Cooldown bars after close (anti-whipsaw)
input double          InpMaxRiskCapPercent = 1.7;       // 🚧 Skip trade if risk > this % (0 = off; prop guard)

input group "🔧  TRADE MGMT — Break-even / Partial"
input double   InpBreakEvenR         = 0.25;       // BE at this R (used only when BE-ATR is OFF)
input bool     InpUseBE_ATR          = true;       // ✅ BE by ATR distance (KRV V19, volatility-aware)
input double   InpBE_TriggerATR      = 1.0;        // ↳ move to BE once profit >= this x ATR
input double   InpBE_BufferPts       = 200;        // BE buffer (pts) — locks a tiny win, not pure BE
input double   InpPartialR           = 2.0;        // Partial close at this R
input double   InpPartialPercent     = 40.0;       // ↳ close this % of the position
input bool     InpLockTrailUntilPartial = true;    // Lock trailing until partial (let it breathe)
input bool     InpUseFixedTP          = false;     // 🎯 Hard take-profit: close 100% at a fixed R (caps the trade, no manual click)
input double   InpFixedTP_R           = 2.0;       // ↳ close the WHOLE trade at this R (2.0 = +2% when risk is 1%)

input group "📊  STAGED CLOSES (KRV V19)"
input bool     InpUseStagedCloses     = true;      // ✅ Momentum staged exits ON/OFF
input double   InpStagedMinProfitR    = 0.5;       // Act only when profit >= this R
input double   InpStrongMoveATRMult    = 1.6;      // STRONG move = candle range >= this x ATR
input double   InpStrongMoveSLPercent  = 60.0;     // ↳ STRONG: lock this % of profit & keep running
input double   InpMiniMoveATRMult      = 1.0;      // MINI move = candle range >= this x ATR
input double   InpMiniMoveClosePercent = 80.0;     // ↳ MINI: bank this % of remaining volume
input double   InpStagedMomentumPct    = 30.0;     // Candle close in top/bottom % (true momentum)

input group "📉  TRAILING LAYERS (M30)"
input int      InpTr1_ATRPeriod      = 18;         // Layer 1 ATR period
input double   InpTr1_ATRMult        = 5.75;       // Layer 1 ATR mult (widest)
input int      InpTr2_ATRPeriod      = 12;         // Layer 2 ATR period
input double   InpTr2_ATRMult        = 2.75;       // Layer 2 ATR mult
input int      InpTr3_ATRPeriod      = 16;         // Layer 3 ATR period
input double   InpTr3_ATRMult        = 2.0;        // Layer 3 ATR mult
input int      InpSwingLookback      = 20;         // Swing high/low lookback (bars)
input int      InpCandleBackShift    = 3;          // "3rd candle" shift
input bool     InpTrailWidest        = true;       // true = WIDEST (let winners run, higher PF)

input group "🔬  KRV LOSS-CUT TRAIL (experiment)"
input bool     InpTrailFromEntry     = true;       // 🧪 ON = trail from ENTRY (even when losing) — cut losses early like KRV
input bool     InpLossCutTightest    = true;       // ↳ when underwater, hug price (tightest) to cut the loss hard
input double   InpLossCutATRMult     = 0.0;        // ↳ 0=hug tightest (aggressive). >0 = keep this ×ATR room while losing (KRV-smart, fewer whipsaws)

input group "🏃  LET WINNERS RUN (experiment)"
input bool     InpLetWinnersRun      = false;      // 🧪 ON = skip partial + mini-bank, widen trail (KRV-style runners: lower win%, higher R:R)
input double   InpRunTrailWiden      = 1.5;        // ↳ widen trailing ATR multipliers by this factor while running

input group "🛡️  DRAWDOWN PROTECTION (PROP)"
input double   InpMaxDD_Percent      = 3.0;        // Max DD -> pause EA (%)
input double   InpMaxDD_ResumeBuffer = 2.0;        // Resume when DD < (Max - this)
input double   InpDailyDD_Percent    = 1.5;        // Daily DD -> stop for the day (%)
input double   InpProfitTargetPercent = 6.0;       // 🎯 +this % profit -> close all + STOP (0 = off)
input double   InpMaxTotalLossPercent = 3.5;       // 🚨 EMERGENCY BRAKE: -this % -> close all + STOP (0 = off)
input double   InpPeakDDStopPercent  = 0.0;        // DD LOCK from peak equity (0 = off)

input group "📅  WEEKEND GUARD"
input bool     InpNoWeekendHold      = true;       // ✅ Close + block before weekend (avoid Mon gap)
input int      InpWeekendCloseHour   = 20;         // ↳ Friday server hour to close (0-23)

input group "📰  NEWS FILTER"
input bool     InpEnableNewsFilter   = true;       // ✅ Live calendar filter (MT5 economic calendar; LIVE only, empty in tester)
input int      InpNewsMinutesBefore  = 90;         // Block minutes BEFORE news
input int      InpNewsMinutesAfter   = 30;         // Block minutes AFTER news
input string   InpNewsCurrencies     = "USD";      // Currencies to watch (comma sep.)
input bool     InpUseFFNews          = false;      // ✅ Forex Factory CSV file (WORKS IN STRATEGY TESTER, like KRV)
input string   InpFFNewsFile         = "ff_news.csv"; // ↳ file in COMMON\Files (works in tester!) — cols: Date,Time,Currency,Impact
input string   InpFFBlockImpact      = "High";     // ↳ impacts to block (comma sep: High  or  High,Medium)
input int      InpFFTimeOffsetHours  = 0;          // ↳ shift CSV times to broker SERVER time (+/- hours)
input bool     InpFFCloseBeforeNews  = false;      // ↳ also CLOSE open positions when a news window starts

input group "🎲  CONFIDENCE SYSTEM (keep OFF)"
input bool     InpEnableConfidence   = false;      // ⚠️ Scale lot by recent form (OFF = proven better)
input int      InpConfidenceTrades   = 10;         // Recent trades to assess
input double   InpConfidenceMin      = 0.5;        // Min lot multiplier
input double   InpConfidenceMax      = 2.0;        // Max lot multiplier
input double   InpConfidenceSmooth   = 0.25;       // Smoothing (EMA alpha)
input double   InpConfMinWinRate     = 0.45;       // Gate: scale up only if win rate >= this
input double   InpConfMinPF          = 1.2;        // Gate: scale up only if PF >= this

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
datetime gWeekendClosedDay = 0;   // which Friday we already flat-closed (weekend guard), avoid repeat
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
bool     gPosMiniDone[];     // staged close: mini-move bank already taken for this position
datetime gPosStagedBar[];    // staged close: last trail-TF bar already evaluated (act once per closed candle)

// drawdown / protection state
double   gPeakEquity     = 0.0;
bool     gMaxDDPaused    = false;
datetime gDayStart       = 0;
double   gDayStartEquity = 0.0;
bool     gDailyStopped   = false;

// news state
bool     gInNews         = false;

// Forex Factory news (loaded from CSV file; works in Strategy Tester)
datetime gFFTime[];      // event time (server time, sorted ascending)
string   gFFCcy[];       // event currency
string   gFFImp[];       // event impact text
int      gFFCount        = 0;
int      gFFIdx          = 0;   // moving pointer: skips events already past (tester time only moves forward)

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

   LoadFFNews();      // load Forex Factory CSV (works in tester) if enabled

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

   string mode = InpLetWinnersRun ? "🏃 LET-RUN mode" : "💰 BANK-EARLY mode";
   Notify("🚀 EA v" + EA_VERSION + " [" + mode + "] started on " + _Symbol + " (entry " + EnumToString(InpEntryTF) +
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

   Notify("🛑 EA stopped (reason " + IntegerToString(reason) + ")");
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
   CheckWeekendClose();     // WEEKEND GUARD: flat all before the weekend (avoid Mon gap)
   SyncPositionState();
   ManageOpenPositions();   // trailing / BE / partial run every tick

   // Entry only on a fresh entry-TF bar
   datetime curBar = (datetime)iTime(_Symbol, InpEntryTF, 0);
   if(curBar == gLastEntryBar)
      return;
   gLastEntryBar = curBar;

   SendSignalStatus();   // report entry-condition state each bar (proves EA is alive)

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

// True if 'val' is in a comma-separated list (case-insensitive).
bool InListCSV(const string list, const string val)
{
   string parts[];
   int n = StringSplit(list, ',', parts);
   for(int i=0; i<n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p); StringTrimRight(p);
      if(StringCompare(p, val, false) == 0)
         return true;
   }
   return false;
}

// Parse a FF row's date + time into server time. Date "yyyy.mm.dd", time "HH:MM" (24h).
datetime ParseFFDateTime(string dateStr, string timeStr)
{
   StringTrimLeft(dateStr); StringTrimRight(dateStr);
   StringTrimLeft(timeStr); StringTrimRight(timeStr);
   if(StringLen(dateStr) < 8) return 0;
   if(StringLen(timeStr) < 4) timeStr = "00:00";   // all-day / tentative -> midnight
   datetime t = StringToTime(dateStr + " " + timeStr);
   if(t <= 0) return 0;
   return t + (datetime)(InpFFTimeOffsetHours * 3600);
}

// Insertion-sort the parallel FF arrays by time ascending (run once after load).
void SortFFNews()
{
   for(int i=1; i<gFFCount; i++)
   {
      datetime kt = gFFTime[i]; string kc = gFFCcy[i]; string ki = gFFImp[i];
      int j = i-1;
      while(j>=0 && gFFTime[j] > kt)
      {
         gFFTime[j+1]=gFFTime[j]; gFFCcy[j+1]=gFFCcy[j]; gFFImp[j+1]=gFFImp[j];
         j--;
      }
      gFFTime[j+1]=kt; gFFCcy[j+1]=kc; gFFImp[j+1]=ki;
   }
}

// Load the Forex Factory CSV from MQL5/Files. Columns: Date,Time,Currency,Impact[,Title...]
void LoadFFNews()
{
   gFFCount = 0; gFFIdx = 0;
   ArrayResize(gFFTime,0); ArrayResize(gFFCcy,0); ArrayResize(gFFImp,0);
   if(!InpUseFFNews) return;

   // FILE_COMMON: read from the shared Common\Files folder so the Strategy
   // Tester (which has its own sandbox) can see the same file as live.
   int fh = FileOpen(InpFFNewsFile, FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
   {
      Notify("📰❗ FF file NOT found: " + InpFFNewsFile + " (put it in COMMON\\Files). FF filter OFF.");
      return;
   }

   while(!FileIsEnding(fh))
   {
      string c1 = FileReadString(fh);   // Date
      // blank trailing line
      if(c1=="" && FileIsLineEnding(fh)) continue;
      string c2 = FileReadString(fh);   // Time
      string c3 = FileReadString(fh);   // Currency
      string c4 = FileReadString(fh);   // Impact
      // consume any extra columns (e.g. Title) up to end of line
      while(!FileIsLineEnding(fh) && !FileIsEnding(fh)) FileReadString(fh);

      datetime t = ParseFFDateTime(c1, c2);
      if(t <= 0) continue;              // header row or unparseable -> skip
      StringTrimLeft(c3); StringTrimRight(c3);
      StringTrimLeft(c4); StringTrimRight(c4);

      int n = gFFCount;
      ArrayResize(gFFTime, n+1); ArrayResize(gFFCcy, n+1); ArrayResize(gFFImp, n+1);
      gFFTime[n]=t; gFFCcy[n]=c3; gFFImp[n]=c4;
      gFFCount = n+1;
   }
   FileClose(fh);

   SortFFNews();
   Notify(StringFormat("📰✅ Forex Factory news loaded: %d events from %s", gFFCount, InpFFNewsFile));
}

// True if a watched, high-impact FF event is inside the block window now.
bool IsFFNewsBlocking()
{
   if(!InpUseFFNews || gFFCount == 0) return false;
   datetime now    = TimeCurrent();
   datetime before = (datetime)(InpNewsMinutesBefore * 60);
   datetime after  = (datetime)(InpNewsMinutesAfter  * 60);

   // advance pointer past events whose "after" window has fully passed
   while(gFFIdx < gFFCount && (gFFTime[gFFIdx] + after) < now)
      gFFIdx++;

   for(int j=gFFIdx; j<gFFCount; j++)
   {
      datetime t = gFFTime[j];
      if((t - before) > now) break;     // sorted: no nearer events ahead
      if(IsWatchedCurrency(gFFCcy[j]) && InListCSV(InpFFBlockImpact, gFFImp[j]))
         return true;
   }
   return false;
}

// Returns true if a high-impact news event is within the block window
// (Forex Factory file first — works in tester — then the live MT5 calendar).
bool IsNewsBlocking()
{
   if(IsFFNewsBlocking())
      return true;
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
      if(InpFFCloseBeforeNews && PositionsTotal() > 0)
      {
         CloseAllMyPositions();
         Notify("📰✂️ Closed open positions ahead of the news window");
      }
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

//==================================================================
//  Weekend guard: flat all + block new entries on Friday from
//  InpWeekendCloseHour onward (avoids Monday-open gap risk, e.g.
//  "Trump weekend" geopolitical headlines). Off via InpNoWeekendHold.
//==================================================================
bool IsWeekendBlockTime()
{
   if(!InpNoWeekendHold) return false;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   // day_of_week: 0=Sun .. 5=Fri .. 6=Sat ; market closed Sat/Sun anyway
   return (dt.day_of_week == 5 && dt.hour >= InpWeekendCloseHour);
}

void CheckWeekendClose()
{
   if(!InpNoWeekendHold)     return;
   if(!IsWeekendBlockTime()) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime todayKey = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(gWeekendClosedDay == todayKey) return;   // already flattened this Friday

   if(CountMyPositions() > 0)
   {
      CloseAllMyPositions();
      Notify(StringFormat("🌅 WEEKEND GUARD: closed all before weekend (Fri %02d:00 server) - avoid Mon gap", dt.hour));
   }
   gWeekendClosedDay = todayKey;
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
   if(IsWeekendBlockTime()) return false;   // WEEKEND GUARD: no new entries Friday-late
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
//  Signal status report — tells you WHY there is no trade yet, and
//  how close each entry condition is (proves the EA is alive & working).
//  Runs once per entry-TF bar while FLAT (no spam while a trade runs).
//==================================================================
void SendSignalStatus()
{
   if(!InpStatusReport)          return;
   if(CountMyPositions() > 0)     return;   // trade running -> user already gets trade alerts

   int upIdx = iHighest(_Symbol, InpEntryTF, MODE_HIGH, InpDonchianPeriod, 2);
   int loIdx = iLowest (_Symbol, InpEntryTF, MODE_LOW,  InpDonchianPeriod, 2);
   if(upIdx < 0 || loIdx < 0)     return;
   double upper  = iHigh (_Symbol, InpEntryTF, upIdx);
   double lower  = iLow  (_Symbol, InpEntryTF, loIdx);
   double close1 = iClose(_Symbol, InpEntryTF, 1);
   double ma=0, adx=0;
   BufVal(hMA, 0, 1, ma);
   BufVal(hADX,0, 1, adx);

   bool   trendUp = (close1 > ma);            // which side the SMA allows
   string side    = trendUp ? "BUY" : "SELL";
   bool   adxOK   = (adx >= InpADXMin);
   // distance to the breakout on the SMA-aligned side
   bool   breakoutOK = trendUp ? (close1 > upper) : (close1 < lower);
   double target     = trendUp ? upper : lower;
   double distPts    = MathAbs(target - close1) / _Point;

   // is the path open? (news / weekend / cooldown / max positions)
   string block = "";
   if(gCooldownBarsLeft > 0)                        block += "cooldown ";
   if(IsWeekendBlockTime())                         block += "weekend ";
   if(gInNews)                                      block += "news ";
   if(CountMyPositions() >= InpMaxPositions)        block += "maxpos ";
   bool pathOpen = (block == "");

   int met = (adxOK?1:0) + (breakoutOK?1:0) + (pathOpen?1:0);   // out of 3 gates

   string txt = StringFormat(
      "📊 EA ยังไม่เข้าไม้ (ผ่าน %d/3)\n"
      "%s ADX %.1f / %.0f\n"
      "%s Breakout(%s): %s\n"
      "%s ทางเปิด: %s",
      met,
      adxOK?"✅":"❌", adx, InpADXMin,
      breakoutOK?"✅":"⏳", side,
      breakoutOK ? "ทะลุแล้ว!" :
                   StringFormat("รอราคา %s %.2f (ห่าง %.0f จุด)", trendUp?">":"<", target, distPts),
      pathOpen?"✅":"⛔", pathOpen ? "ว่าง" : block);
   Notify(txt);
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

   // --- Momentum candle filter (KRV V19) ---
   // The breakout candle must close near its extreme, proving conviction:
   //   Long  : close in the TOP    InpMomentumPct% of the candle range
   //   Short : close in the BOTTOM InpMomentumPct% of the candle range
   // Filters out weak/indecisive breakouts that spike then close mid-range.
   if(InpUseMomentumFilter)
   {
      double h1 = iHigh(_Symbol, InpEntryTF, 1);
      double l1 = iLow (_Symbol, InpEntryTF, 1);
      double rng = h1 - l1;
      if(rng > 0.0)
      {
         double pos = (close1 - l1) / rng;          // 0 = at low, 1 = at high
         double thr = InpMomentumPct / 100.0;       // e.g. 0.30
         if(buySignal  && pos < (1.0 - thr)) buySignal  = false;  // not in top X%
         if(sellSignal && pos > thr)         sellSignal = false;  // not in bottom X%
      }
   }

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

   // Optional hard take-profit: close the whole trade at a fixed R (broker-side,
   // works even if the EA is offline). 0 = off -> let the trail/staged exits run.
   double tp = 0.0;
   if(InpUseFixedTP && InpFixedTP_R > 0.0)
      tp = (type==ORDER_TYPE_BUY) ? entry + InpFixedTP_R*riskDist
                                  : entry - InpFixedTP_R*riskDist;

   bool ok = (type==ORDER_TYPE_BUY)
             ? trade.Buy (lots, _Symbol, entry, sl, tp, "Donchian-SL")
             : trade.Sell(lots, _Symbol, entry, sl, tp, "Donchian-SL");
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
   ArrayResize(gPosMiniDone,    n+1);
   ArrayResize(gPosStagedBar,   n+1);
   gPosTicket[n]      = ticket;
   gPosInitRisk[n]    = risk;
   gPosInitVol[n]     = vol;
   gPosBEDone[n]      = false;
   gPosPartialDone[n] = false;
   gPosMiniDone[n]    = false;
   gPosStagedBar[n]   = 0;
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
      gPosMiniDone[i]    = gPosMiniDone[i+1];
      gPosStagedBar[i]   = gPosStagedBar[i+1];
   }
   ArrayResize(gPosTicket,      n-1);
   ArrayResize(gPosInitRisk,    n-1);
   ArrayResize(gPosInitVol,     n-1);
   ArrayResize(gPosBEDone,      n-1);
   ArrayResize(gPosPartialDone, n-1);
   ArrayResize(gPosMiniDone,    n-1);
   ArrayResize(gPosStagedBar,   n-1);
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
         RemovePosStateAt(i);
}

// Builds a "% of balance" tag for an SL-move notification, measured fresh
// per trade (this position only): current floating profit (handy if you want
// to close manually), and what would be LOCKED if the SL is hit.
string SLPercentTag(const long posType, const double openP, const double curP, const double slP)
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal <= 0.0) return "";
   double vol = PositionGetDouble(POSITION_VOLUME);          // current (post-partial) size
   ENUM_ORDER_TYPE ot = (posType==POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double pNow = 0.0, pSL = 0.0;
   OrderCalcProfit(ot, _Symbol, vol, openP, curP, pNow);     // profit if closed now (floating)
   OrderCalcProfit(ot, _Symbol, vol, openP, slP,  pSL);      // profit if SL is hit
   return StringFormat("  💹 now %+.2f%% | @SL %+.2f%%", pNow/bal*100.0, pSL/bal*100.0);
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

      // ---- Break-even ----
      // BE trigger: ATR-based (KRV V19, adapts to volatility) or R-based (fallback)
      double beTrigger = InpBreakEvenR * R;
      if(InpUseBE_ATR)
      {
         double atrBE;
         if(BufVal(hATRslBuf, 0, 1, atrBE) && atrBE > 0.0)
            beTrigger = InpBE_TriggerATR * atrBE;
      }
      if(!gPosBEDone[i] && profitDist >= beTrigger)
      {
         double buf  = InpBE_BufferPts * _Point;
         double beSL = isBuy ? open + buf : open - buf;
         if(ModifySL(ticket, isBuy, beSL, sl))
         {
            gPosBEDone[i] = true;
            sl = beSL;
            Notify(StringFormat("🛡️ Break-even set #%I64u @ %.2f", ticket, beSL)
                   + SLPercentTag(type, open, cur, beSL));
         }
      }

      // ---- Partial close ----  (skipped in let-winners-run mode: let the whole position ride)
      if(!InpLetWinnersRun && !gPosPartialDone[i] && profitDist >= InpPartialR * R)
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

      // ---- Staged closes (KRV V19): momentum-candle exits ----
      // ปัญหาเดิม: ราคาวิ่งไปไกล (avg MFE ~0.93R) แต่เราเก็บได้แค่ ~0.18R (คืนกำไรเยอะ)
      // วิธีแก้: ดูแท่งบน trail TF (M30) ที่ "โมเมนตัมแรง" ในทางเรา
      //   STRONG move (แท่งใหญ่มาก) = มีแรงไปต่อ -> ไม่ปิด แค่ดึง SL ล็อกกำไร 60% แล้วปล่อยวิ่ง
      //   MINI move   (แท่งแรงปานกลาง) = น่าจะหมดแรง/spike -> เก็บกำไร 80% ของไม้ที่เหลือ
      if(InpUseStagedCloses && profitDist >= InpStagedMinProfitR * R)
      {
         datetime barT = iTime(_Symbol, InpTrailTF, 1);   // last CLOSED trail-TF candle
         if(barT > 0 && barT != gPosStagedBar[i])
         {
            gPosStagedBar[i] = barT;                       // evaluate this candle once

            double h1 = iHigh(_Symbol, InpTrailTF, 1);
            double l1 = iLow (_Symbol, InpTrailTF, 1);
            double c1 = iClose(_Symbol, InpTrailTF, 1);
            double rng = h1 - l1;
            double atrT;
            bool   haveATR = BufVal(hATR1, 0, 0, atrT) && atrT > 0.0;

            if(rng > 0.0 && haveATR)
            {
               // momentum body: close near the extreme in OUR direction
               double thr     = InpStagedMomentumPct / 100.0;
               double posInRng = (c1 - l1) / rng;          // 0 = at low, 1 = at high
               bool   momOK   = isBuy ? (posInRng >= (1.0 - thr)) : (posInRng <= thr);
               // candle must also be in our favour (green for buy / red for sell)
               bool   dirOK   = isBuy ? (c1 > iOpen(_Symbol,InpTrailTF,1))
                                      : (c1 < iOpen(_Symbol,InpTrailTF,1));
               double ratio   = rng / atrT;

               if(momOK && dirOK)
               {
                  if(ratio >= InpStrongMoveATRMult)
                  {
                     // STRONG: lock InpStrongMoveSLPercent of current profit, keep running
                     double lockDist = profitDist * (InpStrongMoveSLPercent/100.0);
                     double lockSL   = isBuy ? open + lockDist : open - lockDist;
                     if(ModifySL(ticket, isBuy, lockSL, sl))
                     {
                        sl = lockSL;
                        Notify(StringFormat("🚀🔒 Strong move #%I64u: SL locks %.0f%% of %.2fR profit",
                                            ticket, InpStrongMoveSLPercent, profitDist/R)
                               + SLPercentTag(type, open, cur, lockSL));
                     }
                  }
                  else if(!InpLetWinnersRun && ratio >= InpMiniMoveATRMult && !gPosMiniDone[i])
                  {
                     // MINI: bank InpMiniMoveClosePercent of the REMAINING volume
                     //       (skipped in let-winners-run mode — this is the biggest cap on runners)
                     double curVol  = PositionGetDouble(POSITION_VOLUME);
                     double closeVol= NormalizeVolume(curVol * (InpMiniMoveClosePercent/100.0));
                     double minV    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
                     if(closeVol >= minV && (curVol - closeVol) >= minV)
                     {
                        if(trade.PositionClosePartial(ticket, closeVol))
                        {
                           gPosMiniDone[i] = true;
                           Notify(StringFormat("⚡💰 Mini move bank %.2f lots #%I64u @ %.2fR",
                                               closeVol, ticket, profitDist/R));
                        }
                     }
                     else
                        gPosMiniDone[i] = true;   // too small to split, skip future mini banks
                  }
               }
            }
         }
      }

      // ---- Multi-layer trailing ----
      // *** ล็อค trailing ไว้จนกว่าจะถึง 1R (หลัง partial) ***
      // ก่อน 1R: มีแค่ break-even ป้องกันทุน ไม่ให้ trailing ดึง SL ออกก่อน
      // ทำให้ราคามีโอกาสวิ่งไปถึง 1R เพื่อ trigger partial ได้จริง
      // In let-winners-run mode there is no partial, so let the trade breathe until it
      // reaches the partial level, then trail (wide). Otherwise use the lock-until-partial rule.
      bool trailAllowed;
      if(InpTrailFromEntry)
         trailAllowed = true;                       // 🔬 KRV-style: trail from entry, even when losing
      else if(InpLetWinnersRun)
         trailAllowed = (profitDist >= InpPartialR * R);
      else
         trailAllowed = (!InpLockTrailUntilPartial) || gPosPartialDone[i];
      if(trailAllowed)
      {
         // Underwater (profitDist <= 0) -> cut the loss early like KRV.
         // In profit -> use the normal widest/tightest setting (let winners run).
         bool useWidest = InpTrailWidest;
         if(InpTrailFromEntry && InpLossCutTightest && profitDist <= 0.0)
            useWidest = false;
         double newSL = ComputeTrailingSL(isBuy, cur, useWidest);

         // 🔬 KRV-smart loss-cut: instead of hugging price (whipsaw death), keep a
         // fixed ATR "grace room" while underwater. Only cuts trades that move hard
         // against us (real losers), lets normal pullbacks breathe -> higher win rate.
         if(InpTrailFromEntry && profitDist <= 0.0 && InpLossCutATRMult > 0.0)
         {
            double atrLC;
            if(BufVal(hATRslBuf, 0, 1, atrLC) && atrLC > 0.0)
            {
               double room   = atrLC * InpLossCutATRMult;
               double floorSL = isBuy ? cur - room : cur + room;
               // never let the loss-cut SL sit TIGHTER than the grace floor
               if(newSL <= 0.0)
                  newSL = floorSL;
               else if(isBuy)
                  newSL = MathMin(newSL, floorSL);   // farther from price = lower SL for a buy
               else
                  newSL = MathMax(newSL, floorSL);   // farther from price = higher SL for a sell
            }
         }
         if(newSL > 0.0 && ModifySL(ticket, isBuy, newSL, sl))
         {
            string arrow = isBuy ? "⬆️" : "⬇️";
            Notify(StringFormat("📈🔧 Trailing SL #%I64u %s %.2f → %.2f", ticket, arrow, sl, newSL)
                   + SLPercentTag(type, open, cur, newSL));
            sl = newSL;
         }
      }
   }
}

// Returns the most protective trailing SL among all layers, or 0 if none valid.
double ComputeTrailingSL(const bool isBuy, const double price, const bool useWidest)
{
   double candidates[];
   int    c = 0;

   // Let-winners-run widens the ATR layers so the trail rides bigger trends (fewer early exits).
   double w = InpLetWinnersRun ? InpRunTrailWiden : 1.0;

   double atr1, atr2, atr3;
   if(BufVal(hATR1,0,0,atr1) && atr1>0.0)
   {
      double m = atr1*InpTr1_ATRMult*w;
      double s = isBuy ? price - m : price + m;
      ArrayResize(candidates, c+1); candidates[c++] = s;
   }
   if(BufVal(hATR2,0,0,atr2) && atr2>0.0)
   {
      double m = atr2*InpTr2_ATRMult*w;
      double s = isBuy ? price - m : price + m;
      ArrayResize(candidates, c+1); candidates[c++] = s;
   }
   if(BufVal(hATR3,0,0,atr3) && atr3>0.0)
   {
      double m = atr3*InpTr3_ATRMult*w;
      double s = isBuy ? price - m : price + m;
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
         if(!have)                                     { best=s; have=true; }
         else if(useWidest ? (s < best) : (s > best))  { best=s; }
      }
      else
      {
         if(s <= price) continue;          // must be above price
         if(!have)                                     { best=s; have=true; }
         else if(useWidest ? (s > best) : (s < best))  { best=s; }
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
      double slPx = 0.0;
      if(PositionSelectByTicket(posId)) slPx = PositionGetDouble(POSITION_SL);
      // risk of THIS trade as % of balance (what you lose if the SL is hit)
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskM = 0.0;
      if(slPx > 0.0)
         OrderCalcProfit(dealIsBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL, _Symbol, vol, price, slPx, riskM);
      double riskPct = (bal > 0.0) ? riskM/bal*100.0 : 0.0;
      Notify(StringFormat("%s %.2f lots @ %.2f  🛑 SL @ %.2f  (💹 @SL %+.2f%%)",
                          dir, vol, price, slPx, riskPct));
   }
   else if(entry == DEAL_ENTRY_OUT)
   {
      string closeTag = (profit >= 0.0) ? "✅ CLOSE 💰" : "❌ CLOSE 📉";
      // result of THIS trade as % of balance
      double balC = AccountInfoDouble(ACCOUNT_BALANCE);
      double pl   = (balC > 0.0) ? profit/balC*100.0 : 0.0;
      Notify(StringFormat("%s %.2f lots @ %.2f  P/L %.2f (💹 %+.2f%%)",
                          closeTag, vol, price, profit, pl));
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

   // *** KRV-style gate ***
   // Only allow the lot to scale ABOVE neutral (1.0x) when the recent record
   // is genuinely good (win rate AND profit factor above the thresholds).
   // Otherwise cap the target at 1.0 so a weak/losing streak can NEVER lever
   // the lot up into bigger losses (this was the flaw that turned the 6.5y
   // backtest negative). Set either threshold to 0 to disable the gate.
   bool gatePass = (winRate >= InpConfMinWinRate && pf >= InpConfMinPF);
   if(!gatePass)
      target = MathMin(target, 1.0);

   // exponential smoothing
   gConfidence = gConfidence + InpConfidenceSmooth * (target - gConfidence);

   if(gConfidence < InpConfidenceMin) gConfidence = InpConfidenceMin;
   if(gConfidence > InpConfidenceMax) gConfidence = InpConfidenceMax;
}
//+------------------------------------------------------------------+
