//+------------------------------------------------------------------+
//|                                            FF_News_Exporter.mq5   |
//|  Export MT5's built-in economic calendar to a CSV file that the   |
//|  Donchian EA can read during BACKTESTS (the live calendar is      |
//|  empty in the Strategy Tester, so we dump it to a file once).     |
//|                                                                    |
//|  HOW TO USE (run ONCE while the terminal is ONLINE):              |
//|   1) Put this file in  MQL5/Scripts/  and compile (F7).          |
//|   2) Make sure the News/Calendar is enabled and populated         |
//|      (open the "Calendar" tab once so MT5 downloads it).          |
//|   3) Drag the script onto any chart, set the date range +         |
//|      currency + impact, press OK.                                 |
//|   4) It writes the CSV into  MQL5/Files/  (default ff_news.csv).  |
//|   5) In the EA set InpUseFFNews=true and InpFFNewsFile to that    |
//|      name. Times are the SAME MT5 time base, so the EA's          |
//|      InpFFTimeOffsetHours can stay 0.                             |
//+------------------------------------------------------------------+
#property copyright "Metasit"
#property version   "1.00"
#property strict
#property script_show_inputs

input string   InpOutFile    = "ff_news.csv";     // output file (saved in MQL5/Files)
input datetime InpFrom       = D'2020.01.01 00:00'; // export FROM this date
input datetime InpTo         = D'2027.01.01 00:00'; // export TO this date
input string   InpCurrencies = "USD";             // currencies to keep (comma sep; "" = ALL)
input bool     InpHigh       = true;              // include HIGH impact (red)
input bool     InpMedium     = true;              // include MEDIUM impact (orange)
input bool     InpLow        = false;             // include LOW impact (yellow)

//--- true if 'val' is in a comma-separated list (case-insensitive)
bool InList(const string list, const string val)
{
   if(list == "") return true;       // empty list = accept all
   string parts[];
   int n = StringSplit(list, ',', parts);
   for(int i=0; i<n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p); StringTrimRight(p);
      if(StringCompare(p, val, false) == 0) return true;
   }
   return false;
}

void OnStart()
{
   int fh = FileOpen(InpOutFile, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(fh == INVALID_HANDLE)
   {
      Print("❌ Cannot create ", InpOutFile, "  err=", GetLastError());
      return;
   }
   FileWrite(fh, "Date", "Time", "Currency", "Impact", "Title");   // header (EA skips it)

   int written = 0, scanned = 0;

   // Pull in ~1-year chunks (robust for long ranges).
   datetime chunkStart = InpFrom;
   while(chunkStart < InpTo)
   {
      datetime chunkEnd = chunkStart + (datetime)(370*24*3600);
      if(chunkEnd > InpTo) chunkEnd = InpTo;

      MqlCalendarValue values[];
      int total = CalendarValueHistory(values, chunkStart, chunkEnd, NULL, NULL);
      if(total <= 0)
         Print("⚠️ No calendar data for ", TimeToString(chunkStart, TIME_DATE),
               " .. ", TimeToString(chunkEnd, TIME_DATE),
               " (is the terminal online & calendar enabled?)");

      for(int i=0; i<total; i++)
      {
         scanned++;
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev)) continue;

         string imp = "";
         if(ev.importance == CALENDAR_IMPORTANCE_HIGH)          { if(!InpHigh)   continue; imp = "High";   }
         else if(ev.importance == CALENDAR_IMPORTANCE_MODERATE) { if(!InpMedium) continue; imp = "Medium"; }
         else if(ev.importance == CALENDAR_IMPORTANCE_LOW)      { if(!InpLow)    continue; imp = "Low";    }
         else continue;   // CALENDAR_IMPORTANCE_NONE -> skip (holidays / no-impact)

         MqlCalendarCountry country; string ccy = "";
         if(CalendarCountryById(ev.country_id, country)) ccy = country.currency;
         if(!InList(InpCurrencies, ccy)) continue;

         datetime t = values[i].time;
         if(t <= 0) continue;

         MqlDateTime d; TimeToStruct(t, d);
         string dateStr = StringFormat("%04d.%02d.%02d", d.year, d.mon, d.day);
         string timeStr = StringFormat("%02d:%02d", d.hour, d.min);
         string title   = ev.name;
         StringReplace(title, ",", " ");   // keep the CSV clean

         FileWrite(fh, dateStr, timeStr, ccy, imp, title);
         written++;
      }
      chunkStart = chunkEnd;
   }

   FileClose(fh);
   string msg = StringFormat("✅ FF export done: %d events -> MQL5/Files/%s  (scanned %d)",
                             written, InpOutFile, scanned);
   Print(msg);
   Alert(msg);
}
//+------------------------------------------------------------------+
