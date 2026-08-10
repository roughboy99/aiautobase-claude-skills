# Design — `aiautobase-claude-skills`

**Date:** 2026-08-10
**Author:** Hector Diaz (Orbix Automation Solutions), with Claude Code
**Status:** Approved

---

## 1. Purpose

Publish a curated, sanitized set of 11 Claude Code skills as a public GitHub repo for the
**AI Auto Base** Skool community. The `okthanks` skill is the headliner — it is the most
distinctive of the set and the README leads with it.

**Repo:** `github.com/roughboy99/aiautobase-claude-skills` — public, MIT.
**Local working copy:** `<workspace-root>/aiautobase-claude-skills/` (local git repo; this
repo is the one documented exception to the workspace's no-remotes policy, because
publication is the whole point).

> **Note on this document.** It ships in the public repo, so it deliberately refers to
> private paths and hosts by placeholder (`<vault-path>`, `<workspace-root>`, `10.0.0.x`)
> rather than by value. The safety gate in §6 therefore needs no exception for `docs/` —
> if this file ever trips the gate, the file is wrong, not the gate.

### Success criteria

1. A stranger on Windows, macOS, or Linux can run one install command and end up with 11
   working skills in `~/.claude/skills/`.
2. `okthanks` runs successfully for that stranger after filling in one config file, and its
   failure message is actionable when they haven't.
3. The published tree contains **zero** credentials, private IPs, private paths, or vault
   references belonging to Hector.
4. Third-party work in the tree is attributed as its license requires.

### Non-goals

- Not a Claude Code *plugin* / marketplace. Plain skill folders + an install script.
- Not bilingual. English only (decided; the Spanish `okthanks` templates stay local).
- Not a distribution channel for the other 49 skills in `~/.claude/skills/`. Those are
  either third-party, Orbix-private, or too large.

---

## 2. Skill roster (11)

| Skill | Origin | Sanitizing needed |
|---|---|---|
| **`okthanks`** ⭐ | Hector | **Substantial** — see §4 |
| `mermaid` | Hector | None |
| `plantuml` | Hector | None |
| `python-diagrams` | Hector | None |
| `go-diagrams` | Hector | None |
| `markmap` | Hector | None |
| `json-canvas` | Hector | None |
| `txt2csv` | Hector | None |
| `ssh-remote-connection` | **`artwist-polyakov/polyakov-claude-skills` (MIT)** | **Delete 3 files** — see §5 |
| `write-a-skill` | Hector | None |
| `find-skills` | Hector | None |

Provenance was established by scanning every skill for `.skillfish.json`. Exactly one match:
`ssh-remote-connection`. The other ten carry no authorship metadata and no upstream
attribution markers.

---

## 3. Repo layout

```
aiautobase-claude-skills/
├── README.md                      okthanks hero section; other 10 below it
├── LICENSE                        MIT — Hector Diaz / Orbix Automation Solutions
├── NOTICE                         MIT attribution: artwist-polyakov
├── .gitignore
├── install.ps1                    Windows
├── install.sh                     macOS / Linux
├── scripts/
│   └── safety-gate.ps1            pre-push secret/private-data scan (§6)
├── docs/
│   ├── QUICKSTART.md
│   ├── WHAT-ARE-SKILLS.md         for non-technical Skool members
│   └── superpowers/specs/         this document
└── skills/
    ├── okthanks/
    │   ├── SKILL.md
    │   ├── README.md
    │   ├── config.example.json
    │   ├── templates/
    │   │   ├── session-pointer.md      the .claude/SESSION.md shape
    │   │   ├── session-archive.md      the .claude/sessions/DATE-slug.md shape
    │   │   └── vault-log.md            the Obsidian vault entry shape
    │   └── gitignore-template.txt      generic; replaces the .staging/ dependency
    ├── mermaid/  plantuml/  python-diagrams/  go-diagrams/
    ├── markmap/  json-canvas/  txt2csv/
    ├── ssh-remote-connection/
    └── write-a-skill/  find-skills/
```

---

## 4. `okthanks` — the portability work

**Decision: Obsidian stays a hard requirement.** The vault log is the skill's reason to
exist; making it optional would leave a generic "commit my work" skill. The skill validates
`vault_path` on load and fails fast with setup instructions rather than degrading.

### 4.1 Config contract

`config.example.json` — the user copies to `config.json`, which is gitignored.

```json
{
  "vault_path": "",
  "sessions_subdir": "Sessions",
  "log_file": "log.md",
  "workspace_root": "",
  "project_pointer_file": ".claude/SESSION.md",
  "project_sessions_subdir": ".claude/sessions",
  "project_history_rows": 10,
  "inject_claude_md_pointer": true,
  "git": {
    "mode": "plain",
    "push": false,
    "gcommit_module": ""
  }
}
```

Removed from the current config: `wiki_subdir` and `topics_subdir` (unused by the skill —
they belong to Hector's private vault protocol, not to `okthanks`), `git_tools_module` and
`gitignore_template` (replaced by `git.gcommit_module` and the bundled template),
`claude_projects_dir` (now auto-detected).

### 4.2 Behavioral changes

| Current | Shared version |
|---|---|
| `config.json` ships with Hector's paths | `config.example.json` ships empty; `config.json` is gitignored |
| `vault_path` hardcoded to a private vault | Required. Empty or nonexistent → **Step 0 aborts** with a setup message naming the file to edit |
| `workspace_root` hardcoded to a private path | Required. Same validation. |
| `claude_projects_dir` hardcoded to a user profile | Auto-detected as `$HOME/.claude/projects` (`$env:USERPROFILE` on Windows) |
| `SESSION.md` template in Spanish, inline in SKILL.md | English, extracted to `templates/*.md` so the skill body stays readable |
| `Import-Module git-tools.psm1` unconditionally | `git.mode: "plain"` (default) → `git add -A` + `git commit`. `"gcommit"` → import `git.gcommit_module`, use `Save-Repo`/`Initialize-RepoChangelog`. Non-Windows forces `"plain"` regardless of config. |
| `.staging/gitignore-template.txt` | `skills/okthanks/gitignore-template.txt`, bundled |
| Hard rule: "Never push to a remote" | `git.push: false` (default). `true` → `git push` after commit, only if an `origin` remote exists. |
| Step 5 is PowerShell-only | Step 5 gives a PowerShell block **and** an equivalent bash block; the skill picks by platform |

### 4.3 What deliberately does NOT change

These are the parts that took real debugging and are already correct. They are copied
verbatim:

- **Session-ID resolution order** — `$env:CLAUDE_CODE_SESSION_ID`, then the scratchpad path
  segment, then newest `.jsonl` in the project transcript dir.
- **The `LAUNCH_CWD` constraint and its warning.** Claude Code indexes sessions by the
  directory the session was launched from, so `/resume` only surfaces sessions belonging to
  the current folder. The handoff must name the exact folder to open. Getting this wrong
  produces a file that looks helpful and silently doesn't work.
- **The `.gitignore`-excludes-`.claude/` guard.** `git check-ignore` on
  `.claude/SESSION.md`; if ignored, `git add -f` once. Tracked files ignore `.gitignore`
  thereafter, so it self-heals after the first session.
- **Never overwrite a dated archive file** — suffix `-2`, `-3`, …
- **Never rewrite an existing `CLAUDE.md`** — append the marked block once, or do nothing.
- **Write the continuity files before the commit**, never after, because the commit does
  `git add -A`.
- **"Where we left off" describes state, not activity.**
- **Never write secrets into the continuity files** — reference by variable name only.
- Per-folder error isolation: a folder that fails is reported and skipped; remaining
  folders still process.

---

## 5. `ssh-remote-connection` — sanitizing

**Delete outright** (do not edit — these contain live data):

- `config/.env` — real credentials
- `config/comfyui-142.json` — a real LAN host (`10.0.0.x`) with SSH details
- `config/mac-build-host.json` — a real LAN host (`10.0.0.x`) with SSH details

**Keep:** `SKILL.md`, `scripts/connect.sh`, `config/.env.example` (already generic and
correct), `.gitignore`.

**Remove:** `.skillfish.json` — it is install-tracking metadata for a different registry and
would be misleading in this repo. Its information moves to `NOTICE` where it belongs.

**Verify:** `scripts/connect.sh` and `SKILL.md` matched the credential grep. Both must be
re-read line by line and any hardcoded host, user, or path replaced with the `.env`
variable reference the skill already documents.

**Attribute:** `NOTICE` carries the upstream MIT notice for
`artwist-polyakov/polyakov-claude-skills`, and the skill's row in the README links to the
original repo.

---

## 6. Pre-push safety gate

`scripts/safety-gate.ps1` scans the tracked tree and fails non-zero on any hit:

| Pattern | Rationale |
|---|---|
| private RFC-1918 LAN ranges + the known VPS IPs | private hosts |
| the Obsidian vault root, both slash forms | vault path |
| the workspace root, both slash forms | workspace path |
| the Windows user-profile path, both slash forms | user path |
| `getorbix\.com` outside README/LICENSE/NOTICE | brand infra references |
| `gho_` , `sk-` , `ghp_` | tokens |
| `password\s*[=:]\s*\S` | credentials |
| any `.env` file whose name is not `.env.example` | credential files |

**The patterns live outside the script.** A gate that hardcodes "search for this private IP"
publishes that private IP — the script would leak exactly what it exists to catch. So:

- `scripts/patterns.local.txt` — the real patterns, one regex per line. **Gitignored.**
- `scripts/patterns.example.txt` — committed, with generic placeholders and a comment
  explaining that each user fills in their own private strings.
- `safety-gate.ps1` reads `patterns.local.txt`, and **fails loudly if that file is missing**
  rather than passing vacuously with zero patterns.

That last point matters: the natural bug here is a gate that finds nothing because it was
looking for nothing, and reports success.

**The gate must return clean before the first push, and its output is shown to the user.**
A gate that is written but not run proves nothing.

---

## 7. Install scripts

`install.ps1` and `install.sh`, functionally equivalent:

1. Resolve the skills target: `$HOME/.claude/skills`. Create if missing.
2. For each directory in the repo's `skills/`:
   - If the target already exists → **skip, and record it.** The user's own version wins.
   - Else copy.
3. Print a summary: installed / skipped, with the skipped list named explicitly.
4. If `okthanks` was installed and `okthanks/config.json` does not exist, copy
   `config.example.json` → `config.json`, then **print** the two values the user must fill in
   (`vault_path`, `workspace_root`) and the absolute path of the file to edit.

**Revision from the approved design:** step 4 was originally going to *prompt* for those two
values. It doesn't, because the install scripts must survive being curl/irm-piped into a
shell, where stdin is the script itself and a `Read-Host` either hangs or eats the rest of
the script. Print-and-instruct works in every invocation mode; prompting works in exactly
one. `okthanks` already fails fast with an actionable message if the values are blank, so
nothing is lost.

Both scripts support being run from a clone or via a curl/irm one-liner (clone to a temp
dir, install, clean up).

---

## 8. README structure

The README is a sales page for `okthanks` with a catalog attached.

1. **Hero** — the problem in two sentences: you close Claude Code, and the context of
   what you were doing, why, and where you left off is gone. Your git history says
   `wip`. Next week you re-derive everything.
2. **What `okthanks` does** — you type "ok thanks". It writes a dated log to your Obsidian
   vault, drops a `.claude/SESSION.md` in every folder you touched with the exact command
   to resume the *conversation*, and commits the work.
3. **The `/resume` gotcha, stated plainly** — this is the insight that makes the skill
   worth having, and explaining it is what makes the README credible.
4. **Install** — one line per platform.
5. **Configure `okthanks`** — the two required values.
6. **The other 10 skills** — a table: name, one line, link to its folder.
7. **Requirements** — Claude Code, git, Obsidian (for `okthanks` only), plus per-skill
   binaries (Graphviz, PlantUML JAR, Node, Go) noted in each skill's own README.
8. **Credits** — `ssh-remote-connection` → artwist-polyakov (MIT). Orbix / AI Auto Base
   footer.

---

## 9. Verification before "done"

In this order. Each produces output that gets shown, not summarized:

1. `scripts/safety-gate.ps1` → clean.
2. `install.ps1` run against a **throwaway** skills directory (a temp path, not
   `~/.claude/skills`), asserting 11 directories land and the skip path works when one
   already exists.
3. `okthanks` exercised end-to-end against a **temp vault + temp git repo**: confirm the
   vault log, the `.claude/SESSION.md`, the `.claude/sessions/` archive, the `CLAUDE.md`
   marked block, and one commit. Then confirm the abort path by blanking `vault_path`.
4. `gh repo create` + push, then re-fetch the pushed tree and re-run the safety gate
   against what GitHub actually received.

Step 3 is the one that matters most. `okthanks` is the headliner; shipping it broken for
strangers while it works locally is the specific failure this design exists to prevent.

---

## 10. Open risks

- **The 8 untouched skills are assumed clean** on the strength of a credential grep and an
  absence of `.skillfish.json`. That is good evidence, not proof of authorship. If any turns
  out to be third-party, attribution gets added — the MIT license on the repo does not
  become wrong, but `NOTICE` would need another entry.
- **`okthanks` cross-platform bash parity is untested on macOS/Linux** from this machine.
  The bash block will be written carefully and reviewed, but it ships unverified on those
  platforms. The README should say so rather than imply it was tested everywhere.
