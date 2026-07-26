# วิเคราะห์สถาปัตยกรรม — AI Digital Product Factory

เอกสารนี้อธิบายว่า "โรงงาน" นี้ถูกออกแบบมาอย่างไร ทำไมถึงตัดสินใจแบบนั้น
และจุดไหนที่จะพังก่อนถ้าเปิดใช้จริง

---

## 1. ภาพรวมสายการผลิต

```
                    ┌─────────────────────────────┐
   Schedule ───┐    │   01 MASTER CONTROLLER      │
   Webhook  ───┼───▶│  run_id / เลือกโรงงาน /      │
   Manual   ───┘    │  error funnel / logging     │
                    └──────────────┬──────────────┘
                                   │
        ┌──────────────────────────┼───────────────────────────┐
        ▼                          ▼                           ▼
┌───────────────┐   ┌──────────────────────────┐   ┌────────────────────┐
│ 02 RESEARCH   │──▶│ 03 PRODUCT ENGINE        │──▶│ 04 PUBLISH ENGINE  │
│ Etsy signals  │   │ Switch 8 โรงงาน           │   │ Etsy draft listing │
│ Research AI   │   │ Idea→Writer→Designer→SEO │   │ Publisher AI       │
│ SEO AI        │   │ →Metadata→QA→Export      │   │ Gumroad/MiriCanvas │
└───────────────┘   └──────────────────────────┘   └─────────┬──────────┘
                                                              │
                                        ┌─────────────────────┴────────┐
                                        ▼                              ▼
                             ┌────────────────────┐        ┌────────────────────┐
                             │ 05 DRIVE BACKUP    │───────▶│ 06 DATABASE LOGGER │
                             │ โฟลเดอร์ idempotent │        │ Postgres / SQLite  │
                             └────────────────────┘        └────────────────────┘
```

จุดสำคัญ: **01 เป็นตัวเดียวที่รู้จักลำดับงาน** ส่วน 02–06 ไม่รู้จักกันเอง แต่ละตัวรับ contract
เข้า → คืน contract ออก เท่านั้น ทำให้เทสแยกทีละตัวได้ และเปลี่ยนตัวใดตัวหนึ่งไม่กระทบตัวอื่น

---

## 2. Data contract ระหว่าง workflow

ทุกเส้นเชื่อมมีสัญญาชัดเจน ถ้าผิดสัญญาจะ throw ทันทีที่ node แรกของ workflow ปลายทาง

**01 → 02**
```json
{ "run_id": "...", "factory": "planner", "seed_keyword": "", "dry_run": false,
  "prompt_version": "v1.0.0" }
```

**02 → 01 → 03** (สัญญาหลักที่โจทย์กำหนด)
```json
{ "ok": true,
  "research": {
    "product_type": "...", "category": "...", "target_customer": "...",
    "keyword": "...", "sub_keywords": ["..."], "difficulty": "easy|medium|hard",
    "selling_points": ["..."], "price_suggestion_usd": 0, "long_tail": ["..."] },
  "market": { "competitor_count": 0, "price_usd": {...}, "top_tags": [...] } }
```

**03 → 01 → 04**
```json
{ "ok": true, "product_name": "...", "slug": "...",
  "metadata": {...}, "seo": {...}, "qa": {...}, "profile": {...},
  "files": [{ "key", "file_name", "format", "mime_type", "purpose", "bytes", "b64" }],
  "stats": { "pdf_pages": 0, "images": {...}, "total_bytes": 0 } }
```

**04 → 01 → 05**
```json
{ "ok": true, "etsy_listing_id": 123, "etsy_listing_state": "draft",
  "gumroad_package_ready": true, "miricanvas_package_ready": false,
  "extra_files": [...] }
```

**05 → 01 → 06**
```json
{ "ok": true, "drive_folder_id": "...", "drive_folder_path": "AI Digital Product Factory/Etsy/...",
  "uploaded_files": [{ "id", "name" }] }
```

### ทำไมส่ง base64 ใน JSON ไม่ส่ง binary
n8n ทำ binary หาย ทุกครั้งที่ Code node คืน item ใหม่โดยไม่ copy `binary` มาด้วย ในสายที่มี
Code node 20+ ตัว โอกาสพลาดสูงมาก จึงเก็บไฟล์เป็น `b64` ในสัญญา แล้ว **แปลงเป็น binary
เฉพาะตอนจะอัปโหลดจริง** (node `Prepare Image Upload`, `Prepare Digital File Upload`,
`Prepare Upload Binary`) ต้นทุนคือ RAM ~15–25 MB ต่อ run ซึ่งรับได้

---

## 3. ทำไม 8 โรงงานใช้สายการผลิตร่วมกัน

โจทย์บอกว่าแต่ละโรงงานต้องมีขั้นตอนครบ 12 ขั้น ถ้าทำแยกจริง = 8 × 12 = 96 node ที่เกือบ
เหมือนกันทุกตัว แก้ prompt ที่เดียวต้องไล่แก้ 8 ที่ และจะ drift ภายในเดือนเดียว

ที่ทำแทนคือ **Switch 8 ทาง → Set node ต่อโรงงาน → มาบรรจบที่ `Merge: Factory Profiles`**
โรงงานแต่ละตัวจึงมี "สาขาของตัวเอง" จริงตามโจทย์ (`Factory Profile: Planner` ฯลฯ)
แต่สิ่งที่แตกต่างถูกบีบให้เหลือแค่ *ข้อมูล* ไม่ใช่ *โครงสร้าง*:

| ฟิลด์ใน profile | ควบคุมอะไร |
|---|---|
| `page_width_pt` / `page_height_pt` | ขนาดหน้า PDF (A4 / Letter / 2:3 / สี่เหลี่ยมจัตุรัส / แนวนอน) |
| `target_pages` / `image_pages` | ความยาวสินค้า และงบภาพ |
| `content_schema` | โครงเนื้อหาที่ Writer AI ต้องทำตาม (คนละเรื่องกันจริง ๆ ในแต่ละโรงงาน) |
| `art_direction` | ทิศทางภาพที่ Designer AI ต้องยึด |
| `svg_required` | ต้องมี source แก้ไขได้ไหม |
| `output_formats` | ฟอร์แมตที่ export |
| `gumroad_ready` / `miricanvas_ready` | ความเข้ากันได้กับ marketplace รอง |
| `price_range_usd` | เพดานราคาที่ Metadata AI ถูกบังคับให้อยู่ในกรอบ |

**เพิ่มโรงงานที่ 9 = เพิ่ม 1 rule ใน Switch + 1 Set node** ไม่ต้องแตะสายการผลิตเลย

---

## 4. การตัดสินใจสำคัญ 6 ข้อ

### 4.1 PDF เขียนเองใน Code node
n8n Code node `require` แพ็กเกจ npm ไม่ได้ ทางเลือกคือยิงไป service ภายนอก (เพิ่ม provider,
เพิ่มค่าใช้จ่าย, เพิ่มคีย์ที่ต้องดูแล) หรือเขียน PDF writer เอง — เลือกอย่างหลัง

เคล็ดลับที่ทำให้ทำได้จริง: **JPEG byte stream คือ PDF image stream ที่ถูกต้องอยู่แล้ว**
ใส่ `/Filter /DCTDecode` แล้ววางไบต์ดิบลงไปได้เลย ไม่ต้อง decode ไม่ต้อง compress
เพราะเหตุนี้ทุกภาพที่จะลง PDF จึงขอจาก OpenAI เป็น `output_format: "jpeg"`
(ถ้าใช้ PNG ต้อง inflate + จัดการ alpha channel ซึ่งทำใน sandbox ไม่ไหว)

ที่รองรับ: หน้าข้อความ Helvetica/Helvetica-Bold + WinAnsi, ตัดคำอัตโนมัติ, ขึ้นหน้าใหม่เองเมื่อ
เนื้อหาล้น, หน้าภาพแบบ fit/full-bleed, caption, footer, document info
ข้อจำกัดที่ยอมรับ: **ไม่รองรับภาษาไทยใน PDF** (base-14 font ไม่มี glyph ไทย) — สินค้าขายบน Etsy
เป็นภาษาอังกฤษอยู่แล้ว ถ้าจะทำสินค้าไทยต้อง embed TrueType font ซึ่งเป็นงานคนละก้อน

`build/verify.py` สร้าง PDF จริงแล้วเดิน xref table ทีละ entry ตรวจว่า offset ทุกตัวชี้ตรงวัตถุ
— บั๊กคลาสสิกของ PDF ที่เขียนมือคือ offset เพี้ยน แล้วไปพังตอนลูกค้าเปิดไฟล์

### 4.2 Etsy เป็น draft เสมอ
`state` มาจาก `ETSY_LISTING_STATE` (default `draft`) และ **node `Parse Publisher Verdict`
บังคับทับค่าที่โมเดลตอบ** — โมเดลไม่มีสิทธิ์ตัดสินใจว่าอะไรขึ้นขายเลย
เหตุผล: ร้าน Etsy ถูกระงับได้จาก listing เดียว ต้นทุนการให้คนกดยืนยันต่ำกว่ามาก

### 4.3 QA gate แบบ fail-closed + ตรวจซ้ำด้วยโค้ด
`Parse QA Report` ไม่เชื่อโมเดลอย่างเดียว แต่ตรวจซ้ำแบบ deterministic:
title ≤ 140, tag = 13 ตัวพอดี, แต่ละ tag ≤ 20 ตัวอักษร
ถ้าไม่ผ่านจะคืน `ok:false` (ไม่ใช่ throw) เพราะนี่คือ "ของไม่ผ่าน QC" ไม่ใช่ "ระบบพัง"
— 01 จะบันทึกลง DB แล้วจบ run อย่างสะอาด

### 4.4 Research มี fallback แบบไม่ใช้ AI
ถ้า Research AI ตอบ JSON เสีย → `Research Fallback Concept` ประกอบ concept จากตัวเลข Etsy
ล้วน (tag ที่พบบ่อย, ราคา median, จำนวนคู่แข่ง) run จึง **degrade ไม่ die**

### 4.5 Gumroad / MiriCanvas เตรียมเท่านั้น
ตามโจทย์ — และมีเหตุผลทางเทคนิครองรับ: MiriCanvas ไม่มี public write API ส่วน Gumroad
ควรให้คนตรวจราคา/สิทธิ์การขายซ้ำก่อน จึงออกมาเป็น `gumroad-package.json` /
`miricanvas-package.json` ที่มีทุกอย่างที่คนต้องใช้ พร้อม `next_manual_steps`
เกณฑ์ตัดสินเป็นโค้ด (deterministic) ส่วน Publisher AI **มีสิทธิ์ veto อย่างเดียว ไม่มีสิทธิ์อนุมัติ**

### 4.6 Prompt อยู่ใน workflow ไม่ใช่ในหัวคน
node `Prompt Library` ของแต่ละ workflow เก็บ prompt ทั้งหมดพร้อม `PROMPT_VERSION`
ทุก run เขียน `Prompt.md` ลง Drive (prompt + ภาพทุกใบ + verdict QA) → ทำซ้ำได้ และรู้ว่า
สินค้าที่ขายดีมาจาก prompt เวอร์ชันไหน

---

## 5. ต้นทุนและคอขวด

| รายการ | ต่อสินค้า 1 ชิ้น | หมายเหตุ |
|---|---|---|
| Image API | **8–14 ใบ** | cover 1 + thumbnail 1 + preview 3 + page 1–8 → **ต้นทุนหลัก >80%** |
| Chat API | 8–10 ครั้ง | Writer AI กินโทเคนมากสุด (max_tokens 8000) |
| Etsy API | 3–8 ครั้ง | create + images + file |
| Drive API | 12–16 ครั้ง | ค้นโฟลเดอร์ 4 + สร้าง 0–4 + อัปโหลด ~10 |
| เวลา | ~4–9 นาที | ภาพคือคอขวด เพราะทำทีละใบ |

**ลดต้นทุนได้ที่ไหน**: ลด `image_pages` ใน profile คือปุ่มที่แรงที่สุด
Kids Factory (8 ใบ) แพงกว่า Resume Factory (1 ใบ) หลายเท่า
ระหว่างทดสอบให้ใช้ `dry_run=true` เสมอ — จะสลับไปใช้ placeholder JPEG 1×1 ทั้งหมด

**ทำไมไม่ generate ภาพขนาน**: Etsy/OpenAI มี rate limit และการทำทีละใบทำให้ภาพใบเดียวพัง
ไม่ล้มทั้งชุด ถ้าต้องการเร็วขึ้นให้เพิ่ม `batchSize` ที่ `Loop: Image Jobs` แล้วดู 429 ให้ดี

---

## 6. ความเสี่ยง (เรียงตามโอกาสเจอจริง)

| ความเสี่ยง | ผลกระทบ | ที่ระบบทำไว้ | ที่คนต้องทำ |
|---|---|---|---|
| `ETSY_TAXONOMY_ID` ผิด | Etsy ปฏิเสธทั้ง listing | error output → log → alert | ตรวจ id จริงก่อน run แรก |
| นโยบายสินค้า AI ของ Etsy | ร้านถูกระงับ | draft + QA gate | อ่านนโยบายล่าสุด + เปิดเผยการใช้ AI |
| ภาพซ้ำ/คล้ายกันทั้งร้าน | ยอดขายตก, ดูสแปม | `art_direction` ต่อโรงงาน | สลับ seed keyword + review งานเป็นระยะ |
| Etsy rate limit (10/s, 10k/วัน) | run ล้ม | retry 3 ครั้ง + อัปโหลดทีละใบ | อย่ารันหลาย factory พร้อมกัน |
| Etsy OAuth token หมดอายุ | 401 ทุก node | retry + error funnel | ตั้งเตือน refresh token |
| โมเดลตอบ JSON เสีย | run ล้มกลางทาง | parse แยก + validate + fallback ที่ 02 | ดู `adpf_events` ว่า agent ไหนพังบ่อย |
| ลิขสิทธิ์/เครื่องหมายการค้าในภาพ | ถูกแจ้งลบ | prompt ห้ามระบุแบรนด์/ตัวละคร + QA ตรวจ | ตรวจงานก่อนกด publish |
| ไฟล์ใหญ่เกิน (base64 ใน memory) | n8n OOM | สินค้าเดี่ยวต่อ run, upload ทีละไฟล์ | เพิ่ม RAM ถ้าเพิ่ม image_pages มาก |

---

## 7. ลำดับการเปิดใช้จริงที่แนะนำ

1. **สัปดาห์ 1** — รัน `dry_run=true` อย่างเดียว ตรวจว่า PDF/โฟลเดอร์/DB ถูกต้องครบ
2. **สัปดาห์ 2** — เปิดของจริง 1 โรงงาน (แนะนำ `printable` เพราะภาพน้อย ต้นทุนต่ำ)
   วันละ 1 ชิ้น ตรวจ draft ทุกชิ้นด้วยมือ
3. **สัปดาห์ 3** — ถ้า QA ผ่านสม่ำเสมอ เปิด `factory=auto` หมุนเวียน ยังตรวจ draft ทุกชิ้น
4. **หลังจากนั้น** — ดูข้อมูลใน `adpf_products` ว่าโรงงาน/keyword ไหนขายได้ แล้วค่อยปรับ
   `FACTORY_ROTATION` ให้เอียงไปทางที่ทำเงิน

**อย่าเพิ่งตั้ง `ETSY_LISTING_STATE=active`** จนกว่าจะมีสินค้าที่ผ่าน QA แล้วขายได้จริงอย่างน้อย
20–30 ชิ้น

---

## 8. สิ่งที่ยังไม่ได้ทำ (ตั้งใจ)

- ไม่มี auto-upload ไป Gumroad/MiriCanvas — ตามโจทย์
- ไม่มีการวัดผลย้อนกลับ (ยอดขาย → ปรับ prompt) — ต้องดึง Etsy receipts API ซึ่งเป็นเฟสถัดไป
- ไม่รองรับฟอนต์ไทยใน PDF — ต้อง embed TrueType
- ไม่มีการ dedupe สินค้าข้าม run — ตอนนี้กันซ้ำได้ระดับ keyword เท่านั้น
  (ทำเพิ่มได้: query `adpf_products` ก่อน แล้วส่ง keyword ที่เคยทำแล้วเข้าไปใน prompt ของ Research AI)
