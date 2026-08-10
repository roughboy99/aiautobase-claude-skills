# What is a Claude Code skill?

If you've never written one, this is the whole idea in about five minutes.

## A skill is a folder with instructions in it

```
~/.claude/skills/
  my-skill/
    SKILL.md          <- required. everything else is optional.
    references/       <- longer docs the skill can pull in when needed
    scripts/          <- helper scripts the skill can run
```

`SKILL.md` starts with frontmatter — a name and a description:

```markdown
---
name: my-skill
description: Converts pasted invoice emails into a spreadsheet row. Use when the
  user pastes an invoice or says "log this invoice".
---

# my-skill

## Step 1 - find the numbers
Pull the invoice number, date, vendor, and total. If the total is missing, stop
and ask - do not guess a number that will end up in accounting.

## Step 2 - write the row
Append to ./invoices.csv ...
```

That's it. No build step, no plugin manifest, no API, no registration.

## How Claude Code decides to use one

It reads the **description** of every installed skill. When your request looks like a
match, it loads the body and follows it.

This makes the description the most important line in the file. It isn't documentation —
it's the trigger. Compare:

```yaml
# Weak - when does this apply? unclear.
description: Helps with invoices.

# Strong - names the situation AND the trigger phrases.
description: Converts pasted invoice emails into a spreadsheet row. Use when the user
  pastes an invoice, mentions a vendor bill, or says "log this invoice". Not for
  generating new invoices.
```

Saying what a skill is **not** for is as useful as saying what it is for. It stops the
skill firing on adjacent requests where it will do the wrong thing.

## Why skills beat pasting the same prompt every time

A skill is a prompt you only have to get right once.

The useful ones usually aren't clever. They're a written-down version of something you
learned painfully. `okthanks` in this repo exists because I discovered that Claude Code
indexes sessions by launch directory, which means a resume note without the folder path
silently doesn't work. That's one paragraph of knowledge. Encoded in a skill, I never
have to rediscover it.

That's the real pattern: **the thing that cost you an afternoon is the thing worth
writing a skill about.**

## Writing your own

Two skills in this repo help:

- **[`write-a-skill`](../skills/write-a-skill/)** — scaffolds a new skill with proper
  structure and progressive disclosure
- **[`find-skills`](../skills/find-skills/)** — finds existing skills for a problem
  before you build one

## Things worth knowing before you write many

**Keep `SKILL.md` short and push detail into `references/`.** Everything in `SKILL.md`
gets read when the skill triggers. A 500-line skill spends context on instructions that
mostly don't apply to the current run. Put the common path in `SKILL.md` and the rare
cases in files it can open when needed.

**Be specific about hard rules.** "Never overwrite an existing dated file — add a `-2`
suffix instead" survives contact with reality. "Be careful with files" does not.

**Don't hardcode your own paths.** The fastest way to make a skill useless to anyone
else — and to yourself on a second machine — is to bake in `C:\Users\you\...`. Read
paths from a config file, or work relative to the current directory. Every skill in
this repo had to be cleaned of exactly this before it could be published.

**Watch out for a skill that can't fail.** If your skill's verification step is "check
that the file mentions X", it will pass even when nothing actually ran. Make the check
observe a real consequence, not the presence of a string.

## Where they live

| Scope | Path | Applies to |
|---|---|---|
| Personal | `~/.claude/skills/` | every project you work on |
| Project | `<repo>/.claude/skills/` | that repo only, and it can be committed for your team |

Project-scoped skills are underused. A skill that encodes *this repo's* deploy steps or
test conventions is often more valuable than a general-purpose one, and it travels with
the code for everyone else on the team.
