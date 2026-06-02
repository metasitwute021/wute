//+------------------------------------------------------------------+
//|                                   XAUUSD_M1_RSI_SR_Scalper.mq5    |
//|        M1 RSI mean-reversion + auto Support/Resistance LIMIT     |
//|        *** Standalone, lightweight management ***                 |
//|                                                                  |
//|  Strategy summary (your style)                                   |
//|  - Market / TF : XAUUSD (GOLDm#), signals on M1                   |
//|  - Idea        : RSI dips to ~30 -> look to BUY                   |
//|                  RSI rises to ~70 -> look to SELL                 |
//|                  RSI around ~50   -> do nothing (wait)            |
//|  - Levels      : EA auto-detects nearest swing-based support /    |
//|                  resistance and places a pending LIMIT there      |
//|  - Stop Loss   : ATR(M1) based  -> entry -/+ mult * ATR           |
//|  - Take Profit : fixed R multiple of the SL distance (R:R)        |
//|  - Sizing      : risk % of balance via OrderCalcProfit (Cent OK)  |
//|  - Management  : break-even, ATR trailing (SL follows strength),  |
//|                  close an order at X% profit of balance; pending  |
//|                  auto-cancel on neutral RSI or after expiry       |
//|  - Filters     : max spread, optional news                        |
//|  - Alerts      : push notifications on every event                |
//+------------------------------------------------------------------+
#property copyright "XAUUSD M1 RSI + S/R LIMIT Scalper"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>

//==================================================================
//  Enums (shared style with the other EAs)
//==================================================================
enum ENUM_ACCT_MODE  { ACCOUNT_STANDARD=0, ACCOUNT_CENT=1 };
enum ENUM_ASSET_MODE { ASSET_2_DECIMAL=0,  ASSET_3_DECIMAL=1 };
enum ENUM_K_MODE     { K_STA=0, K_CENT=1, K_CENT_XM=2 };

//==================================================================
//  Inputs
//==================================================================
input group "=== General ==="
input long     InpMagic              = 20250203;   // Magic number (unique vs other EAs)
input bool     InpEnableNotifications= true;       // Send push notifications
input string   InpNotifPrefix        = "[XAU-M1-RSI] "; // Notification prefix

input group "=== RSI signal (M1) ==="
input int      InpRSIPeriod          = 14;         // RSI period
input double   InpRSIOversold        = 30.0;       // RSI <= this -> arm a BUY
input double   InpRSIOverbought      = 70.0;       // RSI >= this -> arm a SELL
input double   InpRSICancelLevel     = 50.0;       // Cancel pending when RSI returns past this

input group "=== Auto Support / Resistance ==="
input int      InpSRLookback         = 120;        // Bars to scan for swing levels
input int      InpFractalWing        = 3;          // Bars each side for a swing pivot
input double   InpEntryOffsetPoints  = 0;          // Offset limit toward market (points)
input double   InpMaxLevelDistPts    = 0;          // Skip if level farther than this (0=off)

input group "=== Stop Loss / Take Profit ==="
input int      InpSL_ATRPeriod       = 14;         // ATR period for SL (M1)
input double   InpSL_ATRMult         = 1.5;        // SL = mult x ATR (beyond entry)
input double   InpTP_RMultiple        = 1.5;       // TP = R x SL distance (0 = no TP)

input group "=== Management (lightweight) ==="
input bool     InpUseBreakEven       = true;       // Move SL to break-even
input double   InpBreakEvenR         = 0.6;        // Move to BE at this R
input double   InpBE_BufferPts       = 20;         // BE buffer (points beyond entry)
input int      InpPendingExpiryMin   = 60;         // Cancel unfilled pending after N min (0=off)

input group "=== ATR trailing stop (SL follows strength/volatility) ==="
input bool     InpUseTrailing        = true;       // Trail SL by ATR (strong move = wider SL)
input double   InpTrailStartR        = 1.0;        // Start trailing after profit >= this R
input double   InpTrailATRMult        = 2.0;       // Trail distance = mult x ATR(M1)

input group "=== Profit target (close per order) ==="
input double   InpProfitClosePct     = 7.0;        // Close an order when its profit >= % of balance (0=off)

input group "=== Filters ==="
input int      InpMaxSpreadPoints    = 50;         // Skip new orders if spread > this (points)
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
input int             InpMaxPositions= 2;               // Max simultaneous OPEN positions

//==================================================================
//  Globals
//==================================================================
CTrade   trade;

int hRSI    = INVALID_HANDLE;   // M1 RSI
int hATRsl  = INVALID_HANDLE;   // M1 ATR for SL

datetime gLastBar = 0;
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

   hRSI   = iRSI(_Symbol, PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   hATRsl = iATR(_Symbol, PERIOD_M1, InpSL_ATRPeriod);

   if(hRSI==INVALID_HANDLE || hATRsl==INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }

   EventSetTimer(5);
   Notify("M1 RSI+S/R scalper started on " + _Symbol);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(hRSI!=INVALID_HANDLE)   IndicatorRelease(hRSI);
   if(hATRsl!=INVALID_HANDLE) IndicatorRelease(hATRsl);
   Notify("M1 RSI+S/R scalper stopped (reason " + IntegerToString(reason) + ")");
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
   ManageOpenPositions();   // profit-% close, break-even, ATR trailing

   datetime curBar = (datetime)iTime(_Symbol, PERIOD_M1, 0);
   if(curBar == gLastBar)
      return;
   gLastBar = curBar;

   ManagePendingOrders();   // expiry / cancel-on-neutral, runs every new bar

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
   if(CountOpenPositions() >= InpMaxPositions) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
      return false;
   return true;
}

int CountOpenPositions()
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

// true if we already have a position OR a pending order in the given direction
bool HasOrderSide(const bool isBuy)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)  continue;
      bool posBuy = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      if(posBuy==isBuy) return true;
   }
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol)  continue;
      long ot = OrderGetInteger(ORDER_TYPE);
      bool ordBuy = (ot==ORDER_TYPE_BUY_LIMIT);
      bool ordSell= (ot==ORDER_TYPE_SELL_LIMIT);
      if(isBuy && ordBuy)  return true;
      if(!isBuy && ordSell) return true;
   }
   return false;
}

//==================================================================
//  Auto Support / Resistance (swing pivots)
//==================================================================
// nearest swing-low strictly below refPrice (highest such low), else -1
double FindSupport(const double refPrice)
{
   int wing = (InpFractalWing < 1) ? 1 : InpFractalWing;
   double best = -1.0;
   for(int s=wing+1; s<=InpSRLookback; s++)
   {
      double lo = iLow(_Symbol, PERIOD_M1, s);
      if(lo <= 0.0) continue;
      bool isSwing = true;
      for(int k=1; k<=wing; k++)
      {
         if(iLow(_Symbol, PERIOD_M1, s-k) < lo ||
            iLow(_Symbol, PERIOD_M1, s+k) < lo) { isSwing=false; break; }
      }
      if(!isSwing) continue;
      if(lo < refPrice && lo > best) best = lo;
   }
   return best;
}

// nearest swing-high strictly above refPrice (lowest such high), else -1
double FindResistance(const double refPrice)
{
   int wing = (InpFractalWing < 1) ? 1 : InpFractalWing;
   double best = -1.0;
   for(int s=wing+1; s<=InpSRLookback; s++)
   {
      double hi = iHigh(_Symbol, PERIOD_M1, s);
      if(hi <= 0.0) continue;
      bool isSwing = true;
      for(int k=1; k<=wing; k++)
      {
         if(iHigh(_Symbol, PERIOD_M1, s-k) > hi ||
            iHigh(_Symbol, PERIOD_M1, s+k) > hi) { isSwing=false; break; }
      }
      if(!isSwing) continue;
      if(hi > refPrice && (best < 0.0 || hi < best)) best = hi;
   }
   return best;
}

//==================================================================
//  Entry: arm pending LIMIT at the auto S/R when RSI is extreme
//==================================================================
void TryEnter()
{
   double rsi;
   if(!BufVal(hRSI, 0, 1, rsi)) return;

   double atr;
   if(!BufVal(hATRsl, 0, 1, atr) || atr <= 0.0) return;
   double slDist = InpSL_ATRMult * atr;
   if(slDist <= 0.0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   long   stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist   = stopLevel * _Point;

   // ----- BUY side: RSI oversold -> BUY LIMIT at nearest support -----
   if(rsi <= InpRSIOversold && !HasOrderSide(true))
   {
      double support = FindSupport(ask);
      if(support > 0.0)
      {
         double entry = support + InpEntryOffsetPoints * _Point;
         if(entry < ask - minDist)   // must be a valid buy-limit below market
         {
            double dist = ask - entry;
            if(InpMaxLevelDistPts <= 0.0 || dist <= InpMaxLevelDistPts * _Point)
            {
               double sl = entry - slDist;
               double tp = (InpTP_RMultiple > 0.0) ? entry + InpTP_RMultiple * slDist : 0.0;
               PlaceLimit(true, entry, sl, tp);
            }
         }
      }
   }

   // ----- SELL side: RSI overbought -> SELL LIMIT at nearest resistance -----
   if(rsi >= InpRSIOverbought && !HasOrderSide(false))
   {
      double resistance = FindResistance(bid);
      if(resistance > 0.0)
      {
         double entry = resistance - InpEntryOffsetPoints * _Point;
         if(entry > bid + minDist)   // must be a valid sell-limit above market
         {
            double dist = entry - bid;
            if(InpMaxLevelDistPts <= 0.0 || dist <= InpMaxLevelDistPts * _Point)
            {
               double sl = entry + slDist;
               double tp = (InpTP_RMultiple > 0.0) ? entry - InpTP_RMultiple * slDist : 0.0;
               PlaceLimit(false, entry, sl, tp);
            }
         }
      }
   }
}

void PlaceLimit(const bool isBuy, double entry, double sl, double tp)
{
   entry = NormalizeDouble(entry, _Digits);
   sl    = NormalizeDouble(sl,    _Digits);
   tp    = (tp>0.0) ? NormalizeDouble(tp, _Digits) : 0.0;

   double lots = CalcLotSize(isBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL, entry, sl);
   if(lots <= 0.0)
   {
      Print("Lot size computed as 0 - skipping pending");
      return;
   }

   bool ok = isBuy
             ? trade.BuyLimit (lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "M1-RSI-SR")
             : trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "M1-RSI-SR");
   if(!ok)
   {
      Print("Pending send failed: ", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
      return;
   }
   Notify(StringFormat("PENDING %s LIMIT %.2f lots @ %.2f SL %.2f TP %.2f",
                       (isBuy?"BUY":"SELL"), lots, entry, sl, tp));
}

//==================================================================
//  Pending order maintenance: expiry + cancel on neutral RSI
//==================================================================
void ManagePendingOrders()
{
   double rsi;
   bool haveRSI = BufVal(hRSI, 0, 1, rsi);
   datetime now = TimeCurrent();

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol)  continue;

      long ot = OrderGetInteger(ORDER_TYPE);
      bool isBuyLimit  = (ot==ORDER_TYPE_BUY_LIMIT);
      bool isSellLimit = (ot==ORDER_TYPE_SELL_LIMIT);
      if(!isBuyLimit && !isSellLimit) continue;

      // 1) expiry
      if(InpPendingExpiryMin > 0)
      {
         datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         if(now - setup >= InpPendingExpiryMin * 60)
         {
            if(trade.OrderDelete(t))
               Notify(StringFormat("PENDING expired/cancelled #%I64u", t));
            continue;
         }
      }

      // 2) cancel when RSI returns to neutral (setup no longer valid)
      if(haveRSI)
      {
         if(isBuyLimit  && rsi >= InpRSICancelLevel)
         {
            if(trade.OrderDelete(t))
               Notify(StringFormat("PENDING BUY cancelled (RSI %.1f back to neutral) #%I64u", rsi, t));
         }
         else if(isSellLimit && rsi <= InpRSICancelLevel)
         {
            if(trade.OrderDelete(t))
               Notify(StringFormat("PENDING SELL cancelled (RSI %.1f back to neutral) #%I64u", rsi, t));
         }
      }
   }
}

//==================================================================
//  Lot sizing (risk-based, Cent aware)
//==================================================================
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
   for(int i=ArraySize(gPosTicket)-1; i>=0; i--)
   {
      if(!PositionSelectByTicket(gPosTicket[i]))
         RemovePosStateAt(i);
   }
}

//==================================================================
//  Management: profit-% close, break-even, ATR trailing
//==================================================================
void ManageOpenPositions()
{
   double atr = 0.0;
   bool   haveATR = (BufVal(hATRsl, 0, 1, atr) && atr > 0.0);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   for(int i=ArraySize(gPosTicket)-1; i>=0; i--)
   {
      ulong ticket = gPosTicket[i];
      if(!PositionSelectByTicket(ticket)) continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      bool   isBuy= (type==POSITION_TYPE_BUY);
      double cur  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                          : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitDist = isBuy ? (cur - open) : (open - cur);
      double R = gPosInitRisk[i];

      // ---- Profit target: close this order at X% of balance ----
      if(InpProfitClosePct > 0.0 && balance > 0.0)
      {
         double profitMoney = PositionGetDouble(POSITION_PROFIT) +
                              PositionGetDouble(POSITION_SWAP);
         double pct = profitMoney / balance * 100.0;
         if(pct >= InpProfitClosePct)
         {
            if(trade.PositionClose(ticket))
            {
               Notify(StringFormat("PROFIT-CLOSE #%I64u +%.2f%% of balance (%.2f)",
                                   ticket, pct, profitMoney));
               continue;   // position gone; state cleaned next SyncPositionState
            }
         }
      }

      if(R <= 0.0) continue;

      // ---- Break-even ----
      if(InpUseBreakEven && !gPosBEDone[i] && profitDist >= InpBreakEvenR * R)
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

      // ---- ATR trailing (SL follows volatility/strength) ----
      // strong/volatile move -> larger ATR -> SL trails wider (more room);
      // quiet move -> tighter trail. Only ever tightens (ModifySL guards).
      if(InpUseTrailing && haveATR && profitDist >= InpTrailStartR * R)
      {
         double trailDist = InpTrailATRMult * atr;
         double newSL = isBuy ? cur - trailDist : cur + trailDist;
         ModifySL(ticket, isBuy, newSL, sl);
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
   if(total <= 0) return false;

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
