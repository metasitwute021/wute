# ติดตั้ง Planner Factory — ทีละขั้น

ระบบนี้มี **workflow แค่ 2 ตัว** ไม่มี sub-workflow แปลว่าไม่มีปัญหา
"Workflow does not exist" ตอน import อีกแล้ว

---

## ขั้นที่ 1 — เตรียมฐานข้อมูล (5 นาที, ทำครั้งเดียว)

1. เปิด Supabase → โปรเจกต์ของคุณ → เมนูซ้าย **SQL Editor**
2. เปิดไฟล์ `db/schema.sql` ก๊อปทั้งไฟล์
3. วางลงช่อง SQL แล้วกด **Run**
4. ไปที่ **Table Editor** ต้องเห็น 4 ตาราง:
   `planner_runs`, `planner_products`, `planner_listings`, `planner_costs`

ไฟล์นี้รันซ้ำได้ ไม่พัง (ใช้ `CREATE TABLE IF NOT EXISTS`)

---

## ขั้นที่ 2 — เตรียม credential ใน n8n (ทำครั้งเดียว)

ต้องมี 2 อัน ทั้งคู่สร้างที่ **Credentials → Add credential**

| ชื่อ credential | ประเภทที่ต้องเลือก | ใส่อะไร |
|---|---|---|
| OpenAI | **OpenAI API** | API key ของคุณ |
| Postgres | **Postgres** | ค่าจาก Supabase (ดูตารางล่าง) |

**ค่า Postgres จาก Supabase:** กดปุ่ม **Connect** ที่หัวโปรเจกต์ → การ์ด
**Direct** → เลือก **Session pooler** จะได้สตริงหน้าตาแบบนี้

```
postgresql://postgres.xxxxxxxx@aws-0-<region>.pooler.supabase.com:5432/postgres
             └──── User ────┘  └──────── Host ────────┘  └Port┘ └Database┘
```

| ช่องใน n8n | ค่า |
|---|---|
| Host | `aws-0-<region>.pooler.supabase.com` |
| Database | `postgres` |
| User | `postgres.<project-ref>` |
| Password | Database password ของโปรเจกต์นี้ (ไม่ใช่รหัสเข้าเว็บ Supabase) |
| Port | **5432** (ห้ามใช้ 6543) |
| SSL | `require` |

> **จุดที่คนพลาดบ่อยที่สุด:** ถ้าเปลี่ยนโปรเจกต์ Supabase ต้องแก้ **ทั้ง Host และ User**
> ไม่ใช่แค่ password — ถ้าขึ้น `Tenant or user not found` แปลว่า User ยังเป็นของเก่า

กด **Test connection** ต้องขึ้นเขียวก่อนถึงจะ Save

---

## ขั้นที่ 3 — import workflow ทั้ง 2 ตัว

n8n → **Workflows → Import from File**

1. `workflows/02_etsy_connect.json`
2. `workflows/01_planner_factory.json`

หลัง import ให้เข้าไปในแต่ละ workflow แล้วผูก credential ให้ node เหล่านี้
(n8n ไม่ผูกให้อัตโนมัติเวลา import):

| workflow | node ที่ต้องเลือก credential | เลือกอันไหน |
|---|---|---|
| Planner Factory | `AI: Concept`, `AI: Writer`, `AI: Art Direction`, `AI: Listing`, `OpenAI: Image` | OpenAI |
| Planner Factory | `Recent Products`, `Log Run Start`, `Save Product`, `Log Failure` | Postgres |

(workflow **Etsy Connect** ไม่ต้องใช้ credential เลย)

---

## ขั้นที่ 4 — ทดลองรันแบบไม่เสียเงินก่อน

ก่อนต่อ Etsy ให้พิสูจน์ว่าเครื่องทำงานก่อน

1. เปิด **Planner Factory** → กด **Execute workflow**
2. ระบบจะสร้าง planner จริง โดยเรียก OpenAI จริง (ประมาณ **$0.15–0.30** ต่อเล่ม)
3. ถ้าอยากซ้อมแบบ **ไม่เสียเงินเลย** ให้ pin ข้อมูลนี้ที่ node `Start Run`:

```json
[{ "dry_run": true }]
```

โหมดนี้จะข้ามการสร้างภาพ แต่ยังเดินครบทุกขั้นตอนรวมถึงสร้าง PDF จริง

ดูผลที่ node **Summarise Run** — ต้องเห็น `page_count` 20 ขึ้นไป และ
`link_count` มากกว่า `page_count`

---

## ขั้นที่ 5 — ต่อ Etsy (ทำครั้งเดียว)

Etsy บังคับใช้ PKCE ซึ่ง credential OAuth2 ปกติของ n8n ทำไม่ได้
workflow `Etsy Connect` เลยทำขั้นตอนนี้ให้เอง

1. เปิด **Planner Config** ใน workflow **Etsy Connect** ใส่ `ETSY_API_KEY`
   (คือ keystring จากหน้า Etsy App ของคุณ) แล้ว Save
2. **Activate** workflow นั้น แล้วก๊อป **Production URL** ของ node `Open This URL`
3. เอา URL นั้นไปใส่ในหน้า Etsy App ช่อง **Callback URL** ให้ตรงกันเป๊ะ ๆ
4. เปิด URL นั้นในเบราว์เซอร์ → กดปุ่มส้ม → อนุญาต
5. Etsy จะพากลับมาที่หน้าที่แสดง **3 ค่า** พร้อมก๊อป:
   - `ETSY_REFRESH_TOKEN`
   - `ETSY_SHOP_ID`
   - `ETSY_TAXONOMY_ID` ← หมวด Calendars & Planners **ที่ค้นจาก Etsy จริง ไม่ได้เดา**

> เก็บหน้านั้นไว้จนกว่าจะวางค่าครบ — refresh token แสดงครั้งเดียว

6. เอาทั้ง 3 ค่าไปวางใน **Planner Config** ของ **Planner Factory**
   พร้อมตั้งราคา `ETSY_PRICE_USD`

---

## ขั้นที่ 6 — รันจริงและตรวจก่อนเปิดขาย

กด **Execute workflow** อีกครั้ง คราวนี้จะขึ้น Etsy ให้ด้วย

ค่าเริ่มต้นคือ `ETSY_LISTING_STATE = draft` แปลว่า **ยังไม่เปิดขาย**
ให้เข้าไปดูใน Etsy ก่อนว่า:

- ภาพปกดูดี ไม่มีตัวหนังสือเพี้ยน
- ชื่อสินค้าและคำอธิบายอ่านรู้เรื่อง
- ไฟล์ PDF ที่แนบเปิดได้ และแท็บด้านขวากดได้จริง

พอใจแล้วค่อยเปลี่ยนเป็น `active` ใน Planner Config หรือกดเปิดขายเองใน Etsy

---

## ค่าที่แก้ได้ทั้งหมด (node `Planner Config`)

| ชื่อ | ค่าเริ่มต้น | ความหมาย |
|---|---|---|
| `PLANNER_YEAR` | ว่าง | ว่าง = undated (ขายได้ตลอด) ใส่ `2027` = ปฏิทินจริงของปีนั้น |
| `WEEK_STARTS_MONDAY` | `true` | `false` = เริ่มสัปดาห์วันอาทิตย์ (ตลาดอเมริกา) |
| `SECTION_ART_COUNT` | `2` | จำนวนภาพคั่น — เพิ่มแล้วสวยขึ้นแต่แพงขึ้น |
| `IMAGE_QUALITY_COVER` | `high` | ลดเป็น `medium` ประหยัดได้ประมาณ 4 เท่า |
| `ETSY_LISTING_STATE` | `draft` | เปลี่ยนเป็น `active` เมื่อไว้ใจผลลัพธ์แล้ว |
| `ETSY_PRICE_USD` | `12` | ราคาขาย |

---

## เวลาพัง จะรู้ได้ยังไง

ทุก error ของระบบนี้เขียนให้บอกว่า **ต้องทำอะไรต่อ** ไม่ใช่แค่บอกว่าพัง เช่น

> `The writer supplied prompts for only 5 of 12 months. Missing: June, July, ...`

ถ้าเจอ error ที่อ่านไม่ออก ให้ดูที่ node ที่แดง แล้วอ่านบรรทัดแรกของข้อความ —
n8n เก็บเฉพาะท้ายข้อความยาว ๆ ระบบนี้เลยเอาส่วนสำคัญไว้ต้นประโยคเสมอ
