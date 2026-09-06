"""The four agent prompts, and the contracts their replies must satisfy.

Deliberately small. The old suite had eight agents and most of what they
produced was thrown away or contradicted by code. Here the model does the one
thing it is good at - writing the words for a niche - and never decides layout,
never lays out a calendar, and never invents a file list.

Every prompt ends with a JSON contract because the reply is parsed, not read.
"""

from __future__ import annotations

import json

PROMPT_VERSION = "planner-v1"

# --------------------------------------------------------------------------
# 1. Concept: what planner is worth making
# --------------------------------------------------------------------------
CONCEPT_SYSTEM = """
You choose what undated digital planner a small Etsy shop should make next.

You are picking a NICHE, not a generic planner. "2027 Planner" is worthless -
there are two hundred thousand of them. "Shift Worker's Sleep & Life Planner"
is a product, because the person searching for it is not served by a generic
one and will pay more.

Rules that come from how this shop actually sells:
- The buyer must be findable in one Etsy search phrase they would really type.
- The planner is UNDATED: never name a year, a specific date, or "2025/2026".
- No licensed characters, no brand names, no medical or financial advice, no
  claims about outcomes ("lose 10kg", "double your income").
- The niche must need at least six distinct extra pages beyond the twelve
  months, or it is not a niche, it is a colour scheme.
- English only. The shop sells to the US, UK and Australia.

Pick a niche where a monthly calendar genuinely helps. If the audience would
be better served by a checklist, choose a different audience.
""".strip()

CONCEPT_CONTRACT = {
    "niche": "short phrase, e.g. 'shift workers on rotating schedules'",
    "product_name": "the listing title's subject, 4-8 words, no year",
    "one_liner": "one sentence a buyer would nod at",
    "buyer": "who this is for, one sentence",
    "buyer_problem": "the specific problem, one sentence",
    "search_phrase": "what they type into Etsy, 2-5 words",
    "keywords": ["8-13 short phrases, each 20 characters or fewer"],
    "extra_sections": [
        {"title": "section name, 1-3 words",
         "kind": "one of: grid, lined",
         "purpose": "one sentence on what the buyer does with it"}
    ],
    "tone": "two or three adjectives for the writing voice",
    "colour_direction": "a palette in words, no hex codes",
}

# --------------------------------------------------------------------------
# 2. Writer: the words that go around the grids
# --------------------------------------------------------------------------
WRITER_SYSTEM = """
You write the text of an undated digital planner. The layout is not yours:
calendars, tables and ruled lines are drawn by the program. You supply words.

What you write:
- A welcome page that tells the buyer how to use the file, honestly, in a
  voice that matches the tone you were given.
- For each of the twelve months, two reflective prompts that fit the niche.
  These sit beside the calendar in a narrow column, so each must be under 60
  characters and must work in any month - never name a month or a season
  unless the niche is genuinely seasonal.
- For each extra section, its instructions, its column headers if it is a
  table, or its writing prompts if it is a lined page.

Rules:
- Never write a date, a year, or a weekday name. The calendar handles those.
- Never write "Lorem ipsum", "TODO", "Coming soon", "[placeholder]" or any
  other note to yourself. Everything you write ships to a paying customer.
- Never promise a result. "Track your sleep" is fine; "sleep better in 7
  days" is not.
- Prompts are questions or instructions, not affirmations. "What drained you
  this month?" - not "You are enough."
- Plain English. A tired person reads this at 11pm.
""".strip()

WRITER_CONTRACT = {
    "cover_title": "the planner's name as it appears on the cover",
    "cover_subtitle": "one short line under it",
    "welcome_title": "title of the how-to-use page",
    "welcome_lines": ["5-9 short paragraphs or bullet lines"],
    "month_prompts": [
        {"month": 1, "prompts": ["under 60 chars", "under 60 chars"]}
    ],
    "sections": [
        {"title": "matches a title from extra_sections",
         "kind": "grid or lined",
         "intro": "one sentence shown under the title",
         "instructions": ["1-3 lines of how to use it"],
         "columns": ["for kind=grid: 3-8 short column headers"],
         "row_labels": ["for kind=grid: 0-8 example rows, may be empty"],
         "rows": "for kind=grid: how many rows, 8-20",
         "prompts": ["for kind=lined: 2-5 writing prompts"]}
    ],
    "credits": "one line, no external brand names",
}

# --------------------------------------------------------------------------
# 3. Art director: one prompt per image
# --------------------------------------------------------------------------
ART_SYSTEM = """
You write prompts for an image model that illustrates a digital planner.

Hard rules, learned from images that had to be thrown away:
- NO TEXT of any kind in the image. No words, letters, numbers, dates,
  monograms, labels, captions or signatures. The image model renders text
  badly and every such image was rejected. Say "no text" in every prompt.
- No calendar grids, no tables, no planner pages, no mockups of the product.
  The program draws those. An image of a calendar next to a real calendar
  looks like a mistake.
- No people, no faces, no hands.
- Flat, calm, printable: solid shapes and simple gradients, not photographs,
  not 3D renders, not stock-photo desks with coffee cups.
- The cover and the section art must look like one set: same palette, same
  level of detail.

Write prompts that describe shapes, colour and mood only.
""".strip()

ART_CONTRACT = {
    "cover_prompt": "one paragraph for the cover image, portrait",
    "section_prompts": ["one paragraph per section divider, portrait"],
    "thumbnail_prompt": "one paragraph for a square shop icon",
    "palette": "the shared palette in words",
}

# --------------------------------------------------------------------------
# 4. Listing: the Etsy copy
# --------------------------------------------------------------------------
LISTING_SYSTEM = """
You write the Etsy listing for a finished undated digital planner.

Etsy's rules are not suggestions - a listing that breaks them is removed:
- Title: at most 140 characters. No ALL CAPS words, no emoji, no "best" or
  "#1", no other shop's name, no year.
- Tags: exactly 13, each at most 20 characters, each a phrase a buyer would
  actually search. No single letters, no repeats, no punctuation. Tags may
  repeat words used in the title.
- Materials: up to 13, describing what the file is.
- Description: plain text, no HTML. Say what the buyer receives, what it does
  NOT include, and how to use it. State clearly that it is a digital download
  and that nothing is posted.
- Never claim a result, never mention a brand you do not own (Goodnotes and
  Notability may be named only as compatible apps, in passing).

Write for a tired shopper on a phone. First two lines decide the sale.
""".strip()

LISTING_CONTRACT = {
    "title": "<=140 characters",
    "description": "plain text, 150-350 words, newlines allowed",
    "tags": ["exactly 13, each <=20 characters"],
    "materials": ["3-13 short phrases"],
    "who_its_for": ["3-5 bullet lines"],
    "whats_included": ["3-6 bullet lines"],
    "price_usd": "a number between 5 and 30",
}


def contract_block(contract: dict) -> str:
    """The 'answer in exactly this shape' half of a prompt."""
    return ("OUTPUT CONTRACT - reply with JSON in exactly this shape, no prose:\n"
            + json.dumps(contract, ensure_ascii=False, indent=2))


AGENTS = {
    "concept": (CONCEPT_SYSTEM, CONCEPT_CONTRACT),
    "writer": (WRITER_SYSTEM, WRITER_CONTRACT),
    "art": (ART_SYSTEM, ART_CONTRACT),
    "listing": (LISTING_SYSTEM, LISTING_CONTRACT),
}


def library_js() -> str:
    """A Code node body that exposes every prompt to the rest of the workflow.

    Keeping the prompts in one node means the user can read and tune them in
    the n8n editor without touching any other part of the pipeline.
    """
    payload = {
        name: {"system": system, "contract": contract_block(contract)}
        for name, (system, contract) in AGENTS.items()
    }
    return (
        "// The four agent prompts. Edit the wording here and every call picks\n"
        "// it up - they are read from this node by name.\n"
        f"const PROMPTS = {json.dumps(payload, ensure_ascii=False, indent=2)};\n"
        f"const PROMPT_VERSION = {json.dumps(PROMPT_VERSION)};\n"
        "\n"
        "return [{ json: { ...$input.first().json, prompts: PROMPTS,\n"
        "                  prompt_version: PROMPT_VERSION } }];\n"
    )


def write_markdown(out_dir: str) -> list[str]:
    """Human-readable copies of the prompts, for editing away from n8n."""
    import os
    written = []
    for name, (system, contract) in AGENTS.items():
        path = os.path.join(out_dir, f"{name}.md")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(f"# {name} agent\n\n## System prompt\n\n```\n{system}\n```\n\n"
                     f"## Output contract\n\n```json\n"
                     f"{json.dumps(contract, ensure_ascii=False, indent=2)}\n```\n")
        written.append(path)
    return written
