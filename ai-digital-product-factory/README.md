# AI Digital Product Factory

โรงงานผลิตสินค้าดิจิทัลอัตโนมัติบน **n8n** — วิจัยตลาด Etsy → สร้างสินค้า → แพ็กไฟล์ →
ลง Etsy (draft) → สำรองขึ้น Google Drive → บันทึกฐานข้อมูล
ใช้ **OpenAI API อย่างเดียว** ไม่มี provider อื่น

```
01 Master Controller
   └─ 02 Research Engine ──→ 03 Product Engine ──→ 04 Publish Engine
                                                     └─ 05 Google Drive Backup
                                                          └─ 06 Database Logger
```

| Workflow | ไฟล์ | Nodes | หน้าที่ |
|---|---|---:|---|
| 01 Master Controller | `workflows/01_master_controller.json` | 34 | trigger, เลือกโรงงาน, สั่งงาน, error handling, logging |
| 02 Research Engine | `workflows/02_research_engine.json` | 15 | วิเคราะห์ Etsy → product concept |
| 03 Product Engine | `workflows/03_product_engine.json` | 48 | 8 โรงงาน → เนื้อหา → ภาพ → SEO → QA → export ไฟล์ |
| 04 Publish Engine | `workflows/04_publish_engine.json` | 29 | อัปโหลด Etsy + เตรียมแพ็ก Gumroad / MiriCanvas |
| 05 Google Drive Backup | `workflows/05_google_drive_backup.json` | 24 | สร้างโฟลเดอร์อัตโนมัติ + อัปโหลดไฟล์ทั้งหมด |
| 06 Database Logger | `workflows/06_database_logger.json` | 9 | PostgreSQL / SQLite |

---

## 1. ติดตั้ง

### 1.1 Import workflow
Import ทั้ง 6 ไฟล์ใน `workflows/` เข้า n8n **เรียงจาก 06 ไป 01**
(สร้าง sub-workflow ให้เสร็จก่อน แล้วค่อย import ตัวที่เรียกใช้)

> ไฟล์แต่ละตัวมี `id` คงที่ (เช่น `ADPF02RESEARCHENGN`) เพื่อให้ node
> `Execute Workflow` ใน 01 หากันเจอ ถ้า n8n ตั้ง id ใหม่ตอน import ให้เปิด 01 แล้ว
> เลือก sub-workflow ใหม่ใน node `Run: ...` และ `Log: ...` ทั้ง 7 จุด

### 1.2 Credential (ไม่มี key ใดอยู่ในไฟล์ JSON เลย)

| Credential | ชนิดใน n8n | ใช้ที่ |
|---|---|---|
| OpenAI | `OpenAI API` | ทุก node `OpenAI: ...` (predefined credential type) |
| Etsy | `OAuth2 API` (generic, Authorization Code + PKCE) | ทุก node `Etsy: ...` |
| Google Drive | `Google Drive OAuth2 API` | ทุก node `Drive: ...` |
| PostgreSQL | `Postgres` | node `Postgres: ...` (เฉพาะเมื่อ `DB_TYPE=postgres`) |

ค่า Etsy OAuth2 ที่ต้องกรอก:
- Authorization URL `https://www.etsy.com/oauth/connect`
- Access Token URL `https://api.etsy.com/v3/public/oauth/token`
- Scope `listings_r listings_w listings_d shops_r shops_w email_r`

### 1.3 Environment variables
คัดลอกจาก `.env.example` ไปตั้งบน instance และต้องตั้ง

```
N8N_BLOCK_ENV_ACCESS_IN_NODE=false
```

ไม่อย่างนั้น `$env.*` ใน expression จะอ่านไม่ได้ และ node `Validate Environment` จะหยุดงานทันที

### 1.4 ฐานข้อมูล
- **PostgreSQL** (แนะนำ) — workflow 06 รัน `CREATE TABLE IF NOT EXISTS` ให้เองรอบแรก
  หรือรัน `db/schema.postgres.sql` ล่วงหน้าก็ได้
- **SQLite** — ตั้ง `DB_TYPE=sqlite` + `DB_SQLITE_PATH` ต้องมี `sqlite3` CLI บนเครื่อง n8n
  (ใช้ได้เฉพาะ self-hosted เพราะใช้ node `Execute Command`) schema อยู่ที่ `db/schema.sqlite.sql`

---

## 2. ทดสอบก่อนใช้จริง (smoke test)

```
1. รัน 06 เดี่ยว ๆ  → ส่ง {"op":"run_start","run_id":"test-1","status":"running"}
2. รัน 02 เดี่ยว ๆ  → ส่ง {"run_id":"test-2","factory":"printable"}
                       ตรวจว่าได้ contract 7 ฟิลด์ครบ
3. รัน 01 ด้วย Manual Trigger โดยส่ง dry_run=true
      → ภาพจะใช้ placeholder 1x1 ไม่เสียค่า Image API
4. รันเต็มสายจริง 1 ครั้ง แล้วตรวจ Etsy draft + โฟลเดอร์ Drive + แถวใน DB
```

เรียกจากภายนอก:

```bash
curl -X POST https://<n8n>/webhook/ai-digital-product-factory \
  -H 'Content-Type: application/json' \
  -d '{"factory":"planner","seed_keyword":"minimal weekly planner","dry_run":false}'
```

`factory` รับค่า: `planner` `printable` `canva` `wallart` `resume` `spreadsheet` `kids` `svg`
หรือ `auto` (หมุนเวียนตาม `FACTORY_ROTATION`)

---

## 3. โครงสร้างโปรเจกต์

```
ai-digital-product-factory/
├── workflows/          ← ไฟล์ที่ import เข้า n8n (deliverable)
├── prompts/            ← prompt ทั้ง 8 agent ในรูป markdown สำหรับรีวิว
├── db/                 ← schema PostgreSQL / SQLite
├── docs/               ← เอกสารสถาปัตยกรรมภาษาไทย
├── build/              ← generator + ตัวตรวจ (source of truth)
└── .env.example
```

### แก้ไข workflow
ไฟล์ใน `workflows/` **ถูก generate** จาก `build/` อย่าแก้ JSON ตรง ๆ ให้แก้ที่ Python
แล้วรัน

```bash
python3 build/build.py     # สร้างใหม่ทั้ง 6 ไฟล์ + prompts + schema
python3 build/verify.py    # ตรวจ syntax ของ Code node ทุกตัว + smoke test PDF จริง
```

`build.py` ตรวจให้อัตโนมัติว่า: ชื่อ node ไม่ซ้ำ, ทุก node มี comment, connection ชี้ไป node
ที่มีจริง, ไม่มี node กำพร้า, และไม่มีร่องรอย secret ในไฟล์
`verify.py` เอา `jsCode` ของทุก Code node ไปให้ `node --check` แล้วสร้าง PDF จริงหนึ่งไฟล์
พร้อมเดิน xref table ทีละ entry

---

## 4. OpenAI Agents (8 ตัว, prompt แยกกันจริง)

| # | Agent | ใช้ใน | หน้าที่ |
|---|---|---|---|
| 1 | Research AI | 02 | อ่านสัญญาณตลาด → product concept |
| 2 | Idea AI | 03 | concept → product brief ที่สร้างได้จริง |
| 3 | Writer AI | 03 | เขียนเนื้อหาทุกหน้าที่จะพิมพ์ลง PDF |
| 4 | Designer AI | 03 | เขียน prompt ภาพทุกใบ + SVG source |
| 5 | SEO AI | 02, 03 | keyword / title / description / tags |
| 6 | Metadata AI | 03 | metadata record ที่เป็นความจริงของสินค้า |
| 7 | QA AI | 03 | ด่านกันของเสียก่อนขึ้นร้าน |
| 8 | Publisher AI | 04 | payload marketplace + ตัดสินความเข้ากันได้ |

prompt ทุกตัวอยู่ใน node `Prompt Library` ของแต่ละ workflow (versioned ด้วย `PROMPT_VERSION`)
และ mirror เป็นไฟล์ใน `prompts/` ให้ diff ได้

เรียก OpenAI ผ่าน `HTTP Request` + `predefinedCredentialType: openAiApi` ทุกจุด →
API key อยู่ใน credential ของ n8n เท่านั้น ไม่มีใน JSON

---

## 5. ไฟล์ที่โรงงานผลิตออกมา

| ไฟล์ | ฟอร์แมต | หมายเหตุ |
|---|---|---|
| `<slug>.pdf` | PDF | ตัวสินค้าจริง สร้างด้วย PDF writer ใน Code node ไม่พึ่ง service ภายนอก |
| `<slug>-cover.jpg` | JPG | ภาพหน้าปก (ใช้เป็นภาพแรกของ listing ด้วย) |
| `<slug>-thumbnail.png` | PNG | ไอคอนร้าน |
| `<slug>-preview-1..3.jpg` | JPG | ภาพ preview |
| `<slug>.svg` | SVG | เฉพาะโรงงานที่ต้องมี source แก้ไขได้ (Canva / Resume / Kids / SVG) |
| `metadata.json` `SEO.json` `content.json` | JSON | |
| `description.txt` `Prompt.md` `workflow-log.txt` | TXT | `Prompt.md` เก็บ prompt + verdict QA ทั้งหมดเพื่อทำซ้ำได้ |
| `gumroad-package.json` `miricanvas-package.json` | JSON | แพ็กที่ **เตรียมไว้เฉย ๆ ไม่อัปโหลดอัตโนมัติ** |

> ภาพที่จะฝังใน PDF ขอจาก OpenAI เป็น **JPEG** เพราะ byte stream ของ JPEG ใส่ลง PDF
> ด้วย `/DCTDecode` ได้ตรง ๆ ส่วน thumbnail ขอเป็น PNG

---

## 6. โครงสร้างโฟลเดอร์บน Google Drive

```
AI Digital Product Factory/
└── Etsy/
    └── <Product Category>/
        └── <Product Name>/
            ├── <slug>.pdf
            ├── <slug>-cover.jpg
            ├── <slug>-thumbnail.png
            ├── <slug>-preview-1..3.jpg
            ├── metadata.json / SEO.json / content.json
            ├── description.txt / Prompt.md
            ├── <slug>.svg           (source file ถ้ามี)
            ├── gumroad-package.json / miricanvas-package.json
            └── workflow-log.txt
```

สร้างแบบ idempotent — รันซ้ำจะใช้โฟลเดอร์เดิม ไม่สร้างซ้ำ

---

## 7. ฐานข้อมูล

ตาราง `adpf_products` (1 run = 1 แถว) และ `adpf_events` (append-only log)

| คอลัมน์ | |
|---|---|
| `product_name` `category` `keywords` `marketplace` | ข้อมูลสินค้า |
| `drive_folder_id` `etsy_listing_id` | ปลายทาง |
| `prompt_version` `status` `error_log` | ควบคุมเวอร์ชัน + ผลลัพธ์ |
| `created_at` `updated_at` `run_id` `factory` | metadata |

06 รองรับ 4 operation: `run_start` / `product_upsert` / `status_update` / `error_log`
ทั้งหมดใช้ statement เดียวกัน (upsert + insert event) และค่า NULL จะไม่ทับค่าที่มีอยู่แล้ว

---

## 8. Error handling / retry / logging

- node ที่ออกเน็ตทุกตัว: `retryOnFail` 3 ครั้ง เว้น 5 วินาที
- `Execute Workflow` ทุกจุดใน 01 เปิด error output → ไหลเข้า `Stage Failed: ...` →
  `Build Error Payload` → บันทึกลง DB → ยิง alert webhook → `Stop On Fatal Error`
- 02 ล้มเหลวไม่ทำให้ทั้ง run ตาย: มี `Research Fallback Concept` สร้าง concept จากตัวเลข Etsy ล้วน
- ภาพใบใดใบหนึ่งพัง → บันทึกไว้แล้วไปต่อ จะหยุดก็ต่อเมื่อ cover หรือ thumbnail หาย
- QA ไม่ผ่าน → คืน `ok:false` (ไม่ใช่ error) แล้วหยุดก่อนถึง Etsy
- ตั้ง 01 เป็น **Error Workflow** ของ 02–06 เพื่อให้ node `Trigger: Workflow Error Handler`
  จับ crash ที่หลุดออกมาได้

---

## 9. ข้อควรระวังก่อนเปิดใช้จริง

1. **`ETSY_TAXONOMY_ID`** ต้องเป็น id จริงของหมวดที่ขาย ไม่งั้น Etsy ปฏิเสธทั้ง listing
2. Etsy มี rate limit 10 req/s และ 10,000 req/วัน — workflow อัปโหลดภาพทีละใบอยู่แล้ว
   แต่ถ้ารันหลาย factory พร้อมกันควรเว้นระยะ
3. ค่าใช้จ่ายหลักคือ **Image API** (~8–14 ใบต่อสินค้า) ใช้ `dry_run=true` ตอนทดสอบเสมอ
4. ตรวจนโยบายสินค้า AI ของ Etsy และเปิดเผยการใช้ AI ตามที่นโยบายกำหนด
5. `ETSY_LISTING_STATE` ค่าเริ่มต้นคือ `draft` โดยตั้งใจ — เปลี่ยนเป็น `active` เมื่อมั่นใจแล้วเท่านั้น
