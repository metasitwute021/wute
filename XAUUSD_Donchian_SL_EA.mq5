//+------------------------------------------------------------------+
//|                                    XAUUSD_Donchian_SL_EA.mq5      |
//|        Donchian breakout trend EA for XAUUSD (Gold)              |
//|        *** Stop Loss is derived from the Donchian band ***        |
//|                                                                  |
//|  Strategy summary                                                |
//|  - Market / TF : XAUUSD, signals on H4, trailing managed on M30  |
//|  - Entry       : Donchian(20) breakout, filtered by SMA(50)      |
//|                  trend direction and ADX(14) > 20                |
//|  - Stop Loss   : from the Donchian band (NOT from ATR):          |
//|                    Buy  SL = Donchian low  - 0.75 * ATR(16)       |
//|                    Sell SL = Donchian high + 0.75 * ATR(16)       |
//|  - Sizing      : risk 1% of balance vs. SL distance (Cent OK)    |
//|  - Exit        : no fixed TP, SL only, let profit run via        |
//|                  multi-layer trailing                            |
//|  - Management  : break-even @0.25R, partial 40% @1R, multi       |
//|                  trailing layers (pick the safest stop)          |
//|  - Protection  : max DD 20% pause/resume, daily DD 1.5% stop,    |
//|                  high-impact news filter +/-90 min               |
//|  - Confidence  : 0.5x..2.0x lot scaling on last 10 trades        |
//|                  (win rate + profit factor) with 0.25 smoothing  |
//|  - Alerts      : push notifications on every event               |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Donchian EA (Donchian-based SL)"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>

//==================================================================
//  Inputs
//==================================================================
input group "=== General ==="
input long     InpMagic              = 20250117;   // Magic number
input bool     InpCentAccount        = true;       // Account is a Cent account
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

input group "=== Stop Loss (Donchian based) ==="
input int      InpSL_BufferATRPeriod = 16;         // ATR period for SL buffer (entry TF)
input double   InpSL_BufferATRMult   = 0.75;       // SL buffer = ATR x mult

input group "=== Risk / sizing ==="
input double   InpRiskPercent        = 1.0;        // Risk per trade (% balance)
input int      InpMaxPositions       = 1;          // Max simultaneous positions

input group "=== Trade management ==="
input double   InpBreakEvenR         = 0.25;       // Move SL to BE at this R
input double   InpBE_BufferPts       = 20;         // BE buffer (points beyond entry)
input double   InpPartialR           = 1.0;        // Partial close at this R
input double   InpPartialPercent     = 40.0;       // Percent of position to close

input group "=== Trailing layers (M30) ==="
input int      InpTr1_ATRPeriod      = 18;         // Layer 1 ATR period
input double   InpTr1_ATRMult        = 5.75;       // Layer 1 ATR multiplier
input int      InpTr2_ATRPeriod      = 12;         // Strong move ATR period
input double   InpTr2_ATRMult        = 2.75;       // Strong move ATR multiplier
input int      InpTr3_ATRPeriod      = 16;         // Mini strong move ATR period
input double   InpTr3_ATRMult        = 2.0;        // Mini strong move ATR multiplier
input int      InpSwingLookback      = 20;         // Swing high/low lookback (M30 bars)
input int      InpCandleBackShift    = 3;          // "3rd candle" shift for trailing

input group "=== Drawdown protection ==="
input double   InpMaxDD_Percent      = 20.0;       // Max drawdown -> pause EA (%)
input double   InpMaxDD_ResumeBuffer = 2.0;        // Resume when DD below (Max - buffer)
input double   InpDailyDD_Percent    = 1.5;        // Daily drawdown -> stop for day (%)

input group "=== News filter ==="
input bool     InpEnableNewsFilter   = true;       // Avoid trading around news
input int      InpNewsMinutesBefore  = 90;         // Block window before news (min)
input int      InpNewsMinutesAfter   = 90;         // Block window after news (min)
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

// per-position state (parallel arrays keyed by ticket)
ulong    gPosTicket[];
double   gPosInitRisk[];   // price distance of initial risk (R), per position
double   gPosInitVol[];    // original volume
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
   hATRslBuf = iATR(_Symbol, InpEntryTF, InpSL_BufferATRPeriod);
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

   EventSetTimer(5);  // protection / news checks every 5 sec

   Notify("EA started on " + _Symbol + " (entry " + EnumToString(InpEntryTF) +
          ", trail " + EnumToString(InpTrailTF) + ", Donchian-SL)");
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

   Notify("EA stopped (reason " + IntegerToString(reason) + ")");
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
   SyncPositionState();
   ManageOpenPositions();   // trailing / BE / partial run every tick

   // Entry only on a fresh entry-TF bar
   datetime curBar = (datetime)iTime(_Symbol, InpEntryTF, 0);
   if(curBar == gLastEntryBar)
      return;
   gLastEntryBar = curBar;

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
      Notify(StringFormat("MAX DRAWDOWN %.2f%% >= %.2f%% -> EA PAUSED",
                          ddPct, InpMaxDD_Percent));
   }
   else if(gMaxDDPaused && ddPct <= (InpMaxDD_Percent - InpMaxDD_ResumeBuffer))
   {
      gMaxDDPaused = false;
      Notify(StringFormat("Drawdown recovered to %.2f%% -> EA RESUMED", ddPct));
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
         Notify("New trading day -> daily stop reset");
      gDailyStopped   = false;
   }

   if(!gDailyStopped && gDayStartEquity > 0.0)
   {
      double dailyLoss = (gDayStartEquity - equity) / gDayStartEquity * 100.0;
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

   // --- SL buffer from ATR(16) on the entry TF ---
   double atrBuf;
   if(!BufVal(hATRslBuf, 0, 1, atrBuf) || atrBuf <= 0.0) return;
   double buffer = atrBuf * InpSL_BufferATRMult;

   bool buySignal  = (close1 > upper) && (close1 > ma);
   bool sellSignal = (close1 < lower) && (close1 < ma);

   if(buySignal)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      // SL from Donchian LOW minus a buffer (NOT from ATR distance)
      double sl    = lower - buffer;
      if(sl >= entry) return;                    // sanity: SL must be below entry
      OpenTrade(ORDER_TYPE_BUY, entry, sl);
   }
   else if(sellSignal)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      // SL from Donchian HIGH plus a buffer
      double sl    = upper + buffer;
      if(sl <= entry) return;                    // sanity: SL must be above entry
      OpenTrade(ORDER_TYPE_SELL, entry, sl);
   }
}

void OpenTrade(const ENUM_ORDER_TYPE type, const double entry, const double sl)
{
   double riskDist = MathAbs(entry - sl);
   if(riskDist <= 0.0)
      return;

   double lots = CalcLotSize(riskDist);
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
double CalcLotSize(const double riskDist)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || riskDist <= 0.0)
      return 0.0;

   // Loss (account currency) for 1.0 lot if SL is hit.
   // Works for Cent accounts automatically because tickValue is already
   // expressed in the deposit (cent) currency.
   double lossPerLot = (riskDist / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;

   double lots = riskMoney / lossPerLot;

   // confidence scaling
   if(InpEnableConfidence)
      lots *= gConfidence;

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
         else
         {
            gPosPartialDone[i] = true; // cannot split further, skip
         }
      }

      // ---- Multi-layer trailing (pick the safest stop) ----
      double newSL = ComputeTrailingSL(isBuy, cur);
      if(newSL > 0.0)
         ModifySL(ticket, isBuy, newSL, sl);
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

   // "Safest" = the stop that protects the most profit while still being on
   // the correct side of price: highest for buys, lowest for sells.
   double best = 0.0;
   bool   have = false;
   for(int i=0;i<c;i++)
   {
      double s = candidates[i];
      if(isBuy)
      {
         if(s >= price) continue;          // must be below price
         if(!have || s > best){ best=s; have=true; }
      }
      else
      {
         if(s <= price) continue;          // must be above price
         if(!have || s < best){ best=s; have=true; }
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
      string dir = (HistoryDealGetInteger(dealTicket, DEAL_TYPE)==DEAL_TYPE_BUY) ? "BUY" : "SELL";
      Notify(StringFormat("OPEN %s %.2f lots @ %.2f (conf x%.2f)", dir, vol, price, gConfidence));
   }
   else if(entry == DEAL_ENTRY_OUT)
   {
      Notify(StringFormat("CLOSE %.2f lots @ %.2f  P/L %.2f", vol, price, profit));
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
