//+------------------------------------------------------------------+
//|                                 XAUUSD_M1_Donchian_Scalper.mq5    |
//|        M1 Donchian breakout scalper for XAUUSD (Gold)            |
//|        *** Standalone, lightweight management ***                 |
//|                                                                  |
//|  Strategy summary                                                |
//|  - Market / TF : XAUUSD (GOLDm#), signals on M1                   |
//|  - Entry       : Donchian(N) breakout on M1, in the direction of  |
//|                  a higher-TF EMA trend filter                     |
//|  - Stop Loss   : ATR(M1) based  -> entry -/+ mult * ATR           |
//|  - Take Profit : fixed R multiple of the SL distance (R:R)        |
//|  - Sizing      : risk % of balance via OrderCalcProfit (Cent OK)  |
//|  - Management  : break-even only (no partial / no trailing)       |
//|  - Filters     : max spread, higher-TF trend, optional news       |
//|  - Alerts      : push notifications on every event                |
//+------------------------------------------------------------------+
#property copyright "XAUUSD M1 Donchian Scalper"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//==================================================================
//  Enums (shared style with the H4 EA)
//==================================================================
enum ENUM_ACCT_MODE  { ACCOUNT_STANDARD=0, ACCOUNT_CENT=1 };
enum ENUM_ASSET_MODE { ASSET_2_DECIMAL=0,  ASSET_3_DECIMAL=1 };
enum ENUM_K_MODE     { K_STA=0, K_CENT=1, K_CENT_XM=2 };

//==================================================================
//  Inputs
//==================================================================
input group "=== General ==="
input long     InpMagic              = 20250201;   // Magic number (unique vs H4 EA)
input bool     InpEnableNotifications= true;       // Send push notifications
input string   InpNotifPrefix        = "[XAU-M1-DON] "; // Notification prefix

input group "=== Entry (Donchian breakout on M1) ==="
input int      InpDonchianPeriod     = 20;         // Donchian channel period (M1 bars)
input bool     InpUseTrendFilter     = true;       // Only trade with higher-TF EMA trend
input ENUM_TIMEFRAMES InpTrendTF      = PERIOD_M15; // Higher-TF for trend filter
input int      InpTrendEMA           = 50;         // Trend EMA period (on trend TF)

input group "=== Stop Loss / Take Profit ==="
input int      InpSL_ATRPeriod       = 14;         // ATR period for SL (M1)
input double   InpSL_ATRMult         = 1.5;        // SL = mult x ATR
input double   InpTP_RMultiple        = 1.5;       // TP = R x SL distance (0 = no TP)

input group "=== Management (lightweight) ==="
input bool     InpUseBreakEven       = true;       // Move SL to break-even
input double   InpBreakEvenR         = 0.6;        // Move to BE at this R
input double   InpBE_BufferPts       = 20;         // BE buffer (points beyond entry)

input group "=== Filters ==="
input int      InpMaxSpreadPoints    = 50;         // Skip entry if spread > this (points)
input bool     InpEnableNewsFilter   = false;      // Avoid trading around news (live only)
input int      InpNewsMinutesBefore  = 30;         // Block window before news (min)
input int      InpNewsMinutesAfter   = 30;         // Block window after news (min)
input string   InpNewsCurrencies     = "USD";      // Currencies to watch (comma sep.)

input group "=== Risk Management ==="
input double          InpRiskPercent = 1.0;             // Risk per trade (% balance)
input ENUM_ACCT_MODE  InpAccountType = ACCOUNT_CENT;    // Account type
input ENUM_ASSET_MODE InpAssetType   = ASSET_2_DECIMAL; // Asset price decimals
input ENUM_K_MODE     InpKParameter  = K_CENT;          // Lot coefficient profile (K)
input double          InpLotStepOverride = 0.0;         // Force lot step (0 = auto/broker)
input int             InpMaxPositions= 1;               // Max simultaneous positions

//==================================================================
//  Globals
//==================================================================
CTrade   trade;

int hATRsl  = INVALID_HANDLE;   // M1 ATR for SL
int hTrend  = INVALID_HANDLE;   // higher-TF EMA for trend filter

datetime gLastBar = 0;          // M1 new-bar tracking
bool     gInNews  = false;

// per-position state (for break-even)
ulong    gPosTicket[];
double   gPosInitRisk[];
bool     gPosBEDone[];

//==================================================================
//  Utility
//==================================================================
void Notify(const string msg)
{
   Print(msg);
   if(InpEnableNotifications)
      SendNotification(InpNotifPrefix + msg);
}

bool BufVal(const int handle, const int buffer, const int shift, double &out)
{
   double tmp[];
   if(CopyBuffer(handle, buffer, shift, 1, tmp) < 1)
      return false;
   out = tmp[0];
   return true;
}

//==================================================================
//  Init / Deinit
//==================================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(30);

   hATRsl = iATR(_Symbol, PERIOD_M1, InpSL_ATRPeriod);
   hTrend = iMA (_Symbol, InpTrendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(hATRsl==INVALID_HANDLE || hTrend==INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }

   EventSetTimer(5);
   Notify("M1 Donchian scalper started on " + _Symbol);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(hATRsl!=INVALID_HANDLE) IndicatorRelease(hATRsl);
   if(hTrend!=INVALID_HANDLE) IndicatorRelease(hTrend);
   Notify("M1 Donchian scalper stopped (reason " + IntegerToString(reason) + ")");
}

void OnTimer()
{
   UpdateNewsState();
}

//==================================================================
//  Main tick
//==================================================================
void OnTick()
{
   SyncPositionState();
   ManageOpenPositions();   // break-even only

   datetime curBar = (datetime)iTime(_Symbol, PERIOD_M1, 0);
   if(curBar == gLastBar)
      return;
   gLastBar = curBar;

   if(!TradingAllowed())
      return;

   TryEnter();
}

//==================================================================
//  Trading gate
//==================================================================
bool TradingAllowed()
{
   if(gInNews) return false;
   if(CountMyPositions() >= InpMaxPositions) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
      return false;
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
//  Trend filter
//==================================================================
// +1 = up trend, -1 = down trend, 0 = filter disabled / unavailable
int TrendDirection()
{
   if(!InpUseTrendFilter)
      return 0;
   double ema;
   if(!BufVal(hTrend, 0, 0, ema))
      return 0;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(price > ema) return 1;
   if(price < ema) return -1;
   return 0;
}

//==================================================================
//  Entry: Donchian breakout on M1
//==================================================================
void TryEnter()
{
   int N = InpDonchianPeriod;
   if(N < 2) N = 2;

   // Donchian band from the N bars that PRECEDE the just-closed bar
   // (highest high / lowest low of bars [2 .. N+1]).
   int hhIdx = iHighest(_Symbol, PERIOD_M1, MODE_HIGH, N, 2);
   int llIdx = iLowest (_Symbol, PERIOD_M1, MODE_LOW,  N, 2);
   if(hhIdx < 0 || llIdx < 0) return;

   double upper = iHigh(_Symbol, PERIOD_M1, hhIdx);
   double lower = iLow (_Symbol, PERIOD_M1, llIdx);
   double close1= iClose(_Symbol, PERIOD_M1, 1);
   if(upper <= 0.0 || lower <= 0.0 || close1 <= 0.0) return;

   double atr;
   if(!BufVal(hATRsl, 0, 1, atr) || atr <= 0.0) return;
   double slDist = InpSL_ATRMult * atr;
   if(slDist <= 0.0) return;

   int trend = TrendDirection();   // 0 if filter off

   bool buySignal  = (close1 > upper) && (trend >= 0);
   bool sellSignal = (close1 < lower) && (trend <= 0);

   if(buySignal)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl    = entry - slDist;
      double tp    = (InpTP_RMultiple > 0.0) ? entry + InpTP_RMultiple * slDist : 0.0;
      if(sl >= entry) return;
      OpenTrade(ORDER_TYPE_BUY, entry, sl, tp);
   }
   else if(sellSignal)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl    = entry + slDist;
      double tp    = (InpTP_RMultiple > 0.0) ? entry - InpTP_RMultiple * slDist : 0.0;
      if(sl <= entry) return;
      OpenTrade(ORDER_TYPE_SELL, entry, sl, tp);
   }
}

//==================================================================
//  Order open + lot sizing
//==================================================================
void OpenTrade(const ENUM_ORDER_TYPE type, const double entry, const double sl, const double tp)
{
   double lots = CalcLotSize(type, entry, sl);
   if(lots <= 0.0)
   {
      Print("Lot size computed as 0 - skipping entry");
      return;
   }

   bool ok = (type==ORDER_TYPE_BUY)
             ? trade.Buy (lots, _Symbol, entry, sl, tp, "M1-Donchian")
             : trade.Sell(lots, _Symbol, entry, sl, tp, "M1-Donchian");
   if(!ok)
   {
      Print("Order send failed: ", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
      return;
   }
   Notify(StringFormat("OPEN %s %.2f lots @ %.2f SL %.2f TP %.2f",
                       (type==ORDER_TYPE_BUY?"BUY":"SELL"), lots, entry, sl, tp));
}

double GetLotCoefficient()
{
   switch(InpKParameter)
   {
      case K_STA:     return 1.0;
      case K_CENT:    return 1.0;
      case K_CENT_XM: return 1.0;
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
   double lotsFinal = NormalizeVolume(rawLots * GetLotCoefficient());

   double lossAtFinal = lossPerLot * lotsFinal;
   double riskPctReal = (balance > 0.0 ? lossAtFinal / balance * 100.0 : 0.0);

   PrintFormat("SIZING bal=%.2f risk%%=%.2f | dist=%.2f lossPerLot=%.2f | raw=%.5f -> final=%.2f | risk=%.2f%%",
               balance, InpRiskPercent, riskDist, lossPerLot, rawLots, lotsFinal, riskPctReal);

   if(riskPctReal > InpRiskPercent * 1.5)
      Notify(StringFormat("WARNING: min-lot %.2f risks %.2f%% (> target %.2f%%)",
                          lotsFinal, riskPctReal, InpRiskPercent));
   return lotsFinal;
}

double EffectiveLotStep()
{
   double brokerStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(brokerStep <= 0.0) brokerStep = 0.01;
   if(InpLotStepOverride > 0.0) return InpLotStepOverride;
   if(InpKParameter == K_CENT_XM && brokerStep > 0.01) return 0.01;
   return brokerStep;
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
//  Per-position state (break-even tracking)
//==================================================================
int FindPosStateIndex(const ulong ticket)
{
   for(int i=0; i<ArraySize(gPosTicket); i++)
      if(gPosTicket[i]==ticket) return i;
   return -1;
}

void AddPosState(const ulong ticket, const double risk)
{
   int n = ArraySize(gPosTicket);
   ArrayResize(gPosTicket,   n+1);
   ArrayResize(gPosInitRisk, n+1);
   ArrayResize(gPosBEDone,   n+1);
   gPosTicket[n]   = ticket;
   gPosInitRisk[n] = risk;
   gPosBEDone[n]   = false;
}

void RemovePosStateAt(const int idx)
{
   int n = ArraySize(gPosTicket);
   if(idx<0 || idx>=n) return;
   for(int i=idx; i<n-1; i++)
   {
      gPosTicket[i]   = gPosTicket[i+1];
      gPosInitRisk[i] = gPosInitRisk[i+1];
      gPosBEDone[i]   = gPosBEDone[i+1];
   }
   ArrayResize(gPosTicket,   n-1);
   ArrayResize(gPosInitRisk, n-1);
   ArrayResize(gPosBEDone,   n-1);
}

void SyncPositionState()
{
   // add newly seen positions
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)  continue;
      if(FindPosStateIndex(t) >= 0) continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double risk = MathAbs(open - sl);
      AddPosState(t, risk);
   }
   // drop closed positions
   for(int i=ArraySize(gPosTicket)-1; i>=0; i--)
   {
      if(!PositionSelectByTicket(gPosTicket[i]))
         RemovePosStateAt(i);
   }
}

//==================================================================
//  Management: break-even only
//==================================================================
void ManageOpenPositions()
{
   if(!InpUseBreakEven) return;

   for(int i=ArraySize(gPosTicket)-1; i>=0; i--)
   {
      ulong ticket = gPosTicket[i];
      if(!PositionSelectByTicket(ticket)) continue;

      double R = gPosInitRisk[i];
      if(R <= 0.0 || gPosBEDone[i]) continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      bool   isBuy= (type==POSITION_TYPE_BUY);
      double cur  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                          : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitDist = isBuy ? (cur - open) : (open - cur);

      if(profitDist >= InpBreakEvenR * R)
      {
         double buf  = InpBE_BufferPts * _Point;
         double beSL = isBuy ? open + buf : open - buf;
         if(ModifySL(ticket, isBuy, beSL, sl))
         {
            gPosBEDone[i] = true;
            Notify(StringFormat("Break-even set #%I64u @ %.2f", ticket, beSL));
         }
      }
   }
}

bool ModifySL(const ulong ticket, const bool isBuy, double newSL, const double curSL)
{
   if(newSL <= 0.0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   double tp    = PositionGetDouble(POSITION_TP);
   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopLevel * _Point;
   if(isBuy  && (price - newSL) < minDist) return false;
   if(!isBuy && (newSL - price) < minDist) return false;

   // only tighten in the favorable direction
   if(curSL > 0.0)
   {
      if(isBuy  && newSL <= curSL + _Point) return false;
      if(!isBuy && newSL >= curSL - _Point) return false;
   }
   newSL = NormalizeDouble(newSL, _Digits);
   return trade.PositionModify(ticket, newSL, tp);
}

//==================================================================
//  News filter (MT5 economic calendar - LIVE only, empty in tester)
//==================================================================
bool IsWatchedCurrency(const string ccy)
{
   string parts[];
   int n = StringSplit(InpNewsCurrencies, ',', parts);
   for(int i=0; i<n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p); StringTrimRight(p);
      if(StringCompare(p, ccy, false)==0) return true;
   }
   return false;
}

bool IsNewsBlocking()
{
   if(!InpEnableNewsFilter) return false;

   datetime now  = TimeCurrent();
   datetime from = now - (datetime)(InpNewsMinutesAfter  * 60);
   datetime to   = now + (datetime)(InpNewsMinutesBefore * 60);

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to, NULL, NULL);
   if(total <= 0) return false;   // tester / unavailable -> do not block

   for(int i=0; i<total; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)  continue;

      MqlCalendarCountry country;
      string ccy = "";
      if(CalendarCountryById(ev.country_id, country)) ccy = country.currency;
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
      Notify("NEWS filter ON - trading paused");
   }
   else if(!blocking && gInNews)
   {
      gInNews = false;
      Notify("NEWS filter OFF - trading resumed");
   }
}
//+------------------------------------------------------------------+
