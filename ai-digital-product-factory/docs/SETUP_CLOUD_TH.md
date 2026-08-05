# คู่มือติดตั้งบน n8n Cloud — ทำตามทีละขั้น

สำหรับผู้ใช้ **n8n Cloud** (สมัครที่ n8n.io ไม่ได้ลง Docker เอง)
workflow ชุดนี้ (รุ่น Cloud-compatible) **ไม่ใช้ environment variable แล้ว** —
ค่าตั้งค่าทั้งหมดอยู่ใน node ชื่อ **`Factory Config`** ที่แก้ได้จากหน้าจอ n8n โดยตรง

> ถ้าคุณเคย import workflow รุ่นเก่าไว้ **ลบทิ้งทั้งหมดก่อน** แล้ว import ชุดใหม่นี้แทน
> (รุ่นเก่าอ่านค่าจาก `$env` ซึ่งใช้บน Cloud ไม่ได้)

---

## ภาพรวม: ต้องเชื่อมอะไรบ้าง

| Credential | จำเป็นแค่ไหน | ใช้ทำอะไร |
|---|---|---|
| **OpenAI API** | 🔴 บังคับ | สร้างเนื้อหา + ภาพทุกชิ้น (ไม่มี = ทำอะไรไม่ได้เลย) |
| **Postgres** (Supabase) | 🟠 จำเป็น | ความจำของโรงงาน: กันของซ้ำ, คุมงบ, บันทึกผล |
| **Google Drive OAuth2** | 🟡 ทีหลังได้ | สำรองไฟล์สินค้า |
| **Etsy (OAuth2 API)** | 🟡 ทีหลังได้ | ลงขาย — **ไม่มีก็ผลิตสินค้าได้** ระบบจะข้ามขั้นลงร้านให้เอง |
| Gmail | ⚪ ไม่ใช้ | ระบบนี้ไม่ได้ใช้ ลบหรือเก็บไว้ก็ได้ |

---

## ขั้นที่ 1 — สร้าง OpenAI credential (5 นาที)

1. ไปที่ **platform.openai.com** → API keys → **Create new secret key** → คัดลอกเก็บไว้
   (เปิดดูซ้ำไม่ได้ ต้องคัดลอกตอนนั้นเลย)
2. ที่เมนู **Billing** เติมเครดิตอย่างน้อย $10
3. ใน n8n: **Credentials → Create credential → ค้นหา "OpenAI"** → เลือก **OpenAI**
4. วาง API key → **Save** → ต้องขึ้นเครื่องหมายถูกเขียว

---

## ขั้นที่ 2 — Postgres (Supabase)

> **Supabase คืออะไร:** เป็นผู้ให้บริการที่เอา **PostgreSQL ของแท้** มารันบนคลาวด์ให้เรา
> พร้อมหน้าเว็บไว้ดูตาราง — credential ชื่อ "Postgres" ใน n8n ก็คือการต่อไปที่ฐานข้อมูลนี้
> ลบโปรเจกต์ Supabase = ลบฐานข้อมูลทิ้ง / สร้างโปรเจกต์ใหม่ = ได้ฐานข้อมูลใหม่

### 2.1 สร้างโปรเจกต์ Supabase (ทำครั้งเดียว)

supabase.com → **New project** แล้วกรอก:

| ช่อง | ใส่อะไร |
|---|---|
| Organization | ปล่อยตามเดิม |
| GitHub (optional) | **ข้าม** ไม่ต้องกด Connect GitHub |
| Project name | เช่น `ai-product-factory` |
| **Database password** | ดูคำเตือนข้างล่าง |
| Region | **Northeast Asia (Tokyo)** (หรือที่ใกล้ที่สุด) |
| Security | เอาติ๊กออกที่ **Automatically expose new tables** ที่เหลือปล่อยตามเดิม |

⚠️ **Database password — จุดที่คนพลาดบ่อยที่สุด**
- **อย่ากด "Generate a password"** — จะได้อักขระพิเศษที่ทำให้ copy/paste เพี้ยน
- พิมพ์เองเป็น **ตัวอักษรอังกฤษ + ตัวเลขล้วน** ยาว ~16 ตัว ไม่มี `@ # $ % & !` หรือช่องว่าง
- **จดไว้ทันทีก่อนกดสร้าง** — Supabase ไม่โชว์ให้ดูซ้ำอีกเลย และนี่คือรหัสที่ต้องเอาไปใส่ n8n
- ไม่ใช่รหัส login เว็บ Supabase และไม่ใช่ API key
- ถ้าลืมจริง ๆ: Settings → Database → **Reset database password**

กด **Create new project** แล้วรอ ~2 นาที

### 2.2 หาค่าเชื่อมต่อ

ในโปรเจกต์ → ปุ่ม **Connect** (แถบบนสุด) → การ์ด **`Direct` (Connection string)**
→ เลือก **Session pooler**

> ทางสำรองถ้าหาไม่เจอ: Settings → **Database** → หัวข้อ **Connection pooling**
> หน้าจอ Supabase เปลี่ยนบ่อย ถ้าเห็นการ์ด Framework / Server / Direct / ORM / MCP
> ให้กด **Direct**

จะได้สตริงหน้าตาแบบนี้ (ตรง `[YOUR-PASSWORD]` เป็นแค่ข้อความ placeholder):

```
postgresql://postgres.abcdefghijklmnop:[YOUR-PASSWORD]@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres
             └──────── User ────────┘                  └──────────── Host ─────────────┘ └Port┘ └Database┘
```

### 2.3 กรอกใน n8n

n8n → **Credentials** → Create credential → ค้นหา **Postgres**

| ช่องใน n8n | ค่า | หมายเหตุ |
|---|---|---|
| Host | `aws-0-<region>.pooler.supabase.com` | ลอกจากสตริงข้างบน |
| Database | `postgres` | |
| User | `postgres.<project-ref>` | ⚠️ **เปลี่ยนทุกครั้งที่สร้างโปรเจกต์ใหม่** |
| **Password** | Database password ของโปรเจกต์นั้น | |
| **Port** | **`5432`** | ⚠️ ต้อง 5432 (Session pooler) — ห้ามใช้ `6543` (Transaction pooler) n8n ต่อไม่ได้ |
| **SSL** | **`require`** | ⚠️ สาเหตุต่อไม่ติดอันดับ 1 — Supabase บังคับ SSL แต่ n8n ตั้งต้นเป็น disable |

ถ้าตั้ง `require` แล้วยังไม่ผ่าน → เปิด **Ignore SSL Issues** เพิ่ม → Retry

ต้องขึ้นแถบเขียว **Connection tested successfully** → แล้ว **กด Save** (เขียวเฉย ๆ ยังไม่บันทึก)

🧹 ถ้ามี Postgres credential ตัวเก่าที่ต่อไม่ติดค้างอยู่ **ลบทิ้ง** ไม่งั้นเวลาเลือกในโหนดจะหยิบผิดตัว

> **ย้ายไปโปรเจกต์ Supabase ใหม่เมื่อไหร่ ต้องแก้ 3 ช่อง: Host, User, Password**
> ไม่ใช่แค่ password — เพราะ project ref ใหม่ทำให้ User เปลี่ยนด้วย

### 2.4 สร้างตาราง

Supabase → **SQL Editor** → **New query** → วางเนื้อหาไฟล์ `db/schema.postgres.sql` ทั้งไฟล์
→ **Run** (Ctrl+Enter)

ถ้าเด้งกล่อง **"Potential issue detected — creates tables without enabling Row Level Security"**
→ กด **`Run and enable RLS`** (ปุ่มเขียว)

> RLS ปิดกั้นการอ่านตารางผ่าน API สาธารณะ (anon key) แต่**ไม่กระทบ n8n** เพราะ n8n ต่อ
> PostgreSQL โดยตรงด้วย user `postgres` ซึ่งเป็นเจ้าของตาราง — เจ้าของตารางข้าม RLS ได้เสมอ

✅ ต้องได้ `Success. No rows returned` → เช็คที่ **Table Editor** ต้องเห็นตาราง `adpf_*` **12 ตาราง**
(`products`, `ideas`, `events`, `costs`, `budget`, `qa_results`, `product_versions`,
`sales`, `ab_tests`, `trends`, `prompt_versions`, `category_targets`) ทุกตารางว่างเปล่าเป็นเรื่องปกติ
(รันซ้ำได้ไม่พัง ทุกคำสั่งเป็น `CREATE TABLE IF NOT EXISTS`)

---

## ขั้นที่ 3 — Import workflow ชุดใหม่ (Cloud-compatible)

Import ทีละไฟล์ **เรียงจากเลขมากไปน้อย**:

```
10 → 09 → 08 → 07 → 06 → 05 → 04 → 03 → 02 → 01 → 00
```

วิธี import: หน้า Workflows → ปุ่ม ⋯ มุมขวาบน → **Import from File**

หลัง import เปิด **workflow 01** เช็ค node `Run: ...` และ `Log: ...` ทั้ง 11 จุด
ว่าชี้ไปยัง sub-workflow ถูกตัว (ปกติจะถูกอัตโนมัติเพราะ id ตรงกัน)

---

## ขั้นที่ 4 — ตั้งค่าที่ node `Factory Config`

ทุก workflow มี node **`Factory Config`** อยู่ถัดจาก trigger

**แก้ที่ workflow 01 ตัวเดียวพอ** — sub-workflow ทุกตัวรับค่าต่อจาก 01 อัตโนมัติ

1. เปิด workflow 01 → ดับเบิลคลิก node `Factory Config`
2. ในโค้ดจะเห็นก้อน `DEFAULTS = { ... }` — แก้ค่าตรงนั้นได้เลย
3. ตอนนี้ยังไม่ต้องแก้อะไรก็ได้ — ทุกค่ามี default ที่ใช้งานได้
   ค่าที่จะกลับมาแก้ทีหลัง: `ETSY_API_KEY`, `ETSY_SHOP_ID` (เมื่อ Etsy อนุมัติ app)

> ทางเลือก: ถ้าแพลนของคุณมีเมนู **Variables** (Settings → Variables)
> ตั้งชื่อเดียวกับใน DEFAULTS ได้เลย ค่าจาก Variables จะทับ DEFAULTS อัตโนมัติ
> เหมาะกับของลับอย่าง `ETSY_API_KEY`

---

## ขั้นที่ 5 — ทดสอบทีละขั้น

### 5.1 รัน workflow 00 (ฟรีเกือบหมด ~ครึ่งสตางค์)

เปิด **00 Starter Smoke Test** → เลือก OpenAI credential ที่ node
`OpenAI: Connection Test` (ครั้งแรกครั้งเดียว) → กด **Test workflow**

✅ ต้องได้: `PASSED - n8n is ready` + เช็กลิสต์เขียว 4 ข้อ
📄 โบนัส: node `Build Test PDF` → แท็บ **Binary** → ดาวน์โหลด PDF ทดสอบได้เลย

### 5.2 รัน workflow 06 (ทดสอบฐานข้อมูล ฟรี)

เปิด **06** → กด Test workflow → ตอน execute ให้ pin input:
```json
{"op":"run_start","run_id":"test-1","factory":"printable","status":"running"}
```
✅ ต้องได้ `{"ok": true}` — เปิด Supabase → Table Editor → เห็นแถวใน `adpf_products`

❗ ถ้า error ที่ node Postgres = credential ยังไม่ผ่าน กลับไปขั้นที่ 2

### 5.3 รันทั้งสาย แบบซ้อมฟรี

เปิด **01** → Test workflow → pin input ที่ `Trigger: Manual Run`:
```json
{"factory":"printable","dry_run":true}
```

**ไม่ต้องมี Etsy** — ระบบตรวจเจอเองว่า Etsy ยังไม่ตั้งค่า จะ:
ผลิตสินค้าครบ (วิจัย → ไอเดีย → เนื้อหา → QA → ไฟล์) → บันทึกลงฐานข้อมูล →
จบด้วยสถานะ `completed_without_publish` พร้อมบอกว่าไฟล์อยู่ตรงไหน

✅ ต้องได้: `ok: true` + รายชื่อไฟล์ใน `files_produced`
ไฟล์จริงเปิดดูได้ที่ node `Run: Product Engine` → output → `files[]`

### 5.4 ของจริงชิ้นแรก (~$1.3)

```json
{"factory":"resume","dry_run":false}
```
`resume` ใช้ภาพน้อยสุด (6 ใบ) — เปิด PDF ที่ได้มาดูจริง ๆ ก่อนไปต่อ

---

## เรื่องที่ต้องรู้เกี่ยวกับ n8n Cloud

1. **โควตา execution**: การผลิต 1 ชิ้นกิน **~12–14 executions** (นับ sub-workflow ด้วย)
   แพลนทดลอง 1,000 ครั้ง ≈ สินค้า ~70 ชิ้น
2. **SQLite ใช้ไม่ได้บน Cloud** (ต้องใช้ Execute Command) — ใช้ Postgres ตามคู่มือนี้
3. **ของลับใน Factory Config**: ค่า `ETSY_API_KEY` ที่พิมพ์ใน DEFAULTS จะติดอยู่ในตัว
   workflow (คนที่เปิด workflow เห็นได้) — ถ้าแพลนมี Variables ให้เก็บที่นั่นแทน
4. เมื่อได้ Etsy app แล้ว: ใส่ `ETSY_API_KEY` + `ETSY_SHOP_ID` ใน Factory Config ของ 01
   แล้วสร้าง credential **OAuth2 API** (generic) ตาม README ข้อ 1.2 —
   run ถัดไปจะกลับมาลง Etsy อัตโนมัติ ไม่ต้องแก้อะไรเพิ่ม

---

## แก้ปัญหาเร็ว

| อาการ | แก้ |
|---|---|
| Postgres: `password authentication failed` | ใช้ Database password ของ**โปรเจกต์ที่กำลังต่ออยู่** ไม่ใช่ของโปรเจกต์เก่า (reset ได้ใน Supabase → Settings → Database) |
| Postgres: `Tenant or user not found` | ช่อง User ยังเป็น project ref เก่า หรือ Host คนละ region กับโปรเจกต์ — ลอกใหม่จาก Connect → Direct → Session pooler |
| Postgres: timeout / ต่อไม่ติด | Port ต้อง 5432 + SSL = require |
| Postgres: ผ่านแล้วแต่ query พัง `relation does not exist` | รัน schema ใน SQL Editor (ขั้นที่ 2) |
| OpenAI: `Incorrect API key` | key ผิด/ลืม Save credential |
| OpenAI: `insufficient_quota` | เติมเครดิตที่ platform.openai.com/billing |
| 01 จบด้วย `completed_without_publish` | ปกติ! แปลว่ายังไม่ตั้ง Etsy — ไฟล์อยู่ใน output ของ `Run: Product Engine` |
| node อ้าง `Factory Config` ไม่เจอ | คุณ import รุ่นเก่า — ลบแล้ว import ชุดใหม่ |
