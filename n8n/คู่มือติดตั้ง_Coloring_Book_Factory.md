# 🎨 คู่มือติดตั้ง — AI Coloring Book Factory (n8n)

ระบบสร้าง "หนังสือภาพระบายสี" อัตโนมัติด้วย AI Agents 3 ตัว

**ผลงานต่อ 1 ชุด (5 หน้ารวมปก, กระดาษ A4 แนวนอน):**

| หน้า | ไฟล์ | ลักษณะ |
|---|---|---|
| ปก | `cover.jpg` | **ภาพสีสดใส** มีชื่อเล่มบนปก + กรอบตกแต่งเว้นขอบกระดาษ |
| หน้า 1–4 | `page_1.jpg` … `page_4.jpg` | ภาพระบายสี **ขาว-ดำ เส้นหนา** สไตล์โมเดลห้อง isometric มีสวน/ต้นไม้นอกห้อง องค์ประกอบเต็มหน้า + กรอบเว้นขอบ |
| รวมเล่ม | `ชื่อเล่ม.pdf` | PDF 5 หน้า A4 แนวนอน พร้อมพิมพ์/ขาย |

ทุกครั้งที่รัน AI จะ**สุ่มธีมใหม่เอง**จากคลัง 22 ธีม (อวกาศ, พ่อมดแม่มด, สัตว์ป่า, มุมเมือง, ใต้ทะเล, ไดโนเสาร์, สวนแฟรี่, ฟาร์ม, ร้านขนมหวาน, ฮาโลวีนน่ารัก, หมู่บ้านคริสต์มาส, โรงงานหุ่นยนต์, คาเฟ่ชาญี่ปุ่น, อ่าวโจรสลัด, ซาฟารี, เบเกอรี่, แคมป์ปิ้งในป่า, เพื่อนหิมะขั้วโลก, ร้านดอกไม้, วงดนตรีจิ๋ว, ทะเลวันหยุด, ห้องสมุดเวทมนตร์) พร้อมคิดตัวละคร ชื่อเล่ม และฉากเองทั้งหมด

---

## 🤖 AI Agents 3 ตัวในระบบ

```
Trigger → Config → [1] Creative Director → [2] Prompt Artist → [3] Art Director QA
                                                                      ↓
        Google Drive ← รวมเล่ม PDF ← Loop สร้างภาพทีละหน้า (gpt-image-1) ←┘
```

1. **Creative Director** — สุ่มธีม เลือกตัวละครสัตว์น่ารัก ตั้งชื่อเล่ม คิดฉาก 4 หน้า (แต่ละหน้าต้องเป็นกิจกรรมต่างกัน)
2. **Prompt Artist** — เขียน prompt ภาพแบบมืออาชีพ ล็อกสไตล์ตายตัว: โมเดลห้อง isometric + สวนนอกห้อง + กรอบเว้นขอบ + เส้นดำหนา ขาว-ดำล้วน (ปกเป็นเวอร์ชันภาพสี)
3. **Art Director QA** — ตรวจทุก prompt ก่อนจ่ายเงินสร้างภาพ: หน้าระบายสีต้องไม่มีคำที่ทำให้เกิดสี/เงา, ปกต้องมีชื่อเล่มตรงตัว, ฉากไม่ซ้ำกัน — เจอปัญหาแก้ให้อัตโนมัติ

---

## 📋 สิ่งที่ต้องมีก่อนติดตั้ง

1. **n8n** (n8n Cloud หรือ self-hosted ก็ได้) เวอร์ชัน 1.30 ขึ้นไป
2. **OpenAI API key** จาก https://platform.openai.com/api-keys
   - ⚠️ โมเดล `gpt-image-1` ต้องผ่านการยืนยันตัวตนองค์กร (Organization Verification) ก่อน — ไปที่ platform.openai.com → Settings → Organization → **Verify Organization** (ใช้บัตรประชาชน/พาสปอร์ตถ่ายรูป ใช้เวลาไม่กี่นาที)
   - เติมเครดิตในบัญชีอย่างน้อย $5
3. **บัญชี Google** (สำหรับ Google Drive)

## 💰 ค่าใช้จ่ายโดยประมาณต่อ 1 ชุด

| รายการ | ราคา |
|---|---|
| gpt-image-1 ขนาด 1536x1024 quality `medium` × 5 ภาพ | ~$0.35 (~13 บาท) |
| gpt-4.1-mini (agents 3 ตัว) | ~$0.01 |
| **รวม** | **~$0.36/ชุด** |

ถ้าอยากประหยัด: เปลี่ยน `image_quality` ในโหนด **Config** เป็น `low` (~$0.09/ชุด แต่รายละเอียดลดลง) หรืออยากสวยสุดใช้ `high` (~$0.90/ชุด)

---

## 🛠️ ขั้นตอนติดตั้ง

### ขั้นที่ 1: Import workflow

1. เปิด n8n → เมนูซ้าย **Workflows** → ปุ่ม **สามจุด (⋯)** มุมขวาบน → **Import from File**
2. เลือกไฟล์ `AI_Coloring_Book_Factory.json`
3. จะเห็น workflow พร้อมโน้ตอธิบายสีต่างๆ ครบทุกส่วน

### ขั้นที่ 2: ตั้งค่า OpenAI credential (ใช้ 4 โหนด)

1. ดับเบิลคลิกโหนด **Model - Creative Director**
2. ช่อง Credential → **Create new credential** → วาง API key ของ OpenAI → Save
3. เปิดโหนด **Model - Prompt Artist**, **Model - Art Director QA** และ **Generate Image** แล้วเลือก credential ตัวเดียวกันที่เพิ่งสร้าง
   - โหนด **Generate Image** เป็น HTTP Request ที่ใช้ credential ชนิด "OpenAI API" เหมือนกัน เลือกจาก dropdown ได้เลย

### ขั้นที่ 3: ตั้งค่า Google Drive credential (ใช้ 3 โหนด)

1. ดับเบิลคลิกโหนด **Create Folder** → Credential → **Create new credential** → เลือก **Google Drive OAuth2 API**
2. n8n Cloud: กด **Sign in with Google** ได้เลย / Self-hosted: ต้องสร้าง OAuth Client ID ใน Google Cloud Console ก่อน (ดู docs ของ n8n: Google OAuth2 generic setup)
3. เปิดโหนด **Upload Image** และ **Upload PDF** เลือก credential เดียวกัน

### ขั้นที่ 4: ทดสอบรัน

1. กดปุ่ม **Test workflow** (หรือ Execute workflow) มุมล่าง
2. รอประมาณ 3–6 นาที (สร้างภาพ 5 ภาพ ภาพละ ~30–60 วินาที)
3. เสร็จแล้วเข้า Google Drive จะเห็นโฟลเดอร์ใหม่ชื่อ `ColoringBook_ธีม_วันที่เวลา` ข้างในมี `cover.jpg`, `page_1.jpg` … `page_4.jpg` และไฟล์ PDF รวมเล่ม

### ขั้นที่ 5: เปิดระบบอัตโนมัติรายวัน

- Workflow มี **Schedule Trigger** ตั้งไว้ **ทุกวัน 09:00** อยู่แล้ว
- แค่เปิดสวิตช์ **Active** มุมขวาบนของ workflow → ระบบจะสร้างชุดใหม่ (ธีมสุ่มใหม่) ให้ทุกเช้าโดยอัตโนมัติ
- อยากเปลี่ยนเวลา: ดับเบิลคลิกโหนด **Schedule Trigger** แล้วแก้ Trigger at Hour

---

## 🎛️ การปรับแต่ง

### เปลี่ยนจำนวนหน้า
ดับเบิลคลิกโหนด **Config** → แก้ `num_pages` (เช่น 6 หรือ 10) — ทุกอย่างปรับตามอัตโนมัติทั้งจำนวนภาพและ PDF

### เพิ่ม/แก้ธีม
ดับเบิลคลิกโหนด **Creative Director** → Options → **System Message** → แก้รายการธีมในบรรทัด theme pool ได้เลย (เพิ่มธีมไทยๆ ก็ได้ เช่น Thai Temple Fair, Floating Market)

### บังคับธีมที่ต้องการ (ไม่สุ่ม)
พิมพ์เพิ่มท้ายข้อความในช่อง Prompt ของโหนด **Creative Director**: `Use this theme: Under the Sea`

### เปลี่ยนคุณภาพ/ขนาดภาพ
โหนด **Config** → `image_quality`: `low` / `medium` / `high`, `image_size`: `1536x1024` (แนวนอน — แนะนำ), `1024x1536` (แนวตั้ง), `1024x1024` (จัตุรัส)

### เปลี่ยนสไตล์ภาพ
แก้ System Message ของโหนด **Prompt Artist** — บล็อกสไตล์ล็อก (locked style block) คือหัวใจของหน้าตาภาพ อยากได้ลายเส้นแนวอื่น (เช่น mandala, ลายไทย) แก้ตรงนั้น

---

## ❓ แก้ปัญหาที่พบบ่อย

| อาการ | สาเหตุ / วิธีแก้ |
|---|---|
| Generate Image ขึ้น error 403 `organization must be verified` | ยังไม่ได้ Verify Organization กับ OpenAI (ดูขั้นตอนในหัวข้อ "สิ่งที่ต้องมี") |
| Error 429 rate limit | บัญชี OpenAI เพิ่งเติมเงินครั้งแรก limit ต่ำ — โหนดตั้ง retry อัตโนมัติ 3 ครั้งแล้ว ถ้ายังติดให้รอ 1–2 นาทีแล้วรันใหม่ |
| Generate Image timeout | ภาพ quality `high` ใช้เวลานาน — โหนดตั้ง timeout ไว้ 5 นาทีแล้ว ปกติไม่ควรเกิน ถ้าเกินให้ลด quality |
| Agent ตอบไม่เป็น JSON / workflow หยุดที่ agent | เปิดโหนด Parser ที่คู่กัน → เปิด option **Auto-fix format** หรือรันใหม่อีกครั้ง (นานๆ เกิดที) |
| ภาพหน้าระบายสีมีสีเทา/เงาปน | Art Director QA ช่วยกรองอยู่แล้ว แต่ถ้ายังเจอ เพิ่มคำว่า `absolutely no gray tones, no gradients` ในบล็อกสไตล์ของ Prompt Artist |
| อัปโหลด Drive ไม่ได้ | Credential Google หมดอายุ → เปิด credential แล้วกด Reconnect |
| อยากได้ไฟล์ PNG แทน JPEG | แก้ `output_format` ในโหนด Generate Image เป็น `png` ได้ แต่ PDF รวมเล่มจะไม่รองรับ (Code node ฝัง JPEG เท่านั้น) — แนะนำใช้ JPEG ตามเดิม |

---

## 📁 ไฟล์ในโฟลเดอร์นี้

- `AI_Coloring_Book_Factory.json` — workflow สำหรับ import เข้า n8n
- `คู่มือติดตั้ง_Coloring_Book_Factory.md` — ไฟล์นี้
