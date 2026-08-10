---
name: txt2csv
description: Convert pasted social-media posts containing numbered prompts, lists, or structured content into clean CSV files. Strips engagement noise (handles, timestamps, reaction buttons, image alt-text, repeated headers) and extracts the actual content. Use whenever the user pastes raw text from Facebook, LinkedIn, Threads, X, Reddit, Instagram, or any social platform and wants it tabulated — even if they don't say "CSV" explicitly. Trigger phrases include "filter the noise out of this", "clean this up into a table", "tabulate this", "extract these prompts", "make a CSV from this", "do the same with this one", or the literal slash command /txt2csv. Also fires when the user pastes a numbered list of items wrapped in social-media metadata and asks for any kind of structured output.
---

# txt2csv

Extract structured content from noisy social-media pastes and write it as a clean CSV.

## Why this skill exists

The user collects useful content (prompt collections, tip lists, framework breakdowns) from social-media feeds. Raw paste is a wall of noise: creator handles repeated between items, timestamps, "Reply/Share" buttons, image alt-text, engagement counters. Doing this cleanup by hand each time is tedious and error-prone — especially the RFC 4180 CSV escaping for prompts that contain commas, double quotes, and special characters.

This skill turns a 5-minute manual cleanup into a 20-second extraction.

## When this skill fires

Fire when ALL of these are true:
1. The user has pasted text (or is about to) that looks like a social-media post — not a code snippet, not a config file, not their own writing.
2. The pasted text contains a list of items (usually numbered 1–N) that the user wants to extract.
3. The user wants the result as a CSV or structured table.

Trigger phrases (user may use any of these):
- "filter the noise out of this"
- "clean this up into a table" / "tabulate this"
- "extract these prompts" / "pull out the X from this"
- "make a CSV from this" / "convert this to CSV"
- "do the same with this one" (when a prior txt2csv-style task happened in the conversation)
- the literal slash command `/txt2csv`

If the user pastes a numbered list from a social post but doesn't say "CSV", still consider firing — most likely intent is the same cleanup task.

## Workflow

Follow these steps in order. Do not skip steps.

### Step 1: Read the paste and identify structure

- Find the numbered items (1. 2. 3. ... or 1) 2) 3) ... or just "first... second... third...")
- Count them — could be 3, 7, 10, 20+, any number
- Note where each item starts and ends
- Each item typically has a short **title line** ("1. The Pattern Interrupt Script Builder") and a **body** wrapped in `"..."`

If you cannot find clear numbering, ask the user how items are separated before proceeding. Do not guess.

### Step 2: Recognize noise and strip it

These patterns are noise. Remove them silently:

| Noise type | Examples |
|---|---|
| **Creator handle repeated between items** | `Jamie AI Empire`, `John Marketing`, `@growth_guru` |
| **Relative timestamps** | `12h`, `20h`, `2d`, `Just now`, `5 min ago`, `Yesterday` |
| **Reaction/action buttons** | `Reply`, `Share`, `Like`, `Comment`, `Repost`, `Save`, `Send` |
| **Image alt-text** | Lines starting with `May be a graphic of...`, `Image may contain...`, `Photo of...`, `[Image]` |
| **Engagement counters** | `👍 42`, `View 18 comments`, `1.2K likes`, `5 replies` |
| **Duplicate headlines** | When the lead headline ("🚨 BREAKING: ...") appears twice in the paste |
| **Trailing user notes** | Lines like "i dont need" / "remove this" appearing after the content — those are instructions to you, not content |
| **Empty lines and orphan whitespace** | Collapse multiple blank lines, trim leading/trailing whitespace per item |
| **Thread pagination markers (X/Twitter)** | `1/8`, `2/8`, `N/M` — appear between items in threaded posts, indicate "post X of M in this thread" |
| **`Prompt:` label preceding each body** | Some creators (e.g., `aicreatortyler`, the LinkedIn-prompts creator) put a literal `Prompt:` line between the item title and its body — structural marker, not content. Strip it. |
| **Display name + handle pair** | Some platforms show both (e.g., `Travel Threads` on one line, `aicreatortyler` below) — treat both as repeating handle noise |

### Step 3: Preserve one piece of metadata

Identify the source creator's handle (usually the first non-noise line, or the line that repeats most between items). Mentally note it — the user may want it later for attribution. Do not add it to the output unless the user opts in to a Source column.

### Step 4: Propose the output schema

Default schema: `Number, Title, Prompt`

Show a 1-row preview using the first extracted item, then ask:

> "Using `Number, Title, Prompt` as columns — first row would render as:
> `1, [title], [prompt body]`
> Use this, or want to adjust? Common alternatives: add `Role` (the 'Act as a X' opener split out), `Placeholder` (the `[paste]`/`[niche]` variable), or `Source` (the creator handle)."

Wait for confirmation before writing.

### Step 5: Propose a filename

Read the post's headline — usually the first content line starting with 🚨, "BREAKING:", "Here are", "X prompts that...", etc. — and derive a kebab-case topic.

Examples:
- `🚨BREAKING: Claude can now replace your entire YouTube growth team` → `youtube-growth-prompts.csv`
- `🚨BREAKING: Claude can now build The complete marketing strategy for Your business` → `marketing-strategy-prompts.csv`
- `7 prompts that turn ChatGPT into a senior copywriter` → `senior-copywriter-prompts.csv`

Show the proposed filename, let the user override.

**Fallback when no headline is present.** If the user pastes starting from item 1 (skipping the thread header), there is no headline to derive from. In that case, infer the topic from the **unifying theme of the prompts themselves** — what's the one thing all items help the user accomplish? Examples:

- 6 prompts about removing AI tells, varying sentence length, voice-matching → `humanize-ai-text-prompts.csv`
- 7 prompts spanning channel strategy, idea generation, scripts, SEO, community, monetization → `youtube-channel-blueprint-prompts.csv`

State your inferred topic + filename so the user can correct it before the write.

### Step 6: Write the CSV

- **Location**: `./prompt-library/<topic>-prompts.csv`, relative to the current working
  directory. If the user names a different folder, use theirs.
- **Create the folder if missing.** PowerShell:
  `New-Item -ItemType Directory -Force ./prompt-library`. Bash: `mkdir -p ./prompt-library`.
- **Encoding**: UTF-8 (default Write tool behavior)
- **Escaping**: RFC 4180 (see rules below)
- **Collision handling**: if `<topic>-prompts.csv` already exists, do NOT blindly append `-v2`. First check whether the two pastes actually cover the same angle:
  - Compare the existing file's items to the new paste's items. Are they from the same creator and same domain (true duplicate)? Or different creators / different angle on the same broad topic (semantic distinction)?
  - **Same creator + same content** → ask the user before doing anything; they may have re-pasted by accident.
  - **Different creator, but genuinely overlapping items** → append `-v2`, `-v3`. The number captures "another take on the same thing."
  - **Different angle on the same broad topic** → coin a new semantic name that captures the difference. Example: existing `youtube-growth-prompts.csv` (Jamie's identity/positioning angle) + new paste on tactical execution (Shruti's idea-generation/SEO/monetization angle) → name the new one `youtube-channel-blueprint-prompts.csv`, not `youtube-growth-prompts-v2.csv`. The folder is easier to browse by topic distinction than by version number.
  - **Always state the collision and your chosen name in the report** so the user can rename if they disagree.
  - **Never overwrite** without explicit user confirmation, regardless of which case applies.

### Step 7: Report

After writing, output a short report:
- How many items extracted
- What noise patterns were stripped (so user can verify nothing important got cut)
- The final file path as a clickable markdown link
- An `★ Insight ─────` callout with 1–2 observations about the content (recurring theme, structural pattern, comparison to prior CSVs in `prompt-library/` if relevant — since the user runs in learning/explanatory output style)

## Character normalization (CRITICAL — do this before CSV escaping)

Excel on Windows defaults to cp1252 when opening a CSV with no UTF-8 BOM. UTF-8 bytes for smart typography then display as mojibake — `I'm` renders as `Iâ€™m`, `"passionate"` as `â€œpassionateâ€`. The user explicitly flagged this on 2026-05-18.

**Solution:** normalize all "smart" Unicode typography to ASCII equivalents BEFORE applying RFC 4180 escaping. Apply these substitutions in order:

| Source character | Unicode | Replace with |
|---|---|---|
| `'` `'` curly apostrophes (open/close) | U+2018, U+2019 | `'` ASCII apostrophe |
| `"` `"` curly double quotes (open/close) | U+201C, U+201D | `"` ASCII double quote |
| `–` en dash | U+2013 | `-` hyphen |
| `—` em dash | U+2014 | `-` hyphen |
| `…` ellipsis | U+2026 | `...` three ASCII dots |
| Non-breaking space | U+00A0 | regular ASCII space |

Why this matters: the user opens these CSVs in Excel on Windows. cp1252 is Excel's default for BOM-less CSVs. Adding a BOM would also work, but normalization is more portable (every tool everywhere reads ASCII, BOM-aware or not).

**Order of operations:**
1. Strip noise (Step 2 above)
2. Strip outer prompt-wrapping quotes
3. **Normalize smart typography → ASCII** (this section)
4. Apply RFC 4180 escaping below (note: step 3 may produce new ASCII `"` chars that now need to be doubled to `""`)

## RFC 4180 CSV escaping (critical)

This is where manual extraction usually breaks. Follow these rules exactly:

| Condition | Action |
|---|---|
| Cell contains no comma, no `"`, no newline | Write as-is, no quotes |
| Cell contains a comma | Wrap entire cell in `"..."` |
| Cell contains a `"` | Wrap in `"..."` AND replace every internal `"` with `""` |
| Cell contains a newline | Wrap in `"..."`, preserve the newline literally |
| Cell contains single quote / apostrophe `'` | Pass through untouched — apostrophes are NOT CSV-significant |

**Example transformations:**

| Source | CSV cell output |
|---|---|
| `Hello world` | `Hello world` |
| `Hello, world` | `"Hello, world"` |
| `The "Avatar-Psychology" Deep-Dive` | `"The ""Avatar-Psychology"" Deep-Dive"` |
| `It's a great prompt` | `It's a great prompt` (apostrophe pass-through) |
| `Act as a copywriter. Write 3 ads.` | `"Act as a copywriter. Write 3 ads."` (has period+comma) |

**Strip outer prompt-wrapping quotes.** Social posts often wrap each prompt body in `"..."` as a visual cue. Those outer quotes are noise — strip them before writing the cell, then re-apply CSV-level wrapping per the table above. Don't keep both layers, that creates ugly `""prompt""` in the output.

## Edge cases

- **Truncated source content** (sentence cuts off mid-word, post hit a character limit): mark the cell `[TRUNCATED IN SOURCE]` instead of inventing missing words. Tell the user in the report so they can paste the rest if they have it. Never guess at completion.
- **Ambiguous noise**: if you cannot tell whether a line is noise or content, ask. Example: "Is `Pro tip:` between items a section header you want kept, or repeating noise to drop?"
- **No clear numbering**: ask the user how items separate. Don't guess at bullet points vs paragraphs.
- **Mixed languages** (English + Spanish, common for this user): pass through as-is. UTF-8 preserves everything.
- **Image-only items** (item that's just an image alt-text with no real content): drop the entry and tell the user so they can decide if it mattered.
- **User says "do the same with this one"**: same schema (Number/Title/Prompt), same folder, derive filename from the new paste's headline. Don't re-ask the schema question every time.

## What this skill does NOT do

These are deliberate design decisions:

- **No master/consolidated file.** Each invocation writes one topic CSV. The user explicitly declined a `prompt-library.csv` rollup file when this skill was designed.
- **No translation, rewriting, or "improving"** of prompts. Pure extraction + cleanup. If a prompt has a typo in the source, the typo stays.
- **No external API calls or bundled scripts.** Pure Claude reasoning + Write tool. Keeps the skill portable and zero-maintenance.
- **No automatic move of existing CSVs.** Files already at workspace root (e.g., `youtube-growth-prompts.csv`) stay where they are unless the user asks to consolidate.

## Reference examples

Two shapes cover almost every real paste. Match one of them.

**A. No internal quotes** — plain cells, no escaping needed. Note the truncation marker,
used when the source paste itself cut a prompt off mid-sentence:

```csv
Number,Title,Prompt
1,Pick One Content Pillar,"Act as a channel strategist. Given my niche of {{niche}}, name the single content pillar I should own and explain why in 3 bullets."
2,Ninety Day Upload Plan,"Build a 90-day upload calendar for {{niche}}. One video per week. For each, give a title and a one-line hook. [TRUNCATED IN SOURCE]"
```

**B. Internal double quotes** — every embedded `"` doubles to `""`. This is the case people
get wrong, so check your output against it:

```csv
Number,Title,Prompt
1,The So What Test,"Rewrite my headline so it passes the ""so what?"" test. Headline: {{headline}}"
2,Objection Reversal,"List the top 5 objections to {{product}}, then rewrite each as a ""yes, and"" benefit statement."
```

Rules both examples demonstrate: header row always present; a cell is quoted whenever it
contains a comma, a double quote, or a newline; `Number` is bare because it never needs
quoting.

## Example session (full trace)

**User:** `/txt2csv` [pastes a Threads post with 5 productivity tips, "@productivity_pat" handle repeated, "3h Reply Share" lines, an "Image may contain text" alt-line]

**You:**
1. (Internal) Scan paste → find 5 numbered items, identify noise patterns: handle `@productivity_pat`, timestamp `3h`, buttons `Reply`/`Share`, alt-text `Image may contain text`.
2. (To user) "Found 5 tips. Using `Number, Title, Prompt` as columns. First row preview: `1, Time-Block Your Mornings, Carve out the first 90 minutes...`. Proceed?"
3. After user confirms, propose: "Headline says 'Five productivity tips that changed my year' → filename `productivity-tips-prompts.csv`. Sound good?"
4. After user confirms, ensure folder exists, write file.
5. Report: "Extracted 5 tips → `./prompt-library/productivity-tips-prompts.csv`. Stripped: repeated `@productivity_pat` handle (×5), `3h` timestamps (×5), `Reply Share` buttons (×5), `Image may contain text` alt-text (×1).
   ★ Insight ─────
   - All 5 tips center on time-batching as the core mechanic — that's the post's underlying thesis even though the title says "productivity" generically.
   ─────"
