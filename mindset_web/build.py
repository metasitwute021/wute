#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ตรวจคลังข้อใน items.json แล้วฉีดเข้า demo.html

ใช้:  python3 build.py            # ตรวจ + ฉีด
      python3 build.py --check    # ตรวจอย่างเดียว ไม่แตะ demo.html

ทำไมต้องฉีด: เปิด demo.html ผ่าน file:// แล้ว fetch('items.json') จะโดน CORS บล็อก
เดโมจึงต้องมีคลังข้ออยู่ในไฟล์เดียว ส่วน items.json คือต้นฉบับที่ backend จะอ่านตอนทำจริง
"""
import json, sys, collections, pathlib

HERE  = pathlib.Path(__file__).parent
ITEMS = HERE / "items.json"
DEMO  = HERE / "demo.html"
BEGIN, END = "/* === ITEMS:BEGIN === */", "/* === ITEMS:END === */"

AXES        = ["O", "C", "E", "A", "N", "G"]
MIN_PER_AXIS   = 12    # ข้อต่อแกนขั้นต่ำในคลัง
MIN_REVERSE    = 0.40  # สัดส่วนข้อ trait ที่ต้องกลับด้าน (กัน acquiescence bias)
MIN_FORCED     = 12    # ข้อ forced-choice ขั้นต่ำ (กัน social desirability bias)


def validate(items):
    errs, ids = [], {i["id"] for i in items}

    for k, v in collections.Counter(i["id"] for i in items).items():
        if v > 1: errs.append(f"id ซ้ำ: {k}")

    for it in items:
        iid = it.get("id", "?")
        for f in ("id", "type", "source", "tags", "prompt", "options", "skippable"):
            if f not in it: errs.append(f"{iid}: ขาดฟิลด์ {f}")
        if it.get("type") not in ("trait", "scenario", "video", "reading"):
            errs.append(f"{iid}: type ไม่รู้จัก {it.get('type')}")
        if it.get("type") == "video"   and not it.get("slides"): errs.append(f"{iid}: video ไม่มี slides")
        if it.get("type") == "reading" and not it.get("body"):   errs.append(f"{iid}: reading ไม่มี body")
        if len(it.get("options", [])) < 2: errs.append(f"{iid}: ตัวเลือกน้อยกว่า 2")
        if not any(o.get("w") for o in it.get("options", [])):
            errs.append(f"{iid}: ไม่มีตัวเลือกที่ให้คะแนนเลย")

        for ax in it.get("tags", []):
            if ax not in AXES: errs.append(f"{iid}: tag ไม่รู้จัก {ax}")
        for o in it.get("options", []):
            for ax in o.get("w", {}):
                if ax not in AXES: errs.append(f"{iid}: แกนไม่รู้จัก {ax}")

        optids = {o["id"] for o in it.get("options", [])}
        for opt, tgt in it.get("edges", {}).items():
            if opt not in optids: errs.append(f"{iid}: edge อ้าง option '{opt}' ที่ไม่มีอยู่")
            if tgt not in ids:    errs.append(f"{iid}: edge ชี้ไป '{tgt}' ที่ไม่มีในคลัง (กิ่งตาย)")

    per_axis = collections.Counter(ax for i in items for ax in i.get("tags", []))
    for ax in AXES:
        if per_axis[ax] < MIN_PER_AXIS:
            errs.append(f"แกน {ax} มีแค่ {per_axis[ax]} ข้อ (ต้อง >= {MIN_PER_AXIS})")

    for ax in AXES:
        tr = [i for i in items if i.get("type") == "trait" and ax in i.get("tags", [])]
        rv = [i for i in tr if i.get("reverse")]
        if tr and len(rv) / len(tr) < MIN_REVERSE:
            errs.append(f"แกน {ax}: ข้อกลับด้านแค่ {len(rv)}/{len(tr)} (ต้อง >= {MIN_REVERSE:.0%})")

    forced = [i for i in items if i.get("forced")]
    if len(forced) < MIN_FORCED:
        errs.append(f"forced-choice มีแค่ {len(forced)} ข้อ (ต้อง >= {MIN_FORCED})")

    return errs, per_axis, forced


def main():
    data  = json.loads(ITEMS.read_text(encoding="utf-8"))
    items = data["items"]
    errs, per_axis, forced = validate(items)

    print(f"คลังข้อ: {len(items)} ข้อ")
    print("แยกตามชนิด :", dict(collections.Counter(i["type"] for i in items)))
    print("แยกตามที่มา:", dict(collections.Counter(i["source"] for i in items)))
    print("ข้อต่อแกน   :", {a: per_axis[a] for a in AXES})
    print("forced-choice:", len(forced), "| ข้อที่มีเส้นบังคับ:", sum(1 for i in items if i.get("edges")))

    if errs:
        print("\n❌ ไม่ผ่าน validator:")
        for e in errs: print("  -", e)
        return 1
    print("✅ ผ่าน validator ทุกข้อ")

    if "--check" in sys.argv:
        return 0

    html = DEMO.read_text(encoding="utf-8")
    a, b = html.index(BEGIN), html.index(END)
    pool = json.dumps(items, ensure_ascii=False, indent=1)
    html = html[:a] + BEGIN + "\nconst POOL = " + pool + ";\n" + html[b:]
    DEMO.write_text(html, encoding="utf-8")
    print(f"ฉีดคลังข้อเข้า {DEMO.name} แล้ว ({len(html):,} ตัวอักษร)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
