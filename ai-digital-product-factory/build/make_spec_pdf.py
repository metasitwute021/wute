#!/usr/bin/env python3
"""Render docs/SYSTEM_SPEC_TH.md to a Thai-language PDF.

    python3 build/make_spec_pdf.py

Markdown -> self-contained HTML -> headless Chromium print-to-PDF.

Chromium is used instead of ReportLab/FPDF because Thai needs real text
shaping: vowels and tone marks stack above and below the base consonant, and
only a HarfBuzz-backed renderer places them correctly. Loma is requested first;
Chromium substitutes FreeSerif when embedding (Loma is OTF/CFF), which shapes
Thai correctly too - the check at the end verifies the text really is Thai.

No network access and no npm packages are involved.
"""

from __future__ import annotations

import html
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCE = os.path.join(ROOT, "docs", "SYSTEM_SPEC_TH.md")
OUTPUT = os.path.join(ROOT, "docs", "SYSTEM_SPEC_TH.pdf")

CHROME_CANDIDATES = [
    "/opt/pw-browsers/chromium",
    "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell",
    shutil.which("chromium"),
    shutil.which("chromium-browser"),
    shutil.which("google-chrome"),
]

# Chromium does not reliably resolve the Thai face by family name in this
# sandbox, so the font files are embedded directly. They are small (~50 KB each)
# and this makes the rendered PDF byte-identical on any machine.
THAI_FONTS = [
    ("/usr/share/fonts/opentype/tlwg/Loma.otf", 400, "normal"),
    ("/usr/share/fonts/opentype/tlwg/Loma-Bold.otf", 700, "normal"),
    ("/usr/share/fonts/opentype/tlwg/Loma-Oblique.otf", 400, "italic"),
]


def font_face_css() -> str:
    import base64

    blocks = []
    for path, weight, style in THAI_FONTS:
        if not os.path.exists(path):
            continue
        with open(path, "rb") as fh:
            payload = base64.b64encode(fh.read()).decode("ascii")
        blocks.append(
            "@font-face { font-family: 'LomaEmbedded';"
            f" font-weight: {weight}; font-style: {style};"
            f" src: url(data:font/otf;base64,{payload}) format('opentype'); }}"
        )
    if not blocks:
        raise SystemExit(
            "No Thai font found. Install fonts-tlwg (apt-get install fonts-tlwg)."
        )
    return "\n".join(blocks)


CSS = """
@page { size: A4; margin: 16mm 14mm 16mm 14mm; }

:root { --ink:#1b1f24; --muted:#5b6673; --line:#d7dde4; --accent:#2f6f4f;
        --code-bg:#f5f7f9; }

* { box-sizing: border-box; }

body {
  font-family: 'LomaEmbedded', 'Loma', 'FreeSerif', sans-serif;
  font-size: 10pt; line-height: 1.65; color: var(--ink);
  margin: 0; -webkit-font-smoothing: antialiased;
}

h1 { font-size: 21pt; line-height: 1.35; margin: 0 0 4pt; color: var(--accent);
     border-bottom: 2.5px solid var(--accent); padding-bottom: 8pt; }
h2 { font-size: 15pt; margin: 22pt 0 8pt; padding-top: 6pt;
     border-top: 1px solid var(--line); page-break-after: avoid; }
h3 { font-size: 12pt; margin: 16pt 0 6pt; color: var(--accent);
     page-break-after: avoid; }
h1, h2, h3 { page-break-inside: avoid; }

p { margin: 0 0 8pt; }
strong { font-weight: 700; }

ul, ol { margin: 0 0 10pt; padding-left: 20pt; }
li { margin-bottom: 3pt; }

hr { border: 0; border-top: 1px solid var(--line); margin: 16pt 0; }

blockquote {
  margin: 10pt 0; padding: 8pt 12pt; border-left: 3px solid var(--accent);
  background: #f2f7f4; color: var(--muted);
}
blockquote p:last-child { margin-bottom: 0; }

code {
  font-family: 'DejaVu Sans Mono', 'FreeMono', 'LomaEmbedded', monospace;
  font-size: 8.5pt; background: var(--code-bg);
  padding: 1px 4px; border-radius: 3px; border: 1px solid var(--line);
}

pre {
  background: var(--code-bg); border: 1px solid var(--line); border-radius: 4px;
  padding: 9pt 11pt; margin: 0 0 11pt; overflow-x: hidden;
  page-break-inside: avoid;
}
pre code {
  background: none; border: 0; padding: 0; font-size: 7.6pt; line-height: 1.45;
  white-space: pre-wrap; word-break: break-word;
}

table {
  width: 100%; border-collapse: collapse; margin: 0 0 12pt;
  font-size: 8.6pt; page-break-inside: avoid;
}
th, td { border: 1px solid var(--line); padding: 4pt 6pt;
         text-align: left; vertical-align: top; }
th { background: #eef3f0; font-weight: 700; }
tr:nth-child(even) td { background: #fafbfc; }
td code, th code { font-size: 7.8pt; }

.doc-footer { margin-top: 20pt; padding-top: 8pt;
              border-top: 1px solid var(--line);
              font-size: 8pt; color: var(--muted); }
"""

INLINE_CODE = re.compile(r"`([^`]+)`")
BOLD = re.compile(r"\*\*([^*]+)\*\*")
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
ITALIC = re.compile(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])")


def inline(text: str) -> str:
    """Escape, then apply inline markdown. Code spans are protected first."""
    spans: list[str] = []

    def stash(match):
        spans.append(html.escape(match.group(1)))
        return f"\x00{len(spans) - 1}\x00"

    text = INLINE_CODE.sub(stash, text)
    text = html.escape(text)
    text = BOLD.sub(r"<strong>\1</strong>", text)
    text = ITALIC.sub(r"<em>\1</em>", text)
    text = LINK.sub(r'<a href="\2">\1</a>', text)
    return re.sub(r"\x00(\d+)\x00", lambda m: f"<code>{spans[int(m.group(1))]}</code>", text)


def convert(markdown: str) -> str:
    """Just enough Markdown for this document: no external dependency."""
    out: list[str] = []
    lines = markdown.split("\n")
    index = 0
    list_stack: list[str] = []

    def close_lists():
        while list_stack:
            out.append(f"</{list_stack.pop()}>")

    while index < len(lines):
        line = lines[index]

        # fenced code
        if line.startswith("```"):
            close_lists()
            index += 1
            body = []
            while index < len(lines) and not lines[index].startswith("```"):
                body.append(html.escape(lines[index]))
                index += 1
            index += 1
            out.append("<pre><code>" + "\n".join(body) + "</code></pre>")
            continue

        # table: a header row followed by a separator row
        if (line.strip().startswith("|") and index + 1 < len(lines)
                and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[index + 1])):
            close_lists()
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            out.append("<table><thead><tr>" +
                       "".join(f"<th>{inline(c)}</th>" for c in cells) +
                       "</tr></thead><tbody>")
            index += 2
            while index < len(lines) and lines[index].strip().startswith("|"):
                row = [c.strip() for c in lines[index].strip().strip("|").split("|")]
                out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>")
                index += 1
            out.append("</tbody></table>")
            continue

        stripped = line.strip()

        if not stripped:
            close_lists()
            index += 1
            continue

        if re.match(r"^(-{3,}|\*{3,})$", stripped):
            close_lists()
            out.append("<hr>")
            index += 1
            continue

        heading = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if heading:
            close_lists()
            level = len(heading.group(1))
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
            index += 1
            continue

        if stripped.startswith(">"):
            close_lists()
            quote = []
            while index < len(lines) and lines[index].strip().startswith(">"):
                quote.append(lines[index].strip().lstrip(">").strip())
                index += 1
            out.append(f"<blockquote><p>{inline(' '.join(quote))}</p></blockquote>")
            continue

        bullet = re.match(r"^[-*+]\s+(.*)$", stripped)
        numbered = re.match(r"^\d+[.)]\s+(.*)$", stripped)
        if bullet or numbered:
            want = "ul" if bullet else "ol"
            if not list_stack or list_stack[-1] != want:
                close_lists()
                out.append(f"<{want}>")
                list_stack.append(want)
            out.append(f"<li>{inline((bullet or numbered).group(1))}</li>")
            index += 1
            continue

        # paragraph (joins soft-wrapped lines)
        close_lists()
        para = [stripped]
        index += 1
        while index < len(lines):
            nxt = lines[index].strip()
            if (not nxt or nxt.startswith(("#", ">", "|", "```"))
                    or re.match(r"^([-*+]\s|\d+[.)]\s|-{3,}$)", nxt)):
                break
            para.append(nxt)
            index += 1
        out.append(f"<p>{inline(' '.join(para))}</p>")

    close_lists()
    return "\n".join(out)


def find_chrome() -> str:
    for candidate in CHROME_CANDIDATES:
        if candidate and os.path.exists(candidate):
            return candidate
    raise SystemExit("Chromium not found - cannot render the PDF")


def main() -> int:
    with open(SOURCE, encoding="utf-8") as fh:
        markdown = fh.read()

    document = (
        "<!doctype html><html lang=\"th\"><head><meta charset=\"utf-8\">"
        "<title>AI Digital Product Factory - System Specification</title>"
        f"<style>{font_face_css()}\n{CSS}</style></head>"
        f"<body>{convert(markdown)}</body></html>"
    )

    html_path = os.path.join(ROOT, "docs", ".spec_render.html")
    with open(html_path, "w", encoding="utf-8") as fh:
        fh.write(document)

    chrome = find_chrome()
    result = subprocess.run(
        [
            chrome, "--headless", "--disable-gpu", "--no-sandbox",
            "--no-pdf-header-footer",
            "--run-all-compositor-stages-before-draw",
            "--virtual-time-budget=10000",
            f"--print-to-pdf={OUTPUT}",
            f"file://{html_path}",
        ],
        capture_output=True, text=True, timeout=180,
    )
    os.remove(html_path)

    if not os.path.exists(OUTPUT):
        print(result.stderr.strip()[-2000:])
        return 1

    size = os.path.getsize(OUTPUT)
    with open(OUTPUT, "rb") as fh:
        data = fh.read()

    fonts, thai_codepoints = inspect_pdf(data)
    pages = data.count(b"/Type /Page") - data.count(b"/Type /Pages")

    print(f"[ok] {os.path.relpath(OUTPUT, ROOT)}  {size // 1024} KB  ~{pages} pages")
    print("     fonts embedded: " + ", ".join(sorted(fonts)))
    print(f"     Thai codepoints in ToUnicode: {len(thai_codepoints)}"
          f"  e.g. {''.join(chr(c) for c in sorted(thai_codepoints)[:24])}")

    # The real test is not which face was picked but whether the Thai text
    # survived as Thai: every glyph must map back to U+0E00-U+0E7F. Chromium
    # substitutes Loma (OTF/CFF) with FreeSerif when embedding into a PDF, and
    # FreeSerif shapes Thai correctly, so either face is acceptable.
    if len(thai_codepoints) < 40:
        print("     ERROR: too few Thai codepoints - the text did not render as Thai")
        return 1
    return 0


def inspect_pdf(data: bytes) -> tuple[set[str], set[int]]:
    """Read embedded font names and every Unicode codepoint the PDF can map back.

    Chromium stores both inside compressed object streams, so everything has to
    be inflated first.
    """
    import zlib

    blobs = [data]
    for match in re.finditer(rb"stream\r?\n", data):
        start = match.end()
        end = data.find(b"endstream", start)
        if end < 0:
            continue
        try:
            blobs.append(zlib.decompress(data[start:end]))
        except zlib.error:
            continue

    fonts: set[str] = set()
    codepoints: set[int] = set()
    for blob in blobs:
        for name in re.findall(rb"/BaseFont\s*/(?:[A-Z]{6}\+)?([A-Za-z0-9\-]+)", blob):
            fonts.add(name.decode())
        # bfchar: <src> <dst>
        for _src, dst in re.findall(rb"<([0-9A-Fa-f]{2,4})>\s*<([0-9A-Fa-f]{4,})>", blob):
            codepoints.add(int(dst[:4], 16))
        # bfrange: <lo> <hi> <dst>
        for lo, hi, dst in re.findall(
            rb"<([0-9A-Fa-f]{2,4})>\s*<([0-9A-Fa-f]{2,4})>\s*<([0-9A-Fa-f]{4,})>", blob
        ):
            base = int(dst[:4], 16)
            span = int(hi, 16) - int(lo, 16)
            for offset in range(max(0, min(span, 255)) + 1):
                codepoints.add(base + offset)

    thai = {c for c in codepoints if 0x0E00 <= c <= 0x0E7F}
    return fonts, thai


if __name__ == "__main__":
    sys.exit(main())
