#!/usr/bin/env python3
"""Static checks that run without n8n, OpenAI, Etsy or a database.

    python3 build/verify.py

Every check here exists because something shipped broken once. They are cheap
and they run offline, which is the point: a defect caught here costs nothing,
and the same defect caught by n8n costs a paid run and a rejected product.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from js_pdf import PDF_LIB_JS  # noqa: E402

WORKFLOW_DIR = os.path.join(ROOT, "workflows")

# A 1x1 black JPEG. Enough for the writer to parse an SOF marker and embed it.
PLACEHOLDER_JPEG = (
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="
)


def _node(script: str, *args: str) -> subprocess.CompletedProcess:
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False,
                                     encoding="utf-8") as fh:
        fh.write(script)
        path = fh.name
    try:
        return subprocess.run(["node", path, *args], capture_output=True, text=True)
    finally:
        os.unlink(path)


def check_code_nodes() -> list[str]:
    """Parse every Code node body with node --check.

    A syntax error inside a Code node is invisible until n8n runs that node,
    which can be twenty minutes and several dollars into a run.
    """
    problems: list[str] = []
    parsed = 0
    for filename in sorted(os.listdir(WORKFLOW_DIR)):
        if not filename.endswith(".json"):
            continue
        with open(os.path.join(WORKFLOW_DIR, filename), encoding="utf-8") as fh:
            document = json.load(fh)
        for node in document["nodes"]:
            source = node["parameters"].get("jsCode")
            if not source:
                continue
            parsed += 1
            with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False,
                                             encoding="utf-8") as tmp:
                # Code nodes run inside an async function, so top-level await
                # and bare `return` are legal there but not in a plain script.
                tmp.write("async function __n8n() {\n" + source + "\n}\n")
                path = tmp.name
            result = subprocess.run(["node", "--check", path],
                                    capture_output=True, text=True)
            os.unlink(path)
            if result.returncode != 0:
                detail = result.stderr.strip().splitlines()
                problems.append(f"{filename} / {node['name']}: "
                                + " | ".join(detail[:3]))
    print(f"[ok] parsed {parsed} Code node bodies")
    return problems


def check_undeclared() -> list[str]:
    """Catch identifiers a Code node uses but never declares.

    This is the check that would have caught `buildKeywords is not defined` and
    `profile is not defined` before they cost a run each. It looks at both
    property access (`foo.bar`) and calls (`foo(...)`), because the first
    version only looked at property access and missed a bare function call.
    """
    # Language keywords are not identifiers. `if (x)` and `for (const a of b)`
    # both match "word followed by (" and would otherwise be reported forever,
    # which is how a checker gets switched off and stops catching real bugs.
    known = set("""
        if else for while do switch case default break continue return throw
        try catch finally function class new delete typeof instanceof in of
        this super yield await async void with debugger let const var extends
        get set static

        $ $input $json $node $items $workflow $execution $env $vars $now $today
        $getWorkflowStaticData $binary $parameter $prevNode $runIndex $itemMatching
        console JSON Math Date Object Array String Number Boolean Buffer Promise
        Set Map WeakMap RegExp Error TypeError RangeError Intl parseInt parseFloat
        isNaN isFinite encodeURIComponent decodeURIComponent encodeURI decodeURI
        undefined null true false NaN Infinity require process globalThis
        setTimeout structuredClone TextEncoder TextDecoder URLSearchParams
    """.split())

    declare = re.compile(
        r"\b(?:const|let|var|function|class)\s+([A-Za-z_$][\w$]*)"
        r"|\bfunction\s*\(|\b([A-Za-z_$][\w$]*)\s*=>"
        r"|(?:const|let|var)\s*(?:\{|\[)([^}\]]*)(?:\}|\])"
    )
    param = re.compile(r"\(([^()]*)\)\s*=>|function\s*[\w$]*\s*\(([^()]*)\)"
                       r"|catch\s*\(\s*([A-Za-z_$][\w$]*)\s*\)")
    use = re.compile(r"\b([A-Za-z_$][\w$]*)\s*(?:\.|\()")

    problems: list[str] = []
    scanned = 0
    for filename in sorted(os.listdir(WORKFLOW_DIR)):
        if not filename.endswith(".json"):
            continue
        with open(os.path.join(WORKFLOW_DIR, filename), encoding="utf-8") as fh:
            document = json.load(fh)
        for node in document["nodes"]:
            source = node["parameters"].get("jsCode")
            if not source:
                continue
            scanned += 1
            body = strip_literals(source)
            declared = set(known)
            for match in declare.finditer(body):
                for group in match.groups():
                    if not group:
                        continue
                    for name in re.split(r"[,\s:]+", group):
                        name = name.strip().lstrip(".")
                        if name.isidentifier():
                            declared.add(name)
            for match in param.finditer(body):
                for group in match.groups():
                    if not group:
                        continue
                    for name in re.split(r"[,\s]+", group):
                        name = name.strip().split("=")[0].strip()
                        if name.isidentifier():
                            declared.add(name)
            for match in use.finditer(body):
                name = match.group(1)
                if name in declared or name.isupper():
                    continue
                # A property read (`foo.bar.baz`) only names `foo`.
                start = match.start(1)
                if start and body[start - 1] in ".$":
                    continue
                problems.append(f"{filename} / {node['name']}: "
                                f"uses '{name}' which is never declared")
    print(f"[ok] scanned {scanned} Code nodes for undeclared identifiers")
    return sorted(set(problems))


def strip_literals(source: str) -> str:
    """Blank out strings, template literals, regexes and comments.

    Written by hand rather than with a regex because a regex cannot tell a
    division sign from the start of a regex literal, and getting that wrong
    made the scanner report identifiers that only existed inside strings -
    `label` out of `label(?:s|led)?`, and every single-letter regex flag.
    """
    # A `/` begins a regex only where a value is expected. After a name, a
    # number or a closing bracket it is division. This is the standard
    # heuristic and it is exact for everything this project writes.
    value_expected = re.compile(r"(?:[({\[,;:=!&|?+\-*%^~]|=>|\b(?:return|typeof|"
                                r"case|in|of|new|delete|void|instanceof|do|else)\b)\s*$")

    out = []
    i = 0
    n = len(source)
    while i < n:
        ch = source[i]
        nxt = source[i + 1] if i + 1 < n else ""
        if ch == "/" and nxt not in "/*":
            prefix = "".join(out).rstrip()
            if not prefix or value_expected.search(prefix):
                i += 1
                in_class = False
                while i < n:
                    if source[i] == "\\":
                        i += 2
                        continue
                    if source[i] == "[":
                        in_class = True
                    elif source[i] == "]":
                        in_class = False
                    elif source[i] == "/" and not in_class:
                        i += 1
                        break
                    elif source[i] == "\n":
                        break            # not a regex after all; bail out
                    i += 1
                while i < n and source[i] in "gimsuyvd":
                    i += 1
                out.append(" ")
                continue
        if ch == "/" and nxt == "/":
            while i < n and source[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            i += 2
            while i + 1 < n and not (source[i] == "*" and source[i + 1] == "/"):
                i += 1
            i += 2
            continue
        if ch in "\"'`":
            quote = ch
            i += 1
            out.append(" ")
            while i < n:
                if source[i] == "\\":
                    i += 2
                    continue
                if quote == "`" and source[i] == "$" and i + 1 < n and source[i + 1] == "{":
                    # Template holes contain real code and must be kept. They
                    # are padded with spaces: without that, `${a} x ${b.c}`
                    # collapsed to "ab.c" and the scanner reported an
                    # identifier that appears nowhere in the file.
                    depth = 1
                    i += 2
                    start = i
                    while i < n and depth:
                        if source[i] == "{":
                            depth += 1
                        elif source[i] == "}":
                            depth -= 1
                        i += 1
                    out.append(" " + source[start:i - 1] + " ")
                    continue
                if source[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def check_node_references() -> list[str]:
    """Every $('Node Name') must name a node that exists in the same workflow.

    Renaming a node is a two-character edit that fails only at run time, on a
    different node than the one that was edited.
    """
    problems: list[str] = []
    ref = re.compile(r"\$\(\\?['\"]([^'\"\\]+)\\?['\"]\)")
    comment = re.compile(r"//[^\n]*|/\*.*?\*/", re.S)
    checked = 0
    for filename in sorted(os.listdir(WORKFLOW_DIR)):
        if not filename.endswith(".json"):
            continue
        with open(os.path.join(WORKFLOW_DIR, filename), encoding="utf-8") as fh:
            document = json.load(fh)
        names = {n["name"] for n in document["nodes"]}
        for node in document["nodes"]:
            source = comment.sub(" ", json.dumps(node["parameters"]))
            for target in set(ref.findall(source)):
                checked += 1
                if target not in names:
                    problems.append(f"{filename} / {node['name']}: refers to "
                                    f"$('{target}'), which is not in this workflow")
    print(f"[ok] resolved {checked} $('node') references")
    return problems


def check_calendar() -> list[str]:
    """The month grid must agree with a real calendar, for every month.

    Calendars are the one part of a planner a buyer checks immediately, and
    they are trivially verifiable, so they are verified exhaustively rather
    than spot-checked: every month of several years, both week starts.
    """
    script = PDF_LIB_JS + """
const out = [];
for (const year of [2024, 2025, 2026, 2027, 2028]) {
  for (let month = 1; month <= 12; month += 1) {
    for (const mon of [true, false]) {
      const m = monthMatrix(year, month, mon);
      const flat = m.rows.flat().filter((d) => d !== null);
      out.push({ year, month, mon, days: m.days, seen: flat.length,
                 first: flat[0], last: flat[flat.length - 1],
                 firstIndex: m.rows[0].findIndex((d) => d !== null) });
    }
  }
}
console.log(JSON.stringify(out));
"""
    result = _node(script)
    if result.returncode != 0:
        return ["calendar harness crashed:\n" + result.stderr.strip()]

    import calendar as pycal
    problems = []
    for row in json.loads(result.stdout.strip().splitlines()[-1]):
        year, month = row["year"], row["month"]
        days = pycal.monthrange(year, month)[1]
        if row["days"] != days or row["seen"] != days:
            problems.append(f"{year}-{month:02d}: grid has {row['seen']} days, "
                            f"the month has {days}")
        if row["first"] != 1 or row["last"] != days:
            problems.append(f"{year}-{month:02d}: runs {row['first']}..{row['last']}")
        # Where the 1st sits in the first row is the whole point of the grid.
        weekday = pycal.weekday(year, month, 1)          # Monday = 0
        expected = weekday if row["mon"] else (weekday + 1) % 7
        if row["firstIndex"] != expected:
            problems.append(
                f"{year}-{month:02d} ({'Mon' if row['mon'] else 'Sun'} start): the 1st "
                f"is in column {row['firstIndex']}, should be {expected}")
    print(f"[ok] calendar grid matches 120 real months (2024-2028, both week starts)")
    return problems


def check_pdf() -> list[str]:
    """Build a planner with the real writer and inspect the bytes."""
    script = PDF_LIB_JS + f"\nconst JPEG = '{PLACEHOLDER_JPEG}';\n" + """
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
                'August', 'September', 'October', 'November', 'December'];
const tabs = [{ label: 'Contents', anchor: 'contents' }]
  .concat(MONTHS.map((m, i) => ({ label: m.slice(0, 3), anchor: `m${i + 1}` })));

const pages = [
  { type: 'image', jpeg_base64: JPEG, full_bleed: true },
  { type: 'text', cover: true, title: 'Undated Planner', subtitle: 'smoke test',
    anchor: 'start', lines: ['Intro'], footer: 'smoke' },
  { type: 'text', title: 'Contents', anchor: 'contents',
    subtitle: 'Tap a line to jump.',
    index: MONTHS.map((m, i) => ({ label: m, anchor: `m${i + 1}` })), footer: 'smoke' },
];
MONTHS.forEach((name, index) => {
  pages.push({ type: 'month', title: name, anchor: `m${index + 1}`,
    month_number: index + 1, year: null, week_starts_monday: true,
    side_title: 'This month', side_lines: ['What matters most?', 'One habit to keep'],
    footer: `smoke | ${name}` });
});
pages.push({ type: 'grid', title: 'Habit Tracker', anchor: 'habits',
  subtitle: 'Fill a box each day.', lines: ['Pick habits you can keep.'],
  columns: ['Habit', 'M', 'T', 'W', 'T', 'F', 'S', 'S'], rows: 12,
  row_labels: ['Water', 'Walk', 'Read'], footer: 'smoke' });
pages.push({ type: 'lined', title: 'Notes', anchor: 'notes',
  lines: ['What went well this month?', 'What will you change?'],
  lines_per_prompt: 3, footer: 'smoke' });

const result = buildPdf({
  width: 595.28, height: 841.89, tabs, pages,
  info: { title: 'Undated Planner', subject: 'verification', keywords: 'a, b' },
});
require('fs').writeFileSync(process.argv[2], result.buffer);
console.log(JSON.stringify({
  pages: result.page_count, bytes: result.buffer.length,
  links: result.link_count, broken: result.broken_links,
  dropped: result.dropped_index_rows,
}));
"""
    with tempfile.TemporaryDirectory() as tmp:
        output = os.path.join(tmp, "smoke.pdf")
        result = _node(script, output)
        if result.returncode != 0:
            return ["PDF harness crashed:\n" + result.stderr.strip()]
        stats = json.loads(result.stdout.strip().splitlines()[-1])
        with open(output, "rb") as fh:
            data = fh.read()

    problems = []
    if not data.startswith(b"%PDF-1.4"):
        problems.append("PDF header missing")
    if not data.rstrip().endswith(b"%%EOF"):
        problems.append("PDF trailer missing")
    if b"/DCTDecode" not in data:
        problems.append("JPEG image was not embedded")
    if stats["dropped"]:
        problems.append(f"{stats['dropped']} contents rows did not fit")
    if stats["broken"]:
        problems.append(f"{stats['broken']} links pointed at nothing")

    # Walk the cross-reference table: every offset must land exactly on the
    # object it claims. A wrong offset is the classic hand-rolled-PDF bug and
    # readers fail on it in ways that are painful to debug from n8n.
    tail = data[-2048:].decode("latin1")
    startxref = int(tail.rsplit("startxref", 1)[1].strip().split()[0])
    if data[startxref:startxref + 4] != b"xref":
        problems.append("startxref does not point at the xref table")
    else:
        xref = data[startxref:].decode("latin1")
        declared = int(re.match(r"xref\s+0\s+(\d+)\s+", xref).group(1))
        entries = re.findall(r"(\d{10}) (\d{5}) ([nf])", xref[: declared * 20 + 64])
        if len(entries) != declared:
            problems.append(f"xref declares {declared} objects, lists {len(entries)}")
        for index, (offset, _gen, kind) in enumerate(entries):
            if kind == "f":
                continue
            head = data[int(offset):int(offset) + 24].decode("latin1")
            if not re.match(rf"^{index} 0 obj", head):
                problems.append(f"xref offset for object {index} does not point at it")

    annots = re.findall(rb"/Subtype /Link .*?/Dest \[(\d+) 0 R", data, re.S)
    if len(annots) != stats["links"]:
        problems.append(f"builder reported {stats['links']} links, file has {len(annots)}")
    object_types = dict(re.findall(rb"\n(\d+) 0 obj\n<< /Type /(\w+)", data))
    for target in set(annots):
        if object_types.get(target) != b"Page":
            problems.append(f"link destination {int(target)} is not a page")

    pages_declared = int(re.search(rb"/Type /Pages /Count (\d+)", data).group(1))
    page_objects = len(re.findall(rb"/Type /Page[^s]", data))
    if len({pages_declared, page_objects, stats["pages"]}) != 1:
        problems.append(f"page count mismatch: {page_objects} objects, "
                        f"/Count {pages_declared}, builder said {stats['pages']}")

    print(f"[ok] PDF smoke test: {stats['pages']} pages, {stats['bytes']} bytes, "
          f"{stats['links']} links, 12 month grids")
    return problems


def check_sql() -> list[str]:
    """Parse the schema with the grammar PostgreSQL itself uses."""
    path = os.path.join(ROOT, "db", "schema.sql")
    if not os.path.exists(path):
        return ["db/schema.sql has not been generated"]
    try:
        import pglast
    except ImportError:
        print("[warn] pglast not installed - SQL not parsed")
        return []
    with open(path, encoding="utf-8") as fh:
        sql = fh.read()
    try:
        statements = pglast.parse_sql(sql)
    except Exception as exc:  # pglast raises its own error types
        return [f"schema.sql does not parse: {exc}"]
    print(f"[ok] parsed {len(statements)} PostgreSQL statements")
    return []


def main() -> int:
    problems: list[str] = []
    problems += check_code_nodes()
    problems += check_node_references()
    problems += check_undeclared()
    problems += check_calendar()
    problems += check_pdf()
    problems += check_sql()

    print()
    if problems:
        for problem in problems:
            print(f"  - {problem}")
        print(f"\n{len(problems)} problem(s) found")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
