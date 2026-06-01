#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate a mobile-friendly PDF guide for the XAUUSD Donchian EA."""

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

styles = getSampleStyleSheet()


def S(name, **kw):
    base = dict(fontName="Thai", fontSize=11, leading=16, textColor=colors.HexColor("#1a1a1a"))
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
center = S("center", fontSize=11, leading=15, alignment=TA_CENTER, textColor=colors.HexColor("#666666"))


def P(t, st=body):
    return Paragraph(t, st)


def make_table(rows, col_widths, header=True, spans=None):
    data = []
    for r in rows:
        data.append([P(c, head) if (header and i == 0 and rows.index(r) == 0) else c
                     for i, c in enumerate(r)])
    # build directly instead (above index() is fragile); rebuild properly below
    return None


def tbl(header_cells, body_rows, col_widths, full_rows=None):
    data = [[P(c, head) for c in header_cells]]
    for r in body_rows:
        data.append([P(c, cell) if not c.startswith("**") else P(c[2:], cellb) for c in r])
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


story = []
story.append(P("XAUUSD Donchian Trend EA", title))
story.append(Spacer(1, 2))
story.append(HRFlowable(width="100%", thickness=2.5, color=GOLD, spaceAfter=6))
story.append(P("คู่มือ Expert Advisor สำหรับ MetaTrader 5 — เทรดทองคำ (XAUUSD)<br/>"
               "สัญญาณบน H4 · จัดการไม้บน M30 · เวอร์ชัน 1.00", sub))
story.append(Spacer(1, 8))
story.append(box([P("<b>ภาพรวม:</b> EA เข้าสัญญาณตามการทะลุกรอบ Donchian บนกราฟ H4 "
                    "กรองด้วยเทรนด์ (SMA 50) และความแรงเทรนด์ (ADX) จัดการความเสี่ยงด้วย "
                    "ล็อตตามความเสี่ยง 1% ต่อไม้ ไม่ตั้ง TP แต่ปล่อยกำไรวิ่งด้วยระบบ trailing "
                    "หลายชั้น พร้อมระบบป้องกันพอร์ตและระบบปรับขนาดล็อตตามฟอร์มล่าสุด", body)],
                 BOXBG, GRID))

story.append(P("1. กลยุทธ์การเทรด", h2))
story.append(tbl(["หัวข้อ", "รายละเอียด"], [
    ["**ตลาด / กรอบเวลา", "XAUUSD — สัญญาณบน H4, จัดการ trailing บน M30"],
    ["**การเข้า", "Donchian Channel (20): ราคาปิดทะลุกรอบบน = Buy, ทะลุกรอบล่าง = Sell"],
    ["**ตัวกรอง", "ราคาต้องอยู่ฝั่งเดียวกับเทรนด์ SMA(50) และ ADX(14) ต้องมากกว่า 20"],
    ["**ขนาดล็อต", "คำนวณจากความเสี่ยง 1% ของพอร์ตเทียบระยะ SL — รองรับบัญชี Cent"],
    ["**การออก", "ไม่ตั้ง TP — มีแต่ SL แล้วปล่อยกำไรวิ่งด้วย trailing ล้วน"],
], [42 * mm, 128 * mm]))

story.append(P("2. การจัดการไม้", h2))
story.append(tbl(["กลไก", "เงื่อนไข"], [
    ["**Break-Even", "เลื่อน SL มาที่จุดเข้า (+buffer) เมื่อกำไรถึง 0.25R"],
    ["**Partial Close", "ปิด 40% ของไม้เมื่อกำไรถึง 1R"],
    ["**Trailing ชั้นหลัก", "ATR(18) × 5.75"],
    ["Strong Move", "ATR(12) × 2.75"],
    ["Mini Strong Move", "ATR(16) × 2.0"],
    ["Swing", "Swing high / low ล่าสุด"],
    ["โครงสร้างแท่ง", "High / Low ของแท่งเทียนที่ 3"],
], [42 * mm, 128 * mm]))
story.append(Spacer(1, 3))
story.append(P("Trailing ทุกชั้นทำงานพร้อมกัน เลือก SL ที่ปลอดภัยที่สุด (ป้องกันกำไรมากสุด) "
               "และเลื่อนทางเดียวเท่านั้น &nbsp; · &nbsp; R = ระยะความเสี่ยงเริ่มต้น "
               "(จุดเข้าถึง SL แรก)", sub))

story.append(P("3. ระบบป้องกันพอร์ต", h2))
story.append(tbl(["ระบบ", "การทำงาน"], [
    ["**Max Drawdown 20%", "หยุด EA แบบเรียลไทม์ และกลับมารันอัตโนมัติเมื่อ DD ลดลงต่ำกว่าเกณฑ์ (มี buffer กันเด้ง)"],
    ["**Daily Drawdown 1.5%", "หยุดเปิดไม้ใหม่ตลอดวันนั้น แล้วรีเซ็ตเมื่อขึ้นวันใหม่"],
    ["**News Filter", "งดเทรด ±90 นาที รอบข่าว High impact (ใช้ปฏิทินเศรษฐกิจของ MT5 — ค่าเริ่มต้น USD,XAU)"],
], [42 * mm, 128 * mm]))

story.append(P("4. Confidence System (ปรับขนาดล็อตตามฟอร์ม)", h2))
story.append(P("ปรับขนาดล็อต <b>0.5x – 2.0x</b> โดยพิจารณาจาก win rate และ profit factor "
               "ของ <b>10 ไม้ล่าสุด</b> และทำให้ค่านุ่มนวลด้วย smoothing factor "
               "<b>0.25</b> (EMA) เพื่อไม่ให้ล็อตกระโดดแรงเกินไป", body))
story.append(tbl(["สถานการณ์", "ผลต่อขนาดล็อต"], [
    ["ฟอร์มดี (ชนะบ่อย + PF สูง)", "เพิ่มเข้าใกล้ 2.0x"],
    ["ฟอร์มแย่", "ลดเข้าใกล้ 0.5x"],
    ["ประวัติน้อยกว่า 3 ไม้", "ใช้ตัวคูณกลาง 1.0x"],
], [70 * mm, 100 * mm]))

story.append(P("5. การแจ้งเตือน (Push Notification)", h2))
story.append(P("ส่ง push notification ทุก event: เปิดไม้ · ปิดไม้ · ปิดบางส่วน · ตั้ง Break-Even · "
               "เตือน Drawdown · ข่าวเปิด/ปิด · EA start/stop", body))
story.append(Spacer(1, 4))
story.append(box([P("ต้องตั้งค่า <b>MetaQuotes ID</b> ที่ <i>Tools → Options → Notifications</i> "
                    "ในโปรแกรม MT5 ก่อน จึงจะได้รับแจ้งเตือนบนมือถือ", body)], WARNBG, WARNBD))

story.append(P("6. พารามิเตอร์หลัก (Inputs)", h2))
story.append(tbl(["กลุ่ม", "พารามิเตอร์", "ค่าเริ่มต้น"], [
    ["ทั่วไป", "Magic number", "990201"],
    ["ทั่วไป", "Cent account", "false"],
    ["ตัวกรอง", "Donchian period", "20"],
    ["ตัวกรอง", "SMA period", "50"],
    ["ตัวกรอง", "ADX period / ขั้นต่ำ", "14 / 20"],
    ["ความเสี่ยง", "Risk per trade", "1.0%"],
    ["ความเสี่ยง", "Initial SL = ATR(14) ×", "2.0"],
    ["จัดการไม้", "Break-even R", "0.25"],
    ["จัดการไม้", "Partial R / %", "1.0 / 40%"],
    ["Trailing", "ATR 18 / 12 / 16 ×", "5.75 / 2.75 / 2.0"],
    ["Trailing", "Swing lookback / แท่งที่", "20 / 3"],
    ["ป้องกัน", "Max DD / Daily DD", "20% / 1.5%"],
    ["ข่าว", "นาทีก่อน / หลัง", "90 / 90"],
    ["Confidence", "ไม้ / Min / Max / Smooth", "10 / 0.5 / 2.0 / 0.25"],
], [32 * mm, 88 * mm, 50 * mm]))

story.append(P("7. การติดตั้ง", h2))
story.append(tbl(["ขั้นตอน", "รายละเอียด"], [
    ["**1", "คัดลอกไฟล์ XAUUSD_Donchian_EA.mq5 ไปไว้ในโฟลเดอร์ MQL5/Experts/"],
    ["**2", "เปิดใน MetaEditor แล้วกด Compile (F7)"],
    ["**3", "ลาก EA ลงกราฟ XAUUSD H4 และเปิด Algo Trading"],
], [20 * mm, 150 * mm]))

story.append(Spacer(1, 6))
story.append(box([
    P("<b>ข้อควรทราบ</b>", body),
    P("• โค้ดเขียนตาม API มาตรฐาน MQL5 — ควร Compile (F7) ใน MetaEditor เพื่อยืนยันขั้นสุดท้าย", body),
    P("• News filter ต้องมีปฏิทินเศรษฐกิจจากโบรกเกอร์ และมักไม่ทำงานใน Strategy Tester "
      "(เมื่อดึงข้อมูลไม่ได้ EA จะไม่บล็อกการเทรด)", body),
    P("• การลงทุนมีความเสี่ยง ควรทดสอบบนบัญชีเดโมก่อนใช้งานจริงเสมอ", body),
], WARNBG, WARNBD))

story.append(Spacer(1, 14))
story.append(P("XAUUSD Donchian EA v1.00", center))


doc = SimpleDocTemplate("/home/user/wute/XAUUSD_Donchian_EA_Guide.pdf",
                        pagesize=A4,
                        leftMargin=20 * mm, rightMargin=20 * mm,
                        topMargin=18 * mm, bottomMargin=16 * mm,
                        title="XAUUSD Donchian EA Guide")
doc.build(story)
print("PDF written")
