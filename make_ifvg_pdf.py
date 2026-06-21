#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate a mobile-friendly PDF that explains the IFVG+ EA code structure."""

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table,
                                TableStyle, HRFlowable)

# --- Thai-capable TrueType fonts (FreeSerif covers Thai) ---
FT = "/usr/share/fonts/truetype/freefont/"
pdfmetrics.registerFont(TTFont("Thai", FT + "FreeSerif.ttf"))
pdfmetrics.registerFont(TTFont("Thai-Bold", FT + "FreeSerifBold.ttf"))
pdfmetrics.registerFont(TTFont("Thai-Italic", FT + "FreeSerifItalic.ttf"))
pdfmetrics.registerFontFamily("Thai", normal="Thai", bold="Thai-Bold",
                              italic="Thai-Italic", boldItalic="Thai-Bold")

GOLD = colors.HexColor("#b8860b")
DARKGOLD = colors.HexColor("#8a6508")
HEADBG = colors.HexColor("#f3e6c4")
HEADTX = colors.HexColor("#5c4500")
ROWALT = colors.HexColor("#fbf7ec")
GRID = colors.HexColor("#d9c189")
BOXBG = colors.HexColor("#fff8e6")
WARNBG = colors.HexColor("#fdecea")
WARNBD = colors.HexColor("#e6a79a")
CODEBG = colors.HexColor("#f4f4f4")
CODEBD = colors.HexColor("#cccccc")

styles = getSampleStyleSheet()


def S(name, **kw):
    base = dict(fontName="Thai", fontSize=11, leading=16,
                textColor=colors.HexColor("#1a1a1a"))
    base.update(kw)
    return ParagraphStyle(name, **base)


title = S("title", fontName="Thai-Bold", fontSize=22, leading=26, textColor=GOLD)
sub = S("sub", fontSize=11, leading=15, textColor=colors.HexColor("#666666"))
h2 = S("h2", fontName="Thai-Bold", fontSize=15, leading=20, textColor=DARKGOLD,
       spaceBefore=16, spaceAfter=4)
body = S("body", fontSize=11, leading=16)
cell = S("cell", fontSize=10.5, leading=14)
cellb = S("cellb", fontName="Thai-Bold", fontSize=10.5, leading=14)
head = S("head", fontName="Thai-Bold", fontSize=10.5, leading=14, textColor=HEADTX)
codest = S("code", fontName="Courier", fontSize=9, leading=12,
           textColor=colors.HexColor("#222222"))
center = S("center", fontSize=11, leading=15, alignment=TA_CENTER,
           textColor=colors.HexColor("#666666"))


def P(t, st=body):
    return Paragraph(t, st)


def tbl(header_cells, body_rows, col_widths):
    data = [[P(c, head) for c in header_cells]]
    for r in body_rows:
        data.append([P(c[2:], cellb) if c.startswith("**") else P(c, cell)
                     for c in r])
    t = Table(data, colWidths=col_widths, repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), HEADBG),
        ("GRID", (0, 0), (-1, -1), 0.6, GRID),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
    ]
    for i in range(1, len(data)):
        if i % 2 == 0:
            style.append(("BACKGROUND", (0, i), (-1, i), ROWALT))
    t.setStyle(TableStyle(style))
    return t


def box(flowables, bg, border):
    inner = Table([[f] for f in flowables], colWidths=[170 * mm])
    inner.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), bg),
        ("BOX", (0, 0), (-1, -1), 0.8, border),
        ("LEFTPADDING", (0, 0), (-1, -1), 12),
        ("RIGHTPADDING", (0, 0), (-1, -1), 12),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    return inner


def codebox(lines):
    flow = [P(ln.replace(" ", "&nbsp;"), codest) for ln in lines]
    inner = Table([[f] for f in flow], colWidths=[170 * mm])
    inner.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), CODEBG),
        ("BOX", (0, 0), (-1, -1), 0.6, CODEBD),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    return inner


story = []
story.append(P("IFVG+ EA — โครงสร้างโค้ด", title))
story.append(Spacer(1, 2))
story.append(HRFlowable(width="100%", thickness=2.5, color=GOLD, spaceAfter=6))
story.append(P("สรุปหน้าที่แต่ละส่วนของไฟล์ <b>IFVG_Plus_EA.mq5</b><br/>"
               "Inversion Fair Value Gap Expert Advisor · MetaTrader 5 · เวอร์ชัน 1.00", sub))
story.append(Spacer(1, 8))
story.append(box([P("<b>ภาพรวม:</b> เปรียบ EA เป็น “พนักงานเทรด 1 คน” ที่มีหน้าที่ย่อยหลายอย่าง "
                    "หัวใจคือการหาช่องว่างราคา (FVG) แล้วรอให้ราคา “ปิดทะลุกลับ” (Inversion) "
                    "จึงเข้าเทรด ตั้ง SL ใต้แท่งที่ 3 ไม่มี TP ปล่อยกำไรวิ่งด้วย trailing "
                    "พร้อมระบบป้องกันพอร์ตและการวาดกล่อง FVG บนกราฟ", body)], BOXBG, GRID))

story.append(P("โค้ดแบ่งเป็น 7 กลุ่มใหญ่", h2))
story.append(tbl(["กลุ่ม", "หน้าที่โดยรวม"], [
    ["**1. Inputs", "ปุ่มตั้งค่า — ปรับได้โดยไม่ต้องแก้โค้ด"],
    ["**2. Globals", "สมุดจดความจำของ EA ระหว่างทำงาน"],
    ["**3. วงจรชีวิต", "OnInit / OnTick / OnTimer / OnDeinit"],
    ["**4. IFVG Engine", "สมองหาสัญญาณเข้าเทรด (หัวใจ)"],
    ["**5. วาดกล่อง", "แสดง FVG และลูกศรบนกราฟ"],
    ["**6. ระบบป้องกัน", "Drawdown / ข่าว / ประตูอนุญาตเทรด"],
    ["**7. บริหารไม้", "Lot / SL / Trailing / ปิดบางส่วน"],
], [46 * mm, 124 * mm]))

story.append(P("1. Inputs — ปุ่มตั้งค่า", h2))
story.append(P("ส่วนที่ขึ้นต้นด้วย <font name='Courier'>input</font> คือค่าที่ปรับได้จากหน้าต่าง EA "
               "ตอนลากใส่กราฟ โดยไม่ต้องแก้โค้ด", body))
story.append(tbl(["กลุ่ม Input", "คุมอะไร"], [
    ["**General / Timeframes", "Magic number, แจ้งเตือน, ไทม์เฟรมสัญญาณ (M15) และเทรล (M5)"],
    ["**IFVG detection", "ช่องกว้างกี่จุด, แท่งกลางแรงแค่ไหน, FVG อายุกี่แท่งถึงทิ้ง"],
    ["**'+' filters", "ฟิลเตอร์เสริม: เทรนด์ EMA และเซสชันเวลา"],
    ["**Risk / Management", "ความเสี่ยง%, buffer SL, Break-even, ปิดบางส่วน"],
    ["**Trailing / DD / News", "ตั้งค่าเทรล, เพดาน Drawdown, กรองข่าว"],
    ["**Visualization", "สีกล่อง, เปิด/ปิดการวาดกล่องและลูกศร"],
], [50 * mm, 120 * mm]))

story.append(P("2. Globals — สมุดความจำ", h2))
story.append(tbl(["ตัวแปร", "เก็บอะไร"], [
    ["**trade", "เครื่องมือส่งคำสั่งซื้อขาย"],
    ["**hEMA, hATR...", "ตัวเชื่อมไปอ่านค่าอินดิเคเตอร์"],
    ["**gZones[]", "★ ลิสต์ FVG ที่เจอแล้วแต่ยังไม่ inversion (รออยู่)"],
    ["**gPosTicket[]...", "จำสถานะไม้ที่เปิด (เคย BE แล้วยัง? ปิดบางส่วนยัง?)"],
    ["**gPeakEquity, gInNews...", "สถานะระบบป้องกัน (DD / ข่าว / หยุดรายวัน)"],
], [50 * mm, 120 * mm]))

story.append(P("3. วงจรชีวิต — หัวใจการหมุนเวลา", h2))
story.append(tbl(["ฟังก์ชัน", "ทำงานเมื่อ", "หน้าที่"], [
    ["**OnInit()", "ลาก EA ใส่กราฟ", "สร้างอินดิเคเตอร์, ตั้งนาฬิกา, เคลียร์กล่องเก่า"],
    ["**OnTick()", "ทุกครั้งราคาขยับ", "จัดการไม้ที่เปิด + หาสัญญาณใหม่เมื่อขึ้นแท่งใหม่"],
    ["**OnTimer()", "ทุก 5 วินาที", "เช็ค Drawdown + สถานะข่าว"],
    ["**OnDeinit()", "ถอด EA ออก", "ลบกล่อง/ลูกศร, คืนหน่วยความจำ"],
], [30 * mm, 38 * mm, 102 * mm]))
story.append(Spacer(1, 3))
story.append(P("จุดสำคัญใน OnTick: ทำงาน 2 จังหวะ — (1) ทุก tick จัดการไม้ที่เปิด (เทรล/BE) "
               "(2) เฉพาะแท่งใหม่ ค่อยหาสัญญาณเข้า เพื่อไม่คำนวณซ้ำเกินจำเป็น", sub))

story.append(P("4. IFVG Engine — สมองหาสัญญาณ (หัวใจ)", h2))
story.append(tbl(["ฟังก์ชัน", "หน้าที่อธิบายง่าย ๆ"], [
    ["**DetectNewFVG()", "มอง 3 แท่งล่าสุด — ถ้าหาง Low แท่งซ้ายไม่ทับหัว High แท่งขวา = เจอช่องว่าง → จดลง gZones[] (เช็คก่อนว่าช่องกว้างพอ + แท่งกลางแรงพอ)"],
    ["**ScanForInversion()", "ไล่ดู FVG ที่จดไว้ — ถ้าราคาปิดทะลุกลับผ่านช่อง = inversion → ส่งไปเข้าเทรด"],
    ["**PassesPlusFilters()", "ก่อนเข้าจริง เช็ค “+” : อยู่ฝั่งเดียวกับเทรนด์ EMA ไหม? อยู่ในเซสชันไหม?"],
    ["**AgeAndPruneZones()", "นับอายุ FVG — ถ้าเก่าเกินไป หรือราคาทะลุผิดทาง = ลบทิ้ง"],
], [46 * mm, 124 * mm]))

story.append(P("5. การวาดกล่อง — แสดงผลบนกราฟ", h2))
story.append(tbl(["ฟังก์ชัน", "หน้าที่"], [
    ["**DrawZone()", "วาดกล่องคลุมโซน FVG (แดง=รอ Buy / ฟ้า=รอ Sell)"],
    ["**ExtendZones()", "ยืดขอบขวากล่องตามเวลาจริงตราบใดที่ FVG ยังไม่ถูกใช้"],
    ["**DrawEntryArrow()", "ปักลูกศรเขียว/แดงตรงจุดเข้าไม้"],
    ["**DeleteAllObjects()", "ลบกล่อง/ลูกศรทั้งหมด"],
], [46 * mm, 124 * mm]))

story.append(P("6. ระบบป้องกัน — ยามเฝ้าประตู", h2))
story.append(tbl(["ฟังก์ชัน", "หน้าที่"], [
    ["**CheckDrawdownProtection()", "ขาดทุนรวม 20% → พัก EA / ขาดทุนวันละ 1.5% → หยุดทั้งวัน"],
    ["**IsNewsBlocking()", "เช็คปฏิทินข่าว — ใกล้ข่าวแรง ±30 นาที = ห้ามเข้าไม้"],
    ["**TradingAllowed()", "★ ประตูสุดท้าย รวมทุกเงื่อนไข ถ้าไม่ผ่าน EA ไม่เข้าเทรดเด็ดขาด"],
    ["**CountMyPositions()", "นับไม้ของ EA ตัวนี้ที่เปิดอยู่"],
], [55 * mm, 115 * mm]))

story.append(P("7. บริหารไม้ — เมื่อเข้าเทรดแล้วทำอะไรต่อ", h2))
story.append(tbl(["ฟังก์ชัน", "หน้าที่"], [
    ["**OpenTrade()", "ส่งคำสั่ง Buy/Sell จริง พร้อมตั้ง SL (ไม่มี TP)"],
    ["**CalcLotSize()", "★ คำนวณ Lot จาก Risk% ÷ ระยะ SL (รองรับพอร์ต Cent อัตโนมัติ)"],
    ["**NormalizeVolume()", "ปัด Lot ให้ตรงขั้นต่ำของโบรกเกอร์"],
    ["**SyncPositionState()", "อัปเดตลิสต์ไม้ที่เปิด/ปิด"],
    ["**ManageOpenPositions()", "★ ทุก tick: เลื่อน BE → ปิดบางส่วน 40% ที่ 1R → เทรล"],
    ["**ComputeTrailingSL()", "หา SL เทรล “ปลอดภัยที่สุด” จากหลายชั้น (ATR + swing + แท่งที่ 3)"],
    ["**ModifySL()", "ขยับ SL ได้เฉพาะทางแน่นขึ้น ห้ามถอยหลัง"],
], [52 * mm, 118 * mm]))

story.append(P("สรุปการไหลของงาน (1 รอบสมบูรณ์)", h2))
story.append(codebox([
    "ราคาขยับ -> OnTick",
    "   |- ManageOpenPositions()   (มีไม้อยู่? เทรล/BE/ปิดบางส่วน)",
    "   |- ขึ้นแท่งใหม่?",
    "        |- AgeAndPruneZones()  (เก็บกวาด FVG เก่า)",
    "        |- DetectNewFVG()      (เจอช่องใหม่? จดไว้ + วาดกล่อง)",
    "        |- ScanForInversion()  (ราคาทะลุกลับ? -> เข้าไม้ + ปักลูกศร)",
    "        |- ExtendZones()       (ยืดกล่องที่ยังรออยู่)",
]))

story.append(Spacer(1, 8))
story.append(box([
    P("<b>ข้อควรทราบ</b>", body),
    P("• ค่าเริ่มต้นตั้งไว้สำหรับ XAUUSD M15 — ควรจูน MinGap / Displacement / MaxAge "
      "ด้วย Backtest ให้เข้ากับโบรกเกอร์ก่อนใช้จริง", body),
    P("• News filter มักไม่ทำงานใน Strategy Tester (เมื่อดึงปฏิทินไม่ได้ EA จะไม่บล็อก)", body),
    P("• การลงทุนมีความเสี่ยง ทดสอบบนบัญชีเดโมก่อนใช้งานจริงเสมอ", body),
], WARNBG, WARNBD))

story.append(Spacer(1, 14))
story.append(P("IFVG+ EA v1.00 — IFVG_Plus_EA.mq5", center))


doc = SimpleDocTemplate("/home/user/wute/IFVG_Plus_EA_Guide.pdf",
                        pagesize=A4,
                        leftMargin=20 * mm, rightMargin=20 * mm,
                        topMargin=18 * mm, bottomMargin=16 * mm,
                        title="IFVG+ EA Code Guide")
doc.build(story)
print("PDF written")
