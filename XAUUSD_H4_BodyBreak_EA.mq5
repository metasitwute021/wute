//+------------------------------------------------------------------+
//|                                       XAUUSD_H4_BodyBreak_EA.mq5 |
//|        "Body Break" momentum-candle system for XAUUSD (Gold)     |
//|                                                                  |
//|  Strategy summary (from the krv.karavas H4 gold clip)            |
//|  - Market / TF : XAUUSD, signals on H4 (closed bar only)         |
//|  - Signal BUY  : bullish bar (close > open) that closes above    |
//|                  the previous bar's high, and whose body is      |
//|                  >= 3x the average body of the previous 50 bars  |
//|  - Signal SELL : mirror (bearish, closes below previous low)     |
//|  - Bias (MTF)  : D1 close vs SMA(20) on D1 - trade with the bias |
//|                  (clip: win rate ~56% with bias, ~44% without)   |
//|  - Entry       : market at the open of the next bar              |
//|  - Stop Loss   : signal bar high/low (+ optional buffer)         |
//|  - Take Profit : fixed 1.5R (clip: 1.5R is the sweet spot,       |
//|                  3R = higher return but ~32% win rate)           |
//|  - Exit option : Chandelier exit trailing (clip: "best SL")      |
//|  - Stacking    : every signal opens a new trade, no waiting for  |
//|                  older trades to close (capped by max positions) |
//|  - Sizing      : risk % of balance via OrderCalcProfit (Cent OK) |
//|  - Guards      : daily DD / max DD (prop-firm exam style),       |
//|                  max spread, news filter (CSV - works in tester) |
//+------------------------------------------------------------------+
#property copyright "Metasit - Body Break EA"
#property version   "1.30"
#property strict

#include <Trade\Trade.mqh>

//==================================================================
//  Enums
//==================================================================
enum ENUM_BREAK_REF
{
   BREAK_PREV_HIGHLOW = 0,   // Close beyond previous bar HIGH/LOW
   BREAK_PREV_CLOSE   = 1    // Close beyond previous bar CLOSE
};
enum ENUM_SIZE_MODE
{
   SIZE_BODY  = 0,           // Candle body |close-open|
   SIZE_RANGE = 1            // Candle range high-low
};
enum ENUM_EXIT_MODE
{
   EXIT_FIXED_TP          = 0, // Fixed TP (R multiple) only
   EXIT_CHANDELIER        = 1, // No TP - Chandelier trailing only
   EXIT_TP_AND_CHANDELIER = 2  // Fixed TP + Chandelier trailing
};

//==================================================================
//  Inputs
//==================================================================
input group "=== General ==="
input long     InpMagic              = 20251009;    // Magic number
input bool     InpEnableNotifications= true;        // Send push notifications
input string   InpNotifPrefix        = "[XAU-BodyBreak] "; // Notification prefix
input bool     InpDrawOnChart        = true;        // Draw BUY/SELL + SL/TP boxes

input group "=== Signal (Body Break) ==="
input ENUM_TIMEFRAMES InpSignalTF    = PERIOD_H4;   // Signal timeframe
input int      InpAvgPeriod          = 50;          // Bars used for the average size
input double   InpSizeMult           = 3.0;         // Signal bar size >= mult x average
input ENUM_SIZE_MODE InpSizeMode     = SIZE_BODY;   // What "size" means
input ENUM_BREAK_REF InpBreakRef     = BREAK_PREV_HIGHLOW; // Close must break...

input group "=== Multi-Timeframe Bias ==="
input bool     InpUseBias            = true;        // Trade only with higher-TF bias
input ENUM_TIMEFRAMES InpBiasTF      = PERIOD_D1;   // Bias timeframe
input int      InpBiasSMA            = 20;          // Bias SMA period (close vs SMA)

input group "=== Stop Loss / Take Profit ==="
input double   InpSLBufferPts        = 0;           // SL buffer beyond signal bar (points)
input double   InpSLBufferATR        = 0.0;         // + SL buffer as ATR fraction (0 = off)
input double   InpTP_R               = 1.5;         // TP = R x SL distance
input double   InpMaxSL_ATR          = 0.0;         // Skip if SL > x ATR (0 = off)
input int      InpATRPeriod          = 14;          // ATR period (signal TF)

input group "=== Exit Mode ==="
input ENUM_EXIT_MODE InpExitMode     = EXIT_FIXED_TP; // Exit mode
input int      InpChandPeriod        = 22;          // Chandelier lookback (bars)
input double   InpChandATRMult       = 3.0;         // Chandelier ATR multiplier

input group "=== Risk Management ==="
input double   InpRiskPercent        = 1.0;         // Risk per trade (% balance)
input double   InpLotStepOverride    = 0.0;         // Force lot step (0 = broker)
input int      InpMaxPositions       = 1;           // Max open positions at once (0 = unlimited)

input group "=== Account Guards (prop-firm style) ==="
input double   InpDailyDDPct         = 4.0;         // Daily loss limit % (0 = off)
input double   InpMaxDDPct           = 9.0;         // Max loss % from start balance (0 = off)
input double   InpStartBalance       = 0.0;         // Start balance for max DD (0 = balance at start)
input bool     InpCloseOnGuard       = true;        // Close positions when a guard trips

input group "=== Filters ==="
input int      InpMaxSpreadPoints    = 100;         // Skip entry if spread > this (0 = off)

input group "=== News Filter (CSV works in Strategy Tester) ==="
input bool     InpUseFFNews          = false;       // Use news CSV file (works in tester + live)
input string   InpFFNewsFile         = "ff_news.csv"; // CSV in COMMON\Files: Date,Time,Currency,Impact
input string   InpFFBlockImpact      = "High";      // Impacts to use (High  or  High,Medium)
input int      InpFFTimeOffsetHours  = 0;           // Shift CSV times to server time (+/- hours)
input bool     InpEnableNewsFilter   = false;       // Also use MT5 calendar (live only)
input string   InpNewsCurrencies     = "USD";       // Currencies to watch (comma sep.)
input bool     InpNewsBlockEntry     = true;        // [1] No new entry near news
input int      InpNewsMinutesBefore  = 60;          //     ...minutes before news
input int      InpNewsMinutesAfter   = 60;          //     ...minutes after news
input bool     InpNewsSkipSignalBar  = false;       // [2] Skip signal if the signal bar had news
input bool     InpNewsClosePositions = false;       // [3] Close open trades before news
input int      InpNewsCloseMinutes   = 30;          //     ...this many minutes before news

//==================================================================
//  Globals
//==================================================================
CTrade   trade;
int      hATR     = INVALID_HANDLE;
int      hBiasMA  = INVALID_HANDLE;

datetime gLastBarTime = 0;
int      gDayKey      = -1;
double   gDayStartBal = 0.0;
double   gStartBal    = 0.0;
bool     gDailyHit    = false;
bool     gMaxDDHit    = false;

// news events loaded from CSV (server time, sorted ascending)
datetime gFFTime[];
string   gFFCcy[];
string   gFFImp[];
int      gFFCount     = 0;
datetime gLastNewsClose = 0;   // event time we already closed positions for

//==================================================================
//  Helpers
//==================================================================
void Notify(const string msg)
{
   string full = InpNotifPrefix + msg;
   Print(full);
   if(InpEnableNotifications && !MQLInfoInteger(MQL_TESTER))
      SendNotification(full);
}

bool BufVal(const int handle, const int buffer, const int shift, double &out)
{
   double b[];
   if(CopyBuffer(handle, buffer, shift, 1, b) != 1) return false;
   out = b[0];
   return (out != EMPTY_VALUE);
}

double CandleSize(const MqlRates &r)
{
   if(InpSizeMode == SIZE_RANGE) return r.high - r.low;
   return MathAbs(r.close - r.open);
}

//==================================================================
//  Lifecycle
//==================================================================
int OnInit()
{
   if(InpAvgPeriod < 2 || InpSizeMult <= 0.0 || InpTP_R < 0.0 || InpRiskPercent <= 0.0)
   {
      Print("Invalid inputs");
      return INIT_PARAMETERS_INCORRECT;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   hATR = iATR(_Symbol, InpSignalTF, InpATRPeriod);
   if(hATR == INVALID_HANDLE) { Print("ATR handle failed"); return INIT_FAILED; }

   LoadFFNews();

   if(InpUseBias)
   {
      hBiasMA = iMA(_Symbol, InpBiasTF, InpBiasSMA, 0, MODE_SMA, PRICE_CLOSE);
      if(hBiasMA == INVALID_HANDLE) { Print("Bias SMA handle failed"); return INIT_FAILED; }
   }

   gStartBal    = (InpStartBalance > 0.0 ? InpStartBalance : AccountInfoDouble(ACCOUNT_BALANCE));
   gLastBarTime = iTime(_Symbol, InpSignalTF, 0); // wait for the next fresh bar

   Notify(StringFormat("EA started on %s %s | size>=%.1fx avg(%d) | TP %.2fR | risk %.2f%%",
                       _Symbol, EnumToString(InpSignalTF), InpSizeMult, InpAvgPeriod,
                       InpTP_R, InpRiskPercent));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hATR    != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hBiasMA != INVALID_HANDLE) IndicatorRelease(hBiasMA);
   if(reason == REASON_REMOVE) ObjectsDeleteAll(0, "BB_");
   Notify("EA stopped (reason " + IntegerToString(reason) + ")");
}

void OnTick()
{
   UpdateGuards();
   ManageNewsClose();

   datetime barTime = iTime(_Symbol, InpSignalTF, 0);
   if(barTime == 0 || barTime == gLastBarTime) return;
   gLastBarTime = barTime;

   // ---- once per new signal-TF bar ----
   if(InpExitMode != EXIT_FIXED_TP) ManageChandelier();
   TryEnter();
}

//==================================================================
//  Account guards (daily DD / max DD)
//==================================================================
void UpdateGuards()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int key = t.year * 1000 + t.day_of_year;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(key != gDayKey)
   {
      gDayKey      = key;
      gDayStartBal = MathMax(bal, eq);
      if(gDailyHit) Notify("New day - daily DD guard reset");
      gDailyHit    = false;
   }

   if(!gDailyHit && InpDailyDDPct > 0.0 && eq <= gDayStartBal * (1.0 - InpDailyDDPct / 100.0))
   {
      gDailyHit = true;
      Notify(StringFormat("DAILY DD %.2f%% hit (equity %.2f) - no new trades today", InpDailyDDPct, eq));
      if(InpCloseOnGuard) CloseAllMine();
   }

   if(!gMaxDDHit && InpMaxDDPct > 0.0 && eq <= gStartBal * (1.0 - InpMaxDDPct / 100.0))
   {
      gMaxDDHit = true;
      Notify(StringFormat("MAX DD %.2f%% hit (equity %.2f) - EA stopped trading", InpMaxDDPct, eq));
      if(InpCloseOnGuard) CloseAllMine();
   }
}

bool TradingAllowed()
{
   if(gDailyHit || gMaxDDHit) return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
   if(InpMaxSpreadPoints > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPoints)
   {
      PrintFormat("Skip: spread %d > %d", (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), InpMaxSpreadPoints);
      return false;
   }
   if(InpNewsBlockEntry && IsNewsBlocking())
   {
      Print("Skip: news window");
      return false;
   }
   return true;
}

//==================================================================
//  Signal
//==================================================================
// dir: +1 buy, -1 sell, 0 none. Uses the last CLOSED bar (shift 1).
int GetSignal(MqlRates &sig)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int need = InpAvgPeriod + 2;  // [0]=forming, [1]=signal, [2..avg+1]=average window
   if(CopyRates(_Symbol, InpSignalTF, 0, need, r) < need) return 0;

   double sum = 0.0;
   for(int i = 2; i <= InpAvgPeriod + 1; i++) sum += CandleSize(r[i]);
   double avg = sum / InpAvgPeriod;
   if(avg <= 0.0) return 0;

   sig = r[1];
   double size = CandleSize(sig);
   if(size < InpSizeMult * avg) return 0;

   bool bull = (sig.close > sig.open);
   bool bear = (sig.close < sig.open);
   double refUp = (InpBreakRef == BREAK_PREV_HIGHLOW ? r[2].high : r[2].close);
   double refDn = (InpBreakRef == BREAK_PREV_HIGHLOW ? r[2].low  : r[2].close);

   if(bull && sig.close > refUp)
   {
      PrintFormat("BUY signal: size %.2f = %.2fx avg %.2f", size, size / avg, avg);
      return 1;
   }
   if(bear && sig.close < refDn)
   {
      PrintFormat("SELL signal: size %.2f = %.2fx avg %.2f", size, size / avg, avg);
      return -1;
   }
   return 0;
}

// +1 bull, -1 bear, 0 unknown/flat. Uses the last CLOSED bias bar (no look-ahead).
int BiasDirection()
{
   if(!InpUseBias) return 0;
   double ma;
   if(!BufVal(hBiasMA, 0, 1, ma)) return 0;
   double c = iClose(_Symbol, InpBiasTF, 1);
   if(c <= 0.0) return 0;
   if(c > ma) return 1;
   if(c < ma) return -1;
   return 0;
}

//==================================================================
//  Entry
//==================================================================
void TryEnter()
{
   MqlRates sig;
   int dir = GetSignal(sig);
   if(dir == 0) return;

   if(InpNewsSkipSignalBar &&
      FFNewsInRange(sig.time, sig.time + PeriodSeconds(InpSignalTF) - 1))
   {
      Print("Skip: signal bar was a news candle");
      return;
   }

   if(InpUseBias)
   {
      int bias = BiasDirection();
      if(bias != dir)
      {
         PrintFormat("Skip: signal %s against %s bias (%d)",
                     (dir > 0 ? "BUY" : "SELL"), EnumToString(InpBiasTF), bias);
         return;
      }
   }

   // new signal opens a new trade even while older ones are still running
   int nOpen = CountMyPositions();
   if(InpMaxPositions > 0 && nOpen >= InpMaxPositions)
   {
      PrintFormat("Skip: %d positions open (max %d)", nOpen, InpMaxPositions);
      return;
   }
   if(!TradingAllowed()) return;

   double atr = 0.0;
   BufVal(hATR, 0, 1, atr);

   double buffer = InpSLBufferPts * _Point + InpSLBufferATR * atr;
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double stopLv = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   ENUM_ORDER_TYPE type = (dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double entry = (dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID));
   double sl    = (dir > 0 ? sig.low - buffer : sig.high + buffer);
   double dist  = (dir > 0 ? entry - sl : sl - entry);

   if(dist <= stopLv || dist <= 0.0)
   {
      PrintFormat("Skip: price already beyond SL (entry %.2f SL %.2f)", entry, sl);
      return;
   }
   if(InpMaxSL_ATR > 0.0 && atr > 0.0 && dist > InpMaxSL_ATR * atr)
   {
      PrintFormat("Skip: SL %.2f > %.2f x ATR %.2f", dist, InpMaxSL_ATR, atr);
      return;
   }

   double tp = 0.0;
   if(InpExitMode != EXIT_CHANDELIER && InpTP_R > 0.0)
      tp = (dir > 0 ? entry + InpTP_R * dist : entry - InpTP_R * dist);

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   double lots = CalcLotSize(type, entry, sl);
   if(lots <= 0.0) { Print("Skip: lot size 0"); return; }

   bool ok = (dir > 0 ? trade.Buy(lots, _Symbol, 0.0, sl, tp, "BodyBreak")
                      : trade.Sell(lots, _Symbol, 0.0, sl, tp, "BodyBreak"));
   if(!ok)
   {
      Notify(StringFormat("OPEN FAILED %s: %d %s", (dir > 0 ? "BUY" : "SELL"),
                          trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      return;
   }

   double fill = trade.ResultPrice();
   if(fill <= 0.0) fill = entry;
   Notify(StringFormat("OPEN %s %.2f lots @ %.2f SL %.2f TP %.2f",
                       (dir > 0 ? "BUY" : "SELL"), lots, fill, sl, tp));
   if(InpDrawOnChart) DrawTrade(dir, sig.time, fill, sl, tp);
}

//==================================================================
//  Chandelier exit trailing (runs once per new bar)
//==================================================================
void ManageChandelier()
{
   double atr;
   if(!BufVal(hATR, 0, 1, atr) || atr <= 0.0) return;

   int hiIdx = iHighest(_Symbol, InpSignalTF, MODE_HIGH, InpChandPeriod, 1);
   int loIdx = iLowest (_Symbol, InpSignalTF, MODE_LOW,  InpChandPeriod, 1);
   if(hiIdx < 0 || loIdx < 0) return;
   double hh = iHigh(_Symbol, InpSignalTF, hiIdx);
   double ll = iLow (_Symbol, InpSignalTF, loIdx);

   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double stopLv = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsMine()) continue;

      bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double newSL = NormalizeDouble(isBuy ? hh - InpChandATRMult * atr
                                           : ll + InpChandATRMult * atr, digits);

      bool better = isBuy ? (curSL == 0.0 || newSL > curSL + _Point)
                          : (curSL == 0.0 || newSL < curSL - _Point);
      bool valid  = isBuy ? (newSL < bid - stopLv) : (newSL > ask + stopLv);
      if(!better || !valid) continue;

      if(trade.PositionModify(ticket, newSL, curTP))
         Notify(StringFormat("TRAIL #%I64u SL %.2f -> %.2f", ticket, curSL, newSL));
   }
}

//==================================================================
//  Positions
//==================================================================
bool IsMine()
{
   return (PositionGetString(POSITION_SYMBOL) == _Symbol &&
           PositionGetInteger(POSITION_MAGIC) == InpMagic);
}

int CountMyPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && IsMine()) n++;
   return n;
}

void CloseAllMine(const string why = "guard")
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsMine()) continue;
      if(trade.PositionClose(ticket))
         Notify(StringFormat("CLOSE #%I64u by %s", ticket, why));
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string why = (reason == DEAL_REASON_TP ? "TP" : (reason == DEAL_REASON_SL ? "SL" : "CLOSE"));
   Notify(StringFormat("%s %.2f lots @ %.2f | P/L %.2f",
                       why, HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
                       HistoryDealGetDouble(trans.deal, DEAL_PRICE), profit));
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
   double riskPctReal = (balance > 0.0 ? lossPerLot * lots / balance * 100.0 : 0.0);
   PrintFormat("SIZING bal=%.2f dist=%.2f lossPerLot=%.2f -> %.2f lots (risk %.2f%%)",
               balance, MathAbs(entry - sl), lossPerLot, lots, riskPctReal);

   if(riskPctReal > InpRiskPercent * 1.5)
   {
      Notify(StringFormat("Skip: min lot %.2f would risk %.2f%% (> %.2f%%)",
                          lots, riskPctReal, InpRiskPercent));
      return 0.0;
   }
   return lots;
}

double NormalizeVolume(double vol)
{
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = (InpLotStepOverride > 0.0 ? InpLotStepOverride
                                           : SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
   if(step <= 0.0) step = 0.01;

   vol = MathFloor(vol / step + 1e-9) * step;
   if(vol < minV) vol = minV;
   if(vol > maxV) vol = maxV;

   int digits = (int)MathRound(MathLog10(1.0 / step));
   if(digits < 0) digits = 0;
   return NormalizeDouble(vol, digits);
}

//==================================================================
//  Chart drawing (arrow + SL/TP boxes like the clip)
//==================================================================
void DrawTrade(const int dir, const datetime sigTime, const double entry,
               const double sl, const double tp)
{
   string id   = "BB_" + IntegerToString((long)sigTime);
   datetime t0 = iTime(_Symbol, InpSignalTF, 0);
   datetime t1 = t0 + PeriodSeconds(InpSignalTF) * 12;

   ObjectCreate(0, id + "_arrow", OBJ_ARROW, 0, sigTime, sl);
   ObjectSetInteger(0, id + "_arrow", OBJPROP_ARROWCODE, (dir > 0 ? 233 : 234));
   ObjectSetInteger(0, id + "_arrow", OBJPROP_COLOR, (dir > 0 ? clrLime : clrRed));
   ObjectSetInteger(0, id + "_arrow", OBJPROP_ANCHOR, (dir > 0 ? ANCHOR_TOP : ANCHOR_BOTTOM));
   ObjectSetInteger(0, id + "_arrow", OBJPROP_WIDTH, 2);

   ObjectCreate(0, id + "_sl", OBJ_RECTANGLE, 0, t0, entry, t1, sl);
   ObjectSetInteger(0, id + "_sl", OBJPROP_COLOR, clrCrimson);
   ObjectSetInteger(0, id + "_sl", OBJPROP_FILL, true);
   ObjectSetInteger(0, id + "_sl", OBJPROP_BACK, true);

   if(tp > 0.0)
   {
      ObjectCreate(0, id + "_tp", OBJ_RECTANGLE, 0, t0, entry, t1, tp);
      ObjectSetInteger(0, id + "_tp", OBJPROP_COLOR, clrDarkGreen);
      ObjectSetInteger(0, id + "_tp", OBJPROP_FILL, true);
      ObjectSetInteger(0, id + "_tp", OBJPROP_BACK, true);
   }

   ObjectCreate(0, id + "_txt", OBJ_TEXT, 0, t0, entry);
   ObjectSetString (0, id + "_txt", OBJPROP_TEXT,
                    StringFormat("%s  Entry %.2f  SL %.2f  TP %.2f (%.1fR)",
                                 (dir > 0 ? "BUY" : "SELL"), entry, sl, tp, InpTP_R));
   ObjectSetInteger(0, id + "_txt", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, id + "_txt", OBJPROP_ANCHOR, ANCHOR_RIGHT);
   ChartRedraw();
}

//==================================================================
//  News filter
//  - CSV file (Common\Files, e.g. from FF_News_Exporter): works in tester
//  - MT5 economic calendar: live only (empty in tester)
//==================================================================
bool IsWatchedCurrency(const string ccy)
{
   return InList(InpNewsCurrencies, ccy);
}

// True if 'val' is in a comma-separated list (case-insensitive).
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
   ArrayResize(gFFTime, 0); ArrayResize(gFFCcy, 0); ArrayResize(gFFImp, 0);
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
      if(!IsWatchedCurrency(c3) || !InList(InpFFBlockImpact, c4)) continue;

      int n = gFFCount;
      ArrayResize(gFFTime, n + 1); ArrayResize(gFFCcy, n + 1); ArrayResize(gFFImp, n + 1);
      gFFTime[n] = t; gFFCcy[n] = c3; gFFImp[n] = c4;
      gFFCount = n + 1;
   }
   FileClose(fh);

   // insertion sort by time (file is usually sorted already -> fast)
   for(int i = 1; i < gFFCount; i++)
   {
      datetime kt = gFFTime[i]; string kc = gFFCcy[i]; string ki = gFFImp[i];
      int j = i - 1;
      while(j >= 0 && gFFTime[j] > kt)
      {
         gFFTime[j + 1] = gFFTime[j]; gFFCcy[j + 1] = gFFCcy[j]; gFFImp[j + 1] = gFFImp[j];
         j--;
      }
      gFFTime[j + 1] = kt; gFFCcy[j + 1] = kc; gFFImp[j + 1] = ki;
   }

   if(gFFCount > 0)
      Notify(StringFormat("NEWS loaded: %d events (%s) from %s | %s -> %s",
                          gFFCount, InpFFBlockImpact, InpFFNewsFile,
                          TimeToString(gFFTime[0], TIME_DATE),
                          TimeToString(gFFTime[gFFCount - 1], TIME_DATE)));
   else
      Notify("NEWS file loaded but 0 matching events - check currency/impact columns");
}

// Index of the first loaded event with time >= t (binary search).
int FFLowerBound(const datetime t)
{
   int lo = 0, hi = gFFCount;
   while(lo < hi)
   {
      int mid = (lo + hi) / 2;
      if(gFFTime[mid] < t) lo = mid + 1; else hi = mid;
   }
   return lo;
}

// First loaded event time in [from, to], or 0 if none.
datetime FFNewsAt(const datetime from, const datetime to)
{
   if(gFFCount == 0) return 0;
   int i = FFLowerBound(from);
   if(i < gFFCount && gFFTime[i] <= to) return gFFTime[i];
   return 0;
}

bool FFNewsInRange(const datetime from, const datetime to)
{
   return (FFNewsAt(from, to) > 0);
}

bool IsNewsBlocking()
{
   datetime now = TimeCurrent();
   datetime from = now - (datetime)(InpNewsMinutesAfter  * 60);
   datetime to   = now + (datetime)(InpNewsMinutesBefore * 60);

   if(FFNewsInRange(from, to)) return true;
   if(!InpEnableNewsFilter || MQLInfoInteger(MQL_TESTER)) return false;

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to, NULL, NULL);
   for(int i = 0; i < total; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)  continue;

      MqlCalendarCountry country;
      if(CalendarCountryById(ev.country_id, country) && !IsWatchedCurrency(country.currency))
         continue;
      return true;
   }
   return false;
}

// [3] Close open trades shortly before a CSV news event (checked every tick).
void ManageNewsClose()
{
   if(!InpNewsClosePositions || gFFCount == 0) return;
   datetime now = TimeCurrent();
   datetime ev  = FFNewsAt(now, now + (datetime)(InpNewsCloseMinutes * 60));
   if(ev == 0 || ev == gLastNewsClose) return;
   gLastNewsClose = ev;
   if(CountMyPositions() == 0) return;

   Notify(StringFormat("NEWS at %s - closing open trades", TimeToString(ev, TIME_DATE | TIME_MINUTES)));
   CloseAllMine("news");
}
//+------------------------------------------------------------------+
