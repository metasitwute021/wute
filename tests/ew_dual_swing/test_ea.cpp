// Offline test harness for the Elliott Wave Dual Swing EA.
// Feeds a synthetic, textbook-clean 5-wave + a-b-c structure into the EA's
// own analysis chain and checks that both directions are detected.
#include "ea.cpp"
#include <iostream>
#include <iomanip>

//------------------------------------------------------------------
//  Synthetic series
//------------------------------------------------------------------
static std::vector<double>   gHi, gLo, gOp, gCl;
static std::vector<datetime> gTm;

string _Symbol = "TEST";
int    _Period = 60;

struct WP { int bar; double price; };

// Build a piecewise-linear path through the waypoints, one bar per step.
static void BuildSeries(const std::vector<WP>& wps, int total, bool mirror, double centre)
{
    gHi.assign(total, 0); gLo.assign(total, 0);
    gOp.assign(total, 0); gCl.assign(total, 0);
    gTm.assign(total, 0);

    for(int i = 0; i < total; i++)
    {
        // locate the segment containing bar i
        double val = wps.back().price;
        for(size_t k = 0; k + 1 < wps.size(); k++)
        {
            if(i >= wps[k].bar && i <= wps[k+1].bar)
            {
                double t = (wps[k+1].bar == wps[k].bar) ? 0.0
                         : double(i - wps[k].bar) / double(wps[k+1].bar - wps[k].bar);
                val = wps[k].price + t * (wps[k+1].price - wps[k].price);
                break;
            }
            if(i > wps.back().bar) val = wps.back().price;
        }
        if(mirror) val = 2.0 * centre - val;

        gOp[i] = val;
        gCl[i] = val;
        gHi[i] = val + 0.05;    // tiny wick, far below any deviation filter
        gLo[i] = val - 0.05;
        gTm[i] = 1700000000LL + (long long)i * 3600LL;
    }
}

//------------------------------------------------------------------
//  MQL runtime shims backed by the synthetic series
//------------------------------------------------------------------
int Bars(string, ENUM_TIMEFRAMES) { return (int)gHi.size(); }
int Bars(string, ENUM_TIMEFRAMES, datetime a, datetime b)
{
    int cnt = 0;
    for(size_t i = 0; i < gTm.size(); i++) if(gTm[i] >= a && gTm[i] <= b) cnt++;
    return cnt;
}

template<class T>
static int CopyVec(const std::vector<T>& src, int cnt, std::vector<T>& dst)
{
    int n = (int)src.size();
    if(cnt > n) cnt = n;
    dst.assign(src.end() - cnt, src.end());     // chronological, oldest first
    return cnt;
}
int CopyHigh(string, ENUM_TIMEFRAMES, int, int c, std::vector<double>& d){ return CopyVec(gHi, c, d); }
int CopyLow (string, ENUM_TIMEFRAMES, int, int c, std::vector<double>& d){ return CopyVec(gLo, c, d); }
int CopyTime(string, ENUM_TIMEFRAMES, int, int c, std::vector<datetime>& d){ return CopyVec(gTm, c, d); }
int CopyBuffer(int, int, int, int c, std::vector<double>& d){ d.assign(c, 30.0); return c; }

static int Shift(int i){ return (int)gHi.size() - 1 - i; }
datetime iTime (string, ENUM_TIMEFRAMES, int i){ return gTm[Shift(i)]; }
double   iOpen (string, ENUM_TIMEFRAMES, int i){ return gOp[Shift(i)]; }
double   iHigh (string, ENUM_TIMEFRAMES, int i){ return gHi[Shift(i)]; }
double   iLow  (string, ENUM_TIMEFRAMES, int i){ return gLo[Shift(i)]; }
double   iClose(string, ENUM_TIMEFRAMES, int i){ return gCl[Shift(i)]; }
int      iADX(string, ENUM_TIMEFRAMES, int){ return 1; }
bool     IndicatorRelease(int){ return true; }
int      PeriodSeconds(ENUM_TIMEFRAMES){ return 3600; }

double SymbolInfoDouble(string, ENUM_SYM_PROP p)
{
    switch(p)
    {
        case SYMBOL_POINT:      return 0.01;
        case SYMBOL_VOLUME_MIN: return 0.01;
        case SYMBOL_VOLUME_MAX: return 100.0;
        case SYMBOL_VOLUME_STEP:return 0.01;
        case SYMBOL_ASK:        return gCl.back() + 0.05;
        case SYMBOL_BID:        return gCl.back() - 0.05;
        default:                return 0.0;
    }
}
long SymbolInfoInteger(string, ENUM_SYM_PROP p)
{
    switch(p)
    {
        case SYMBOL_DIGITS:            return 2;
        case SYMBOL_SPREAD:            return 10;
        case SYMBOL_TRADE_STOPS_LEVEL: return 0;
        default:                       return 0;
    }
}
double AccountInfoDouble(ENUM_ACC_PROP){ return 10000.0; }
long   MQLInfoInteger(ENUM_MQL_PROP){ return 1; }
long   TerminalInfoInteger(ENUM_TERM_PROP){ return 1; }
bool   OrderCalcProfit(ENUM_ORDER_TYPE, string, double v, double o, double c, double& p)
{ p = (c - o) * v * 100.0; return true; }

int    PositionsTotal(){ return 0; }
ulong  PositionGetTicket(int){ return 0; }
long   PositionGetInteger(ENUM_POS_PROP){ return 0; }
double PositionGetDouble (ENUM_POS_PROP){ return 0.0; }
string PositionGetString (ENUM_POS_PROP){ return ""; }
int    OrdersTotal(){ return 0; }
ulong  OrderGetTicket(int){ return 0; }
long   OrderGetInteger(ENUM_ORD_PROP){ return 0; }
string OrderGetString (ENUM_ORD_PROP){ return ""; }

bool ObjectCreate(long, string, ENUM_OBJECT, int, datetime, double, datetime, double){ return true; }
bool ObjectDelete(long, string){ return true; }
int  ObjectsDeleteAll(long, string, int, int){ return 0; }
bool ObjectSetInteger(long, string, ENUM_OBJPROP, long){ return true; }
bool ObjectSetString (long, string, ENUM_OBJPROP, string){ return true; }
void ChartRedraw(){}
void Comment(string){}
void SendNotification(string){}
string EnumToString(ENUM_TIMEFRAMES){ return "TF"; }

bool   CTrade::Buy (double,string,double,double,double,string){ return false; }
bool   CTrade::Sell(double,string,double,double,double,string){ return false; }
bool   CTrade::BuyLimit (double,double,string,double,double,ENUM_ORDER_TYPE_TIME,datetime,string){ return false; }
bool   CTrade::SellLimit(double,double,string,double,double,ENUM_ORDER_TYPE_TIME,datetime,string){ return false; }
bool   CTrade::PositionModify(ulong,double,double){ return false; }
bool   CTrade::OrderDelete(ulong){ return false; }
uint   CTrade::ResultRetcode(){ return 0; }
string CTrade::ResultRetcodeDescription(){ return ""; }
double CTrade::ResultPrice(){ return 0.0; }


//------------------------------------------------------------------
//  Negative cases - the rules must actually reject broken structures
//------------------------------------------------------------------
static int failures = 0;

static void Check(const char* what, bool ok)
{
    std::cout << (ok ? "  PASS  " : "  FAIL  ") << what << "\n";
    if(!ok) failures++;
}

static void RunReject(const char* title, std::vector<WP> wps, bool mirror,
                      const char* expectStage)
{
    BuildSeries(wps, 175, mirror, 3100.0);
    gTF = PERIOD_H1;
    InpDirection = EW_DIR_BOTH;
    AnalyzeStructure();

    std::cout << title << "\n      note: " << gSetup.note << "\n";
    bool rejected = !gSetup.phase2 &&
                    gSetup.note.find(expectStage) != std::string::npos;
    Check(expectStage, rejected);
}

static void NegativeCases(bool mirror)
{
    // wave 3 is the shortest of 1/3/5  ->  Phase 1 must fail
    RunReject("  [n1] wave 3 shortest",
        { {0,3120.0},{40,3000.0},{50,3100.0},{60,3060.0},{75,3130.0},
          {85,3110.0},{95,3250.0},{105,3200.0},{115,3230.0},{130,3090.0},{170,3095.0} },
        mirror, "wave 3 is the shortest");

    // wave 2 retraces 95% of wave 1  ->  Phase 1 must fail
    RunReject("  [n2] wave 2 retraces 95%",
        { {0,3120.0},{40,3000.0},{50,3060.0},{60,3003.0},{75,3160.0},
          {85,3110.0},{95,3200.0},{105,3150.0},{115,3180.0},{130,3070.0},{170,3075.0} },
        mirror, "wave 2 retracement");

    // the pullback breaks past P0  ->  the whole setup must be dropped
    RunReject("  [n3] pullback breaks P0",
        { {0,3120.0},{40,3000.0},{50,3060.0},{60,3025.0},{75,3160.0},
          {85,3110.0},{95,3200.0},{105,3150.0},{115,3180.0},{130,2960.0},{170,2965.0} },
        mirror, "broke past P0");

    // pullback only 30% - valid structure but outside the entry zone
    BuildSeries({ {0,3120.0},{40,3000.0},{50,3060.0},{60,3025.0},{75,3160.0},
                  {85,3110.0},{95,3200.0},{105,3170.0},{115,3185.0},{130,3140.0},{170,3145.0} },
                175, mirror, 3100.0);
    gTF = PERIOD_H1; InpDirection = EW_DIR_BOTH;
    AnalyzeStructure();
    std::cout << "  [n4] shallow 30% pullback\n      note: " << gSetup.note << "\n";
    Check("shallow pullback flagged outside the entry zone", !gSetup.zoneOK);
}

//------------------------------------------------------------------
//  Test
//------------------------------------------------------------------
static void RunCase(const char* title, bool mirror, int expectDir)
{
    // textbook impulse P0 -> 1-2-3-4-5 -> a-b-c, pullback ends at 65% of P0->P1
    std::vector<WP> wps = {
        {  0, 3120.0},   // prior decline into P0
        { 40, 3000.0},   // P0   (major low)
        { 50, 3060.0},   // wave 1
        { 60, 3025.0},   // wave 2  (58% of wave 1)
        { 75, 3160.0},   // wave 3  (longest)
        { 85, 3110.0},   // wave 4  (no overlap into wave 2)
        { 95, 3200.0},   // wave 5 = P1 (major high)
        {105, 3150.0},   // a
        {115, 3180.0},   // b  (lower high)
        {130, 3070.0},   // c = P2 (65% retracement)
        {170, 3075.0}    // shallow drift, stays inside the major deviation
    };
    BuildSeries(wps, 175, mirror, 3100.0);

    gTF = PERIOD_H1;
    InpDirection = EW_DIR_BOTH;
    AnalyzeStructure();

    std::cout << title << "\n";
    std::cout << std::fixed << std::setprecision(2);
    std::cout << "  dir=" << gSetup.dir
              << " P0=" << gSetup.p0 << " P1=" << gSetup.p1 << " P2=" << gSetup.p2
              << " retr=" << gSetup.retrPct << "%\n"
              << "  note: " << gSetup.note << "\n";

    Check("direction detected",        gSetup.dir    == expectDir);
    Check("major swing found",         gSetup.majorOK);
    Check("Phase 1 (1-2-3-4-5) passed",gSetup.phase1);
    Check("Phase 2 (a-b-c) passed",    gSetup.phase2);
    Check("P2 inside the entry zone",  gSetup.zoneOK);
    Check("c recognised as P2",        gSetup.cEqualsP2);
    Check("retracement ~65%",          MathAbs(gSetup.retrPct - 65.0) < 1.0);

    // wave labels must be ordered with the trend
    int d = gSetup.dir;
    Check("waves 1..5 run with the trend",
          d*(gSetup.wPrice[1]-gSetup.wPrice[0]) > 0 &&
          d*(gSetup.wPrice[3]-gSetup.wPrice[1]) > 0 &&
          d*(gSetup.wPrice[5]-gSetup.wPrice[3]) > 0);

    // TP/SL must land on the correct side of the entry
    double entry = (d > 0 ? SymbolInfoDouble("", SYMBOL_ASK) : SymbolInfoDouble("", SYMBOL_BID));
    double sl    = ComputeSL(gSetup, entry);
    double tp    = ComputeTP(gSetup, entry);
    std::cout << "  entry=" << entry << " SL=" << sl << " TP=" << tp << "\n";
    Check("SL on the losing side of the entry", d*(entry - sl) > 0);
    Check("TP on the winning side of the entry", tp > 0 && d*(tp - entry) > 0);

    // pending ladder levels must sit between P1 and P0
    double rng = d * (gSetup.p1 - gSetup.p0);
    double lvl = gSetup.p1 - d * 0.618 * rng;
    Check("61.8% ladder level between P1 and P0",
          d*(gSetup.p1 - lvl) > 0 && d*(lvl - gSetup.p0) > 0);
}

int main()
{
    std::cout << "=== Elliott Wave Dual Swing - offline structure test ===\n\n";
    RunCase("[1] Bullish structure (expect BUY setup)",  false, +1);
    std::cout << "\n";
    RunCase("[2] Mirrored structure (expect SELL setup)", true, -1);

    std::cout << "\n[3] Negative cases - bullish side\n";
    NegativeCases(false);
    std::cout << "\n[4] Negative cases - mirrored (sell) side\n";
    NegativeCases(true);

    std::cout << "\n" << (failures == 0 ? "ALL CHECKS PASSED" : "FAILURES: ")
              << (failures ? std::to_string(failures) : "") << "\n";
    return failures == 0 ? 0 : 1;
}
