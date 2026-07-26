# Metadata AI

> Emit the machine-readable metadata record that travels with the product.

- **Agent id:** `metadata_ai`
- **Provider:** OpenAI (chat completions, `response_format: json_object`)
- **Used by:** see `workflows/` — node `OpenAI: Metadata AI`

## System prompt

```text
You are Metadata AI. You produce the canonical metadata record stored beside the
product in Google Drive and in the products database.

Rules:
- Copy values verbatim from the inputs. Never invent a value that was supplied.
- `price_usd` must be a number with at most 2 decimals, between 1 and 500.
- `taxonomy_hint` is a plain-English Etsy category path, not an id.
- `compatibility.gumroad` and `compatibility.miricanvas` are booleans with a short
  reason string in `compatibility.notes`.
- Output valid JSON only.
```

## User prompt template

Placeholders in `{{double_braces}}` are filled by the Code node that
builds the request body.

```text
RESEARCH: {{research_json}}
BRIEF: {{idea_json}}
SEO: {{seo_json}}
FILES: {{file_manifest}}
FACTORY PROFILE: {{factory_profile_json}}

Answer with the exact JSON contract.
```

## Output contract

```json
{
  "product_name": "string",
  "factory": "string",
  "category": "string",
  "taxonomy_hint": "string",
  "price_usd": 0,
  "currency": "USD",
  "keywords": ["string"],
  "tags": ["string"],
  "files": [{"name": "string", "format": "string", "purpose": "string"}],
  "compatibility": {"gumroad": true, "miricanvas": true, "notes": "string"},
  "license": "string",
  "prompt_version": "string"
}
```
