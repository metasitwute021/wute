# Planner Factory

Makes one sellable undated digital planner, end to end: picks a niche, writes
the copy, generates the art, assembles a tabbed PDF, checks it, writes the Etsy
listing and publishes it as a draft.

Two n8n workflows. No sub-workflows, so nothing breaks on import.

```
build/          the generators - edit these, not the JSON
workflows/      what you import into n8n
prompts/        readable copies of the four agent prompts
db/schema.sql   run once in Supabase
docs/SETUP_TH.md  ขั้นตอนติดตั้งทีละขั้น (ภาษาไทย)
```

## Build and check

```bash
python3 build/build.py       # regenerate workflows/, prompts/, db/schema.sql
python3 build/verify.py      # static checks, offline
python3 build/simulate.py    # run the whole pipeline offline, no API calls
```

`simulate.py --keep out.pdf` writes the planner the pipeline would produce, so
you can look at a real file before paying for a real run.

## What it makes

A 25-page A4 PDF: full-bleed cover, title page, how-to-use, a tappable
contents page, twelve month calendars with a tab strip down the edge, six or
more niche-specific sections, and a licence page. Undated by default, so it
does not expire every January; set `PLANNER_YEAR` for real dated calendars.

## What is code and what is the model

The model writes words. It never decides layout and never lays out a calendar
— ask a language model for February and it will hand back thirty days.

| Done by code | Done by a model |
|---|---|
| Month grids, weekday columns, the position of the 1st | Which niche to serve |
| Tab strip, contents page, every link | The words on every page |
| Page order, page count, section structure | The image prompts |
| Tag length, tag count, title length | The Etsy title and description |

Four agent calls per run, plus one image call per image (four by default).

## The gates

Every gate is arithmetic, not a second opinion from a model. `simulate.py`
proves each one fires:

- a concept with fewer than six sections, or that names a year in an undated
  planner, or with too few usable keywords
- a writer that skipped months, or left `TODO` / `placeholder` / `lorem ipsum`
  in the copy
- art direction that asks the image model for lettering (it renders text
  badly, and the image is paid for before you see it)
- a PDF whose tabs do not work, or whose contents list silently dropped rows
- a listing over 140 characters, shouting in caps, with fewer than 13 tags, a
  tag over 20 characters, HTML in the description, or a description too short
  to convert

## Setup

See `docs/SETUP_TH.md`. Short version: import both workflows, run
**Etsy Connect** once to get three values, paste them into the **Planner
Config** node, run `db/schema.sql` in Supabase, then run **Planner Factory**.
