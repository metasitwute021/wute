#!/usr/bin/env python3
"""Run the whole factory offline: no n8n, no OpenAI, no Etsy, no database.

    python3 build/simulate.py [--keep out.pdf]

Every Code node is lifted out of the built workflow and executed in order
against a mocked n8n runtime, with the agent replies faked. The result is the
real PDF the real pipeline would produce.

This exists because the previous system was debugged one paid run at a time:
six runs died on gates the data feeding them could never satisfy. A gate that
cannot be tested offline gets tested with money.

The fixture is deliberately unhelpful - a model answering at the short end of
every range, with the awkward shapes real replies arrive in.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from wf_factory import DRY_RUN_JPEG, MONTHS  # noqa: E402

WORKFLOW = os.path.join(ROOT, "workflows", "01_planner_factory.json")

SECTIONS = [
    ("Year at a Glance", "grid"),
    ("Goals", "lined"),
    ("Habit Tracker", "grid"),
    ("Sleep Log", "grid"),
    ("Brain Dump", "lined"),
    ("Month in Review", "lined"),
]


def concept_reply() -> dict:
    return {
        "niche": "shift workers on rotating schedules",
        "product_name": "Shift Worker Sleep and Life Planner",
        "one_liner": "A planner that fits a week where Monday starts at 10pm.",
        "buyer": "Nurses, drivers and factory staff on rotating shifts.",
        "buyer_problem": "Ordinary planners assume you sleep at night.",
        "search_phrase": "shift worker planner",
        # Deliberately awkward: a comma string instead of an array, a phrase
        # far over the 20-character tag limit, and a duplicate.
        "keywords": ("shift worker planner, rotating shift schedule planner for nurses, "
                     "sleep log, night shift, undated planner, shift planner, "
                     "nurse planner, sleep tracker, shift work, shift worker planner"),
        "extra_sections": [
            {"title": title, "kind": kind, "purpose": f"where the buyer handles {title.lower()}"}
            for title, kind in SECTIONS
        ],
        "tone": "calm, practical",
        "colour_direction": "deep navy with warm sand accents",
    }


def writer_reply(*, months=12, sections=None, marker=None) -> dict:
    reply = {
        "cover_title": "Shift Worker Sleep and Life Planner",
        "cover_subtitle": "For weeks that do not start on Monday",
        "welcome_title": "How to use this planner",
        "welcome_lines": [
            "This planner is undated, so you start it the day you open it.",
            "Write the dates into the month grid yourself.",
            "The tabs on the right edge jump to any month.",
            "Use the sleep log after each shift block, not each day.",
            "Nothing here has to be filled in to be useful.",
        ],
        "month_prompts": [
            {"month": n + 1, "prompts": ["What must not slip this month?",
                                         "One thing to protect your sleep"]}
            for n in range(months)
        ],
        "sections": [],
    }
    for title, kind in (sections if sections is not None else SECTIONS):
        if kind == "grid":
            reply["sections"].append({
                "title": title, "kind": "grid",
                "intro": f"Track {title.lower()} without thinking about it.",
                "instructions": [f"Fill one row per entry in {title.lower()}."],
                "columns": ["Item", "M", "T", "W", "T", "F", "S", "S"],
                "row_labels": ["Sleep 7h", "Water", "Walk"],
                "rows": 14,
            })
        else:
            reply["sections"].append({
                "title": title, "kind": "lined",
                "intro": f"Space to think about {title.lower()}.",
                "instructions": ["Write as much or as little as you like."],
                "prompts": ["What went well?", "What drained you?", "What changes?"],
            })
    reply["credits"] = "Made by a small shop."
    if marker:
        reply["welcome_lines"].append(marker)
    return reply


def art_reply(*, bad=False) -> dict:
    good = ("A calm flat composition of soft overlapping arcs in deep navy and warm "
            "sand, gentle gradients, generous empty space, printable and quiet.")
    return {
        "cover_prompt": ("An elegant title card with the planner name in gold lettering."
                         if bad else good),
        "section_prompts": [good, good],
        "thumbnail_prompt": good,
        "palette": "deep navy, warm sand, off white",
    }


def listing_reply(*, tags=13, description_length=600) -> dict:
    return {
        "title": "Shift Worker Sleep and Life Planner Undated Digital Planner PDF",
        "description": ("A planner built for people whose week does not start on "
                        "Monday morning. " * (description_length // 70)),
        "tags": [f"shift planner {n}" for n in range(tags)],
        "materials": ["pdf file", "digital download"],
        "who_its_for": ["Nurses", "Drivers"],
        "whats_included": ["12 month grids", "Sleep log"],
        "price_usd": 14,
    }


def chat(payload: dict) -> dict:
    """An OpenAI chat completion carrying the given JSON."""
    return {"choices": [{"finish_reason": "stop",
                         "message": {"content": json.dumps(payload)}}]}


# The order Code nodes execute in on a successful, non-publishing run, and
# which mocked HTTP reply feeds each one.
PIPELINE = [
    ("Planner Config", None),
    ("Prompt Library", None),
    ("Start Run", None),
    ("Build Concept Prompt", None),
    ("Parse Concept", "concept"),
    ("Check Duplicate", None),
    ("Build Writer Prompt", None),
    ("Parse Writer", "writer"),
    ("Build Art Prompt", None),
    ("Parse Art", "art"),
    ("Image Jobs", None),
    ("Gather Images", None),
    ("Build PDF", None),
    ("QA Gate", None),
    ("Build Listing Prompt", None),
    ("Parse Listing", "listing"),
    ("Prepare Etsy Draft", None),
    ("Summarise Run", None),
]

HARNESS = """
const NODES = %s;      // node name -> jsCode
const ORDER = %s;      // [name, replyKey]
const REPLIES = %s;    // replyKey -> the mocked HTTP response
const IMAGES = %s;     // role -> base64

const results = {};    // node name -> array of items

const wrap = (list) => ({
  first: () => list[0],
  all: () => list,
  last: () => list[list.length - 1],
});

const $ = (name) => {
  if (!(name in results)) {
    throw new Error(`node "${name}" was read before it ran`);
  }
  return wrap(results[name]);
};

// Nodes that are fed by something other than the previous node in ORDER.
const FEED = {
  'Planner Config': () => [{ json: {} }],
  'Recent Products': () => [],
  'Gather Images': () => Object.keys(IMAGES).map(
    (role) => ({ json: { role, b64: IMAGES[role] } })),
};

async function main() {
  results['Recent Products'] = [];
  let previous = null;
  for (const [name, replyKey] of ORDER) {
    let input;
    if (FEED[name]) input = FEED[name]();
    else if (replyKey) input = [{ json: REPLIES[replyKey] }];
    else input = results[previous];

    const $input = wrap(input);
    const $json = input[0] ? input[0].json : {};
    const $execution = { id: 'sim', url: null, customData: {} };
    const $getWorkflowStaticData = () => ({});
    const run = new Function(
      '$', '$input', '$json', '$execution', '$getWorkflowStaticData',
      'return (async () => {' + NODES[name] + '})();');
    try {
      const out = await run($, $input, $json, $execution, $getWorkflowStaticData);
      results[name] = out;
    } catch (error) {
      console.log(JSON.stringify({ failed_at: name, message: String(error.message) }));
      return;
    }
    previous = name;
  }

  const summary = results['Summarise Run'][0].json;
  const pdf = results['Build PDF'][0].json.pdf;
  if (process.argv[2]) {
    require('fs').writeFileSync(process.argv[2], Buffer.from(pdf.base64, 'base64'));
  }
  console.log(JSON.stringify({
    ok: true,
    summary,
    pdf: { pages: pdf.page_count, links: pdf.link_count, bytes: pdf.bytes },
    etsy_body: results['Prepare Etsy Draft'][0].json.etsy_body,
  }));
}

main();
"""


def run_pipeline(tmp: str, code_of: dict, replies: dict,
                 pdf_path: str | None = None) -> dict:
    images = {"cover": DRY_RUN_JPEG, "thumbnail": DRY_RUN_JPEG,
              "section_1": DRY_RUN_JPEG, "section_2": DRY_RUN_JPEG}
    script = os.path.join(tmp, "sim.js")
    with open(script, "w", encoding="utf-8") as fh:
        fh.write(HARNESS % (json.dumps(code_of), json.dumps(PIPELINE),
                            json.dumps(replies), json.dumps(images)))
    args = ["node", script] + ([pdf_path] if pdf_path else [])
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        return {"crashed": result.stderr.strip().splitlines()[-1][:300]}
    return json.loads(result.stdout.strip().splitlines()[-1])


def default_replies() -> dict:
    return {
        "concept": chat(concept_reply()),
        "writer": chat(writer_reply()),
        "art": chat(art_reply()),
        "listing": chat(listing_reply()),
    }


def happy_path(tmp: str, code_of: dict, pdf_path: str | None) -> int:
    print("=== a run that should succeed ===")
    report = run_pipeline(tmp, code_of, default_replies(), pdf_path)
    if report.get("crashed"):
        print(f"  [CRASH] {report['crashed']}")
        return 1
    if report.get("failed_at"):
        print(f"  [FAIL ] stopped at {report['failed_at']}: {report['message'][:200]}")
        return 1

    summary, pdf, etsy = report["summary"], report["pdf"], report["etsy_body"]
    failures = 0

    def check(label, condition, detail):
        nonlocal failures
        if condition:
            print(f"  [pass ] {label}: {detail}")
        else:
            print(f"  [FAIL ] {label}: {detail}")
            failures += 1

    check("planner built", pdf["pages"] >= 20,
          f"{pdf['pages']} pages, {pdf['bytes']} bytes")
    check("every page navigable", pdf["links"] >= pdf["pages"],
          f"{pdf['links']} links across {pdf['pages']} pages")
    check("13 Etsy tags", len(summary["listing_tags"]) == 13,
          f"{len(summary['listing_tags'])} tags")
    check("tags within 20 chars",
          all(len(t) <= 20 for t in summary["listing_tags"]),
          f"longest is {max(len(t) for t in summary['listing_tags'])} chars")
    check("no duplicate tags",
          len(set(summary["listing_tags"])) == len(summary["listing_tags"]),
          f"{len(set(summary['listing_tags']))} distinct")
    check("title within Etsy's limit", len(etsy["title"]) <= 140,
          f"{len(etsy['title'])} chars")
    check("all six sections survived", len(summary["sections"]) == 6,
          ", ".join(summary["sections"]))
    check("listing is a digital download", etsy["listing_type"] == "download",
          f"listing_type={etsy['listing_type']}, state={etsy['state']}")
    check("description mentions delivery",
          "digital download" in etsy["description"].lower(),
          f"{len(etsy['description'])} chars")
    return failures


SABOTAGE = [
    ("a concept with only three sections",
     lambda r: r.update({"concept": chat({**concept_reply(),
                                          "extra_sections": [
                                              {"title": t, "kind": k, "purpose": "x"}
                                              for t, k in SECTIONS[:3]]})}),
     "Parse Concept", "at least 6"),

    ("a concept that names a year",
     lambda r: r.update({"concept": chat({**concept_reply(),
                                          "product_name": "2027 Shift Planner"})}),
     "Parse Concept", "names a year"),

    ("a concept with too few usable keywords",
     lambda r: r.update({"concept": chat({**concept_reply(),
                                          "keywords": ["a", "b", "shift"]})}),
     "Parse Concept", "keywords"),

    ("a writer that skipped half the months",
     lambda r: r.update({"writer": chat(writer_reply(months=5))}),
     "Parse Writer", "of 12 months"),

    ("a draft marker left in the copy",
     lambda r: r.update({"writer": chat(writer_reply(marker="TODO: write this bit"))}),
     "Parse Writer", "Draft markers"),

    ("art direction that asks for lettering",
     lambda r: r.update({"art": chat(art_reply(bad=True))}),
     "Parse Art", "type"),

    # The concept still passes its own gate (eight keywords is the minimum
    # there), so this isolates the listing gate: eight plus two is ten, and
    # Etsy wants thirteen.
    ("a listing with too few tags to top up to thirteen",
     lambda r: r.update({"listing": chat({**listing_reply(), "tags": ["ab", "cd"]}),
                         "concept": chat({**concept_reply(), "keywords": [
                             "shift planner", "night shift", "sleep log", "nurse planner",
                             "undated planner", "shift work", "rota planner",
                             "sleep tracker"]})}),
     "Parse Listing", "tags"),

    ("a listing description that is too short",
     lambda r: r.update({"listing": chat({**listing_reply(), "description": "Buy it."})}),
     "Parse Listing", "description"),

    ("a shouting listing title",
     lambda r: r.update({"listing": chat({**listing_reply(),
                                          "title": "BEST Shift Worker Planner Ever"})}),
     "Parse Listing", "shouts"),

    ("a model that answered with prose instead of JSON",
     lambda r: r.update({"concept": {"choices": [{"finish_reason": "stop",
                                                  "message": {"content": "Sure! Here you go."}}]}}),
     "Parse Concept", "not valid JSON"),

    ("a model that ran out of output tokens",
     lambda r: r.update({"writer": {"choices": [{"finish_reason": "length",
                                                 "message": {"content": "{\"cover_title\""}}]}}),
     "Parse Writer", "output tokens"),
]


def negative_checks(tmp: str, code_of: dict) -> int:
    """A gate that never blocks anything is not a gate.

    Each of these is a defect that reached a customer, or would have. The gate
    must stop it, and it must stop it at the named node with a message that
    says what to do - an error that only says "cannot read property of
    undefined" costs an hour of reading JSON.
    """
    print("\n=== defects that must be stopped ===")
    failures = 0
    for label, mutate, expect_node, expect_text in SABOTAGE:
        replies = default_replies()
        mutate(replies)
        report = run_pipeline(tmp, code_of, replies)
        if report.get("crashed"):
            print(f"  [CRASH] {label}: {report['crashed'][:120]}")
            failures += 1
        elif report.get("ok"):
            print(f"  [FAIL ] {label}: shipped anyway")
            failures += 1
        elif report["failed_at"] != expect_node:
            print(f"  [FAIL ] {label}: stopped at {report['failed_at']}, "
                  f"expected {expect_node}")
            failures += 1
        elif expect_text.lower() not in report["message"].lower():
            print(f"  [FAIL ] {label}: message does not mention '{expect_text}': "
                  f"{report['message'][:120]}")
            failures += 1
        else:
            print(f"  [pass ] {label}")
            print(f"          -> {report['message'].splitlines()[0][:110]}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--keep", metavar="PATH",
                        help="write the simulated planner PDF here")
    args = parser.parse_args()

    with open(WORKFLOW, encoding="utf-8") as fh:
        document = json.load(fh)
    code_of = {n["name"]: n["parameters"].get("jsCode", "")
               for n in document["nodes"] if n["parameters"].get("jsCode")}

    missing = [name for name, _ in PIPELINE if name not in code_of]
    if missing:
        print(f"these nodes are not in the built workflow: {missing}")
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        pdf_path = os.path.abspath(args.keep) if args.keep else None
        failures = happy_path(tmp, code_of, pdf_path)
        failures += negative_checks(tmp, code_of)

    print()
    if failures:
        print(f"{failures} failure(s) - a real run would not be safe")
        return 1
    print("the pipeline builds a complete planner and stops every known defect")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
