# IFVG+ EA — จุดที่ต้องเพิ่ม + บทเรียนที่เรียนมา

> เอกสารส่งต่อ (handoff spec) สำหรับพัฒนา IFVG+ EA ให้ปลอดภัย + พร้อมใช้กับบัญชีสอบกองทุน
> สรุปจากการพัฒนา EA ทอง (Donchian) ร่วมกัน

---

## ส่วน A — จุดที่ "ขาด" ต้องเพิ่ม

### 🔴 A1. Risk Cap / Lot Safety (สำคัญสุด — กันแตก)

เพิ่มใน `CalcLotSize()`:

```mql5
input double InpMaxRiskCapPercent = 1.7;  // skip ถ้า min-lot เสี่ยงเกิน %นี้ (0 = ไม่ skip)

// หลังคำนวณ lot (lotsFinal) แล้ว ก่อน return:
double lossAtLot = lossPerLot * lotsFinal;
double riskPct   = (balance > 0.0) ? lossAtLot / balance * 100.0 : 0.0;
if(InpMaxRiskCapPercent > 0.0 && riskPct > InpMaxRiskCapPercent)
    return 0.0;   // เสี่ยงเกินเพดาน -> ไม่เปิดไม้ (OpenTrade เห็น lot=0 จะข้าม)
```

**เหตุผล:** กันลอตบาน / บัญชีเล็กเกินไป → ไม่แตกแบบ KRV เก่า (-104%)
ไม้เดียวจะ "ทำให้สอบตก" ไม่ได้เด็ดขาด

---

### 🔴 A2. DD Protection แบบ Prop (แก้ค่า 20% ที่หลวมเกินไป!)

ปัญหา: ไฟล์เดิมตั้ง "ขาดทุนรวม 20% → พัก" — **ใช้กับกองทุนไม่ได้** เพราะเส้นตาย = 5% (สอบตกไปก่อนถึง 20%)

เพิ่ม/แก้ inputs + เรียกเช็กใน `OnTick()`:

```mql5
input double InpProfitTargetPercent = 6.0;   // ถึง +6% -> ปิดหมด + STOP
input double InpMaxTotalLossPercent = 3.5;   // EMERGENCY BRAKE: -3.5% -> ปิดหมด + STOP (hard)
input double InpMaxDD_Percent        = 3.0;   // Max DD pause (ไม่ใช่ 20!)
input double InpDailyDD_Percent      = 1.5;   // รายวัน

// CheckProfitTarget():   equity >= startBalance * (1 + 6%)   -> CloseAll + stop
// CheckEmergencyBrake(): equity <= startBalance * (1 - 3.5%) -> CloseAll + stop
// (เรียกทั้งคู่ต้นๆ ของ OnTick ก่อนหาสัญญาณ)
```

**เหตุผล:** เส้นตายกองทุน = 5% STATIC จากเงินตั้งต้น
→ brake 3.5% หยุดก่อน + เหลือ buffer ~1.5% (กัน slippage/gap)

---

### 🟡 A3. เล็กน้อย (ถ้ามีเวลา)

- เช็ก **spread** ก่อน `OpenTrade()` (ทอง spread แกว่ง โดยเฉพาะช่วงข่าว)
- **Re-entry cooldown** 1 แท่ง หลังปิดไม้ (กัน whipsaw) — IFVG อาจไม่จำเป็น

---

## ส่วน B — บทเรียนที่เรียนมา (ต้องยึด!)

### 💰 B1. Money Management
- ✅ **Fix Risk %** เท่านั้น (Sharpe ดีสุด — KRV พิสูจน์ในคลิป, เราใช้)
- ❌ **ห้าม Martingale** (เบิ้ลหลังแพ้ = ล้างพอร์ตแน่นอน)
- ❌ **ห้าม Anti-Martingale / Confidence system** (ขยายลอตหลังชนะ)
  → เราเทสเองพบว่า**ฉุดผลงาน** (PF 0.80 ตอนเปิด vs 1.11 ตอนปิด)
  → ต่อให้ใส่ "ประตูกรอง" (gate) ก็ไม่ช่วย (ยังได้ PF 0.80)

### 🛡️ B2. ความปลอดภัย (Lot Safety)
- **Risk cap = หัวใจกันแตก** — KRV เก่าไม่มี → แตก -104% / เรามี → รอด
- **เกราะ DD ต้องแน่นพอกับเส้นกองทุน** (brake < 5%, มี buffer)

### 📊 B3. การทดสอบ (Backtest)
- **Backtest ยาว 6.5 ปี** (หลายสภาพตลาด: COVID, ขึ้นดอกเบี้ย, ฯลฯ) ก่อนเชื่อ
- ⚠️ **Backtest สั้นหลอกตา!** — 4 เดือนเราได้ PF 7.3 / win 95% แต่จริงๆ 6.5 ปี = PF 1.2 / win 60%
- ดู **PF + Max DD + R:R** ไม่ใช่แค่กำไร
- เป้าหมาย: **PF > 1.2, Max DD ต่ำ, R:R >= 1**

### 🎯 B4. R:R (Risk:Reward)
- อย่าตัด winner เร็ว → **ปล่อยให้วิ่ง** (เราเจอ Partial 1R→2R ทำให้ PF 1.11→1.22, DD ลด)
- กำไรเฉลี่ยต้องไม่เล็กกว่าขาดทุนเฉลี่ยมาก (ไม่งั้น win rate สูงก็ยังขาดทุน)

### 📰 B5. ข่าว & Gap
- News filter จับได้แค่ **ข่าวในตาราง HIGH (★★★)** (เช่น NFP, CPI, FOMC)
- **ข่าวด่วน/สุดสัปดาห์ (สงคราม, ทรัมป์เสาร์-อาทิตย์) จับไม่ได้** → **SL คือเกราะจริง**
- พิจารณา **Weekend Guard** (ปิดไม้ก่อนเสาร์-อาทิตย์ กัน Monday gap)

### 🧠 B6. วินัย (KRV ย้ำเอง)
- สูตรอยู่รอด = **ระบบ EV บวก + Money Management ดี + วินัย (ไม่ override)**
- อย่าจิ้ม / อย่าเลื่อน SL เอง / อย่าเทรดตามข่าว / อย่ารีบเข้าก่อนยืนยัน

---

## ⚠️ หมายเหตุสำคัญ

1. **IFVG ยังไม่มีหลักฐานว่ามี edge** — logic สวย ≠ ทำเงินได้
   → ต้อง **backtest พิสูจน์ PF/DD ก่อน** (เหมือนที่ทำกับ EA ทอง 6.5 ปี)
2. ค่าเริ่มต้นจูนมาเพื่อ **XAUUSD M15** → ต้องจูน MinGap / Displacement / MaxAge ตามโบรกเกอร์
3. **ทดสอบบนเดโมก่อนใช้จริงเสมอ**

---

*สรุป: Blueprint IFVG ดี (logic แน่น) แต่ต้องเพิ่ม A1 (risk cap) + A2 (DD แบบ prop) ก่อนใช้กับกองทุน — และยึดบทเรียน B1-B6 ที่เราเรียนมาด้วยเลือดเนื้อ*
