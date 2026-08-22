// Minimal MQL5 -> C++ shim used only to syntax-check the EA source with g++.
#pragma once
#include <vector>
#include <string>
#include <cmath>
#include <cstdio>

typedef long long        datetime;
typedef unsigned int     color;
// ulong comes from <sys/types.h> on Linux
typedef unsigned int     uint;
typedef std::string      string;

#define INVALID_HANDLE (-1)
#define INIT_SUCCEEDED 0
#define INIT_FAILED 1
#define INIT_PARAMETERS_INCORRECT 2
#define PERIOD_CURRENT ((ENUM_TIMEFRAMES)0)

enum ENUM_TIMEFRAMES { PERIOD_M1=1, PERIOD_M5=5, PERIOD_M15=15, PERIOD_M30=30,
                       PERIOD_H1=60, PERIOD_H4=240, PERIOD_D1=1440 };
enum ENUM_LINE_STYLE  { STYLE_SOLID, STYLE_DASH, STYLE_DOT, STYLE_DASHDOT };
enum ENUM_ANCHOR_POINT{ ANCHOR_UPPER, ANCHOR_LOWER, ANCHOR_LEFT_UPPER, ANCHOR_RIGHT_UPPER };
enum ENUM_OBJECT      { OBJ_TREND, OBJ_TEXT };
enum ENUM_OBJPROP     { OBJPROP_COLOR, OBJPROP_WIDTH, OBJPROP_STYLE, OBJPROP_RAY_RIGHT,
                        OBJPROP_BACK, OBJPROP_SELECTABLE, OBJPROP_TEXT, OBJPROP_FONT,
                        OBJPROP_FONTSIZE, OBJPROP_ANCHOR };
enum ENUM_ORDER_TYPE  { ORDER_TYPE_BUY, ORDER_TYPE_SELL, ORDER_TYPE_BUY_LIMIT,
                        ORDER_TYPE_SELL_LIMIT, ORDER_TYPE_BUY_STOP, ORDER_TYPE_SELL_STOP };
enum ENUM_ORDER_TYPE_TIME { ORDER_TIME_GTC };
enum ENUM_POSITION_TYPE  { POSITION_TYPE_BUY, POSITION_TYPE_SELL };
enum ENUM_POS_PROP    { POSITION_MAGIC, POSITION_TYPE, POSITION_SYMBOL,
                        POSITION_PRICE_OPEN, POSITION_SL, POSITION_TP };
enum ENUM_ORD_PROP    { ORDER_MAGIC, ORDER_SYMBOL, ORDER_TYPE };
enum ENUM_SYM_PROP    { SYMBOL_POINT, SYMBOL_ASK, SYMBOL_BID, SYMBOL_DIGITS, SYMBOL_SPREAD,
                        SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX,
                        SYMBOL_VOLUME_STEP };
enum ENUM_ACC_PROP    { ACCOUNT_BALANCE };
enum ENUM_MQL_PROP    { MQL_TRADE_ALLOWED };
enum ENUM_TERM_PROP   { TERMINAL_TRADE_ALLOWED };

const color clrDodgerBlue=0, clrOrange=1, clrWhite=2, clrLime=3, clrSeaGreen=4, clrTomato=5;
extern string _Symbol;
extern int    _Period;

// --- math
inline double MathAbs(double v){ return std::fabs(v); }
inline double MathMin(double a,double b){ return a<b?a:b; }
inline double MathMax(double a,double b){ return a>b?a:b; }
inline double MathFloor(double v){ return std::floor(v); }
inline double MathRound(double v){ return std::round(v); }
inline double MathLog10(double v){ return std::log10(v); }
inline double NormalizeDouble(double v,int d){ (void)d; return v; }

// --- arrays (MQL dynamic arrays are mapped to std::vector by the transpiler)
template<class T> int  ArrayResize(std::vector<T>& a,int n){ a.resize(n); return n; }
template<class T> void ArrayFree(std::vector<T>& a){ a.clear(); }
template<class T> int  ArraySize(const std::vector<T>& a){ return (int)a.size(); }
template<class T> bool ArraySetAsSeries(std::vector<T>& a,bool s){ (void)a;(void)s; return true; }

// --- series access
int      Bars(string s, ENUM_TIMEFRAMES tf);
int      Bars(string s, ENUM_TIMEFRAMES tf, datetime a, datetime b);
int      CopyHigh(string s, ENUM_TIMEFRAMES tf,int start,int cnt,std::vector<double>& d);
int      CopyLow (string s, ENUM_TIMEFRAMES tf,int start,int cnt,std::vector<double>& d);
int      CopyTime(string s, ENUM_TIMEFRAMES tf,int start,int cnt,std::vector<datetime>& d);
int      CopyBuffer(int h,int buf,int start,int cnt,std::vector<double>& d);
datetime iTime (string s, ENUM_TIMEFRAMES tf,int i);
double   iOpen (string s, ENUM_TIMEFRAMES tf,int i);
double   iHigh (string s, ENUM_TIMEFRAMES tf,int i);
double   iLow  (string s, ENUM_TIMEFRAMES tf,int i);
double   iClose(string s, ENUM_TIMEFRAMES tf,int i);
int      iADX(string s, ENUM_TIMEFRAMES tf,int period);
bool     IndicatorRelease(int h);
int      PeriodSeconds(ENUM_TIMEFRAMES tf);

// --- symbol / account
double SymbolInfoDouble (string s, ENUM_SYM_PROP p);
long   SymbolInfoInteger(string s, ENUM_SYM_PROP p);
double AccountInfoDouble(ENUM_ACC_PROP p);
long   MQLInfoInteger(ENUM_MQL_PROP p);
long   TerminalInfoInteger(ENUM_TERM_PROP p);
bool   OrderCalcProfit(ENUM_ORDER_TYPE t,string s,double v,double open,double close,double& profit);

// --- positions / orders
int    PositionsTotal();
ulong  PositionGetTicket(int i);
long   PositionGetInteger(ENUM_POS_PROP p);
double PositionGetDouble (ENUM_POS_PROP p);
string PositionGetString (ENUM_POS_PROP p);
int    OrdersTotal();
ulong  OrderGetTicket(int i);
long   OrderGetInteger(ENUM_ORD_PROP p);
string OrderGetString (ENUM_ORD_PROP p);

// --- objects / output
bool ObjectCreate(long c,string n,ENUM_OBJECT t,int w,datetime t1,double p1,datetime t2=0,double p2=0);
bool ObjectDelete(long c,string n);
int  ObjectsDeleteAll(long c,string prefix,int sub=-1,int type=-1);
bool ObjectSetInteger(long c,string n,ENUM_OBJPROP p,long v);
bool ObjectSetString (long c,string n,ENUM_OBJPROP p,string v);
void ChartRedraw();
void Comment(string s);
void SendNotification(string s);
string EnumToString(ENUM_TIMEFRAMES v);

template<class...A> void Print(A&&...){}
template<class...A> void PrintFormat(const char*, A&&...){}
inline const char* FmtArg(const string& v){ return v.c_str(); }
template<class T> T FmtArg(T v){ return v; }
template<class...A> string StringFormat(const char* f, A&&...a)
{
   char buf[1024];
   snprintf(buf, sizeof(buf), f, FmtArg(a)...);
   return string(buf);
}

// --- CTrade
class CTrade
{
public:
   void   SetExpertMagicNumber(long m){(void)m;}
   void   SetTypeFillingBySymbol(string s){(void)s;}
   void   SetDeviationInPoints(int d){(void)d;}
   bool   Buy(double v,string s,double p,double sl,double tp,string c);
   bool   Sell(double v,string s,double p,double sl,double tp,string c);
   bool   BuyLimit(double v,double price,string s,double sl,double tp,
                   ENUM_ORDER_TYPE_TIME tt,datetime exp,string c);
   bool   SellLimit(double v,double price,string s,double sl,double tp,
                    ENUM_ORDER_TYPE_TIME tt,datetime exp,string c);
   bool   PositionModify(ulong t,double sl,double tp);
   bool   OrderDelete(ulong t);
   uint   ResultRetcode();
   string ResultRetcodeDescription();
   double ResultPrice();
};
