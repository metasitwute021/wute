#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ตรวจคลังข้อใน items.json แล้ว build เว็บออกมาที่ docs/ สำหรับ GitHub Pages

ใช้:  python3 build.py            # ตรวจ + build
      python3 build.py --check    # ตรวจอย่างเดียว ไม่เขียนไฟล์

ที่มา -> ผลลัพธ์
    app.html   (โครงเว็บ + engine, มี marker ITEMS:BEGIN/END)
    items.json (คลังข้อ 120 ข้อ — ต้นฉบับ)
        |
        +--> docs/index.html            เว็บที่ deploy จริง (ไฟล์เดียว เปิดในมือถือได้)
             docs/manifest.webmanifest  ให้ "เพิ่มลงหน้าจอโฮม" บนมือถือได้
             docs/.nojekyll             กัน GitHub Pages ไปประมวลผลด้วย Jekyll

ทำไมต้องฉีดคลังข้อเข้าไปในไฟล์: เปิดผ่าน file:// แล้ว fetch('items.json') จะโดน CORS บล็อก
ส่วน items.json คือต้นฉบับที่ backend จะอ่านตอนทำระบบจริง
"""
import json, sys, collections, pathlib

HERE  = pathlib.Path(__file__).parent
ITEMS = HERE / "items.json"
SHELL = HERE / "app.html"
DOCS  = HERE.parent / "docs"
BEGIN, END = "/* === ITEMS:BEGIN === */", "/* === ITEMS:END === */"

MANIFEST = {
    "name": "สังเกตการณ์ — แบบทดสอบ mindset",
    "short_name": "สังเกตการณ์",
    "description": "แบบทดสอบ mindset ที่ดูมากกว่าคำตอบของคุณ",
    "start_url": "./index.html",
    "scope": "./",
    "display": "standalone",
    "orientation": "portrait",
    "lang": "th",
    "background_color": "#F2F4F0",
    "theme_color": "#1C5E4E",
    "icons": [{
        "src": "icon.svg",
        "sizes": "any",
        "type": "image/svg+xml",
        "purpose": "any maskable"
    }]
}

ICON = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
    '<rect width="512" height="512" fill="#1C5E4E"/>'
    '<circle cx="256" cy="256" r="104" fill="none" stroke="#F2F4F0" stroke-width="30"/>'
    '<circle cx="256" cy="256" r="35" fill="#F2F4F0"/>'
    '</svg>'
)

AXES        = ["O", "C", "E", "A", "N", "G", "D"]
FACETS      = {"mach", "narc", "psyc"}
MIN_PER_AXIS   = 12    # ข้อต่อแกนขั้นต่ำในคลัง
MIN_REVERSE    = 0.40  # สัดส่วนข้อ trait ที่ต้องกลับด้าน (กัน acquiescence bias)
MIN_FORCED     = 12    # ข้อ forced-choice ขั้นต่ำ (กัน social desirability bias)
MIN_DCOMP_PAIR = 4     # ข้อคู่เทียบต่อคู่ด้าน (engine หยิบไปคู่ละ 2 ต่อรอบ ต้องมีให้เลือกมากกว่านั้น)
DPAIRS = [("mach", "narc"), ("mach", "psyc"), ("narc", "psyc")]


def validate(items):
    errs, ids = [], {i["id"] for i in items}

    for k, v in collections.Counter(i["id"] for i in items).items():
        if v > 1: errs.append(f"id ซ้ำ: {k}")

    for it in items:
        iid = it.get("id", "?")
        for f in ("id", "type", "source", "tags", "prompt", "options", "skippable"):
            if f not in it: errs.append(f"{iid}: ขาดฟิลด์ {f}")
        if it.get("type") not in ("trait", "scenario", "video", "reading", "dcomp"):
            errs.append(f"{iid}: type ไม่รู้จัก {it.get('type')}")
        if it.get("type") == "video"   and not it.get("slides"): errs.append(f"{iid}: video ไม่มี slides")
        if it.get("type") == "reading" and not it.get("body"):   errs.append(f"{iid}: reading ไม่มี body")
        if len(it.get("options", [])) < 2: errs.append(f"{iid}: ตัวเลือกน้อยกว่า 2")

        if it.get("type") == "dcomp":
            # ข้อคู่เทียบ: ให้คะแนนผ่าน dw ไม่ใช่ w — และต้องเป็นคู่ตรงข้ามพอดี
            # (+1 ด้านหนึ่ง / -1 อีกด้าน) ไม่งั้นการเลือกข้างจะไม่หักล้างกันจริง
            if not it.get("forced"):
                errs.append(f"{iid}: ข้อคู่เทียบต้องเป็น forced-choice (ห้ามมีตัวเลือกกลาง ๆ ให้หลบ)")
            if len(it.get("options", [])) != 2:
                errs.append(f"{iid}: ข้อคู่เทียบต้องมี 2 ตัวเลือกพอดี")
            sides = []
            for o in it.get("options", []):
                dw = o.get("dw")
                if not dw:
                    errs.append(f"{iid}/{o.get('id')}: ข้อคู่เทียบต้องมี dw"); continue
                if o.get("w"):
                    errs.append(f"{iid}/{o.get('id')}: ข้อคู่เทียบห้ามให้คะแนน w (จะไปปนกับ % ของแต่ละด้าน)")
                if set(dw) - FACETS:
                    errs.append(f"{iid}/{o.get('id')}: dw อ้าง facet ไม่รู้จัก {sorted(set(dw) - FACETS)}")
                if sorted(dw.values()) != [-1, 1]:
                    errs.append(f"{iid}/{o.get('id')}: dw ต้องเป็น +1 ด้านหนึ่ง และ -1 อีกด้าน")
                sides.append(tuple(sorted(dw)))
            if len(set(sides)) > 1:
                errs.append(f"{iid}: สองตัวเลือกต้องเทียบคู่ด้านเดียวกัน")
        elif not any(o.get("w") for o in it.get("options", [])):
            errs.append(f"{iid}: ไม่มีตัวเลือกที่ให้คะแนนเลย")

        for ax in it.get("tags", []):
            if ax not in AXES: errs.append(f"{iid}: tag ไม่รู้จัก {ax}")

        # แกน D (Dark Triad) ต้องระบุ facet เสมอ ไม่งั้นรายงานแยกสามด้านไม่ได้
        if "D" in it.get("tags", []):
            if it.get("type") != "dcomp" and it.get("facet") not in FACETS:
                errs.append(f"{iid}: ข้อแกน D ต้องมี facet เป็นหนึ่งใน {sorted(FACETS)}")
            if len(it.get("tags", [])) > 1:
                errs.append(f"{iid}: ข้อแกน D ห้ามผูกกับแกนอื่น (จะทำให้คะแนน Big Five ปนกับ Dark Triad)")
        elif it.get("facet"):
            errs.append(f"{iid}: มี facet แต่ไม่ได้ tag แกน D")
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

    openers = [i for i in items if i.get("opener")]
    if len(openers) < 8:
        errs.append(f"ข้อเปิดมีแค่ {len(openers)} ข้อ (ต้อง >= 8 ไม่งั้นคนทำซ้ำจะเจอข้อแรกเดิม)")
    for i in openers:
        if i.get("type") != "scenario":
            errs.append(f"{i['id']}: ตั้งเป็นข้อเปิดได้เฉพาะข้อสถานการณ์")

    # ทุก facet ของ Dark Triad ต้องมีข้อพอ ๆ กัน ไม่งั้นด้านที่ข้อน้อยจะถูกประเมินจากหลักฐานบางเกินไป
    fc = collections.Counter(i.get("facet") for i in items if "D" in i.get("tags", []))
    for f in sorted(FACETS):
        if fc[f] < 4:
            errs.append(f"Dark Triad facet '{f}' มีแค่ {fc[f]} ข้อ (ต้อง >= 4)")

    # ทุกคู่ด้านต้องมีข้อคู่เทียบพอ ไม่งั้น engine จะหยิบข้อเดิมซ้ำทุกรอบ (exposure สูงเกิน)
    dcp = collections.Counter(
        tuple(sorted(i["options"][0]["dw"])) for i in items
        if i.get("type") == "dcomp" and i["options"][0].get("dw"))
    for pair in DPAIRS:
        if dcp[pair] < MIN_DCOMP_PAIR:
            errs.append(f"ข้อคู่เทียบ {pair[0]}-{pair[1]} มีแค่ {dcp[pair]} ข้อ (ต้อง >= {MIN_DCOMP_PAIR})")

    forced = [i for i in items if i.get("forced")]
    if len(forced) < MIN_FORCED:
        errs.append(f"forced-choice มีแค่ {len(forced)} ข้อ (ต้อง >= {MIN_FORCED})")

    return errs, per_axis, forced, openers


def main():
    data  = json.loads(ITEMS.read_text(encoding="utf-8"))
    items = data["items"]
    errs, per_axis, forced, openers = validate(items)

    print(f"คลังข้อ: {len(items)} ข้อ")
    print("แยกตามชนิด :", dict(collections.Counter(i["type"] for i in items)))
    print("แยกตามที่มา:", dict(collections.Counter(i["source"] for i in items)))
    print("ข้อต่อแกน   :", {a: per_axis[a] for a in AXES})
    print("Dark Triad  :", dict(collections.Counter(
        i.get("facet") for i in items if "D" in i.get("tags", []) and i.get("type") != "dcomp")))
    print("ข้อคู่เทียบ  :", dict(collections.Counter(
        "-".join(sorted(i["options"][0]["dw"])) for i in items if i.get("type") == "dcomp")))
    print("forced-choice:", len(forced), "| เส้นบังคับ:", sum(1 for i in items if i.get("edges")), "| ข้อเปิด:", len(openers))

    if errs:
        print("\n❌ ไม่ผ่าน validator:")
        for e in errs: print("  -", e)
        return 1
    print("✅ ผ่าน validator ทุกข้อ")

    if "--check" in sys.argv:
        return 0

    html = SHELL.read_text(encoding="utf-8")
    a, b = html.index(BEGIN), html.index(END)
    pool = json.dumps(items, ensure_ascii=False, indent=1)
    html = html[:a] + BEGIN + "\nconst POOL = " + pool + ";\n" + html[b:]

    DOCS.mkdir(exist_ok=True)
    (DOCS / "index.html").write_text(html, encoding="utf-8")
    (DOCS / "manifest.webmanifest").write_text(
        json.dumps(MANIFEST, ensure_ascii=False, indent=2), encoding="utf-8")
    (DOCS / "icon.svg").write_text(ICON, encoding="utf-8")
    (DOCS / ".nojekyll").write_text("", encoding="utf-8")

    print(f"\nbuild เสร็จ -> docs/")
    print(f"  index.html            {len(html):,} ตัวอักษร (คลังข้อฝังอยู่ในไฟล์)")
    print(f"  manifest.webmanifest  สำหรับเพิ่มลงหน้าจอโฮมบนมือถือ")
    print(f"  icon.svg .nojekyll")
    return 0


if __name__ == "__main__":
    sys.exit(main())
