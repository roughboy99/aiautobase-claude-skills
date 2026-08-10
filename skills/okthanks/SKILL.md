---
name: okthanks
description: Auto-archive the current Claude Code session to the user's Obsidian vault, drop a resumable continuity file inside every workspace folder touched this session, AND commit the work. Use when the user says "ok thanks", "okthanks", "/okthanks", "save this session", or signals end of session. Writes a dated vault log, appends to log.md, writes .claude/SESSION.md with the exact `claude --resume` command per project, then per-touched-folder: git init if needed, init-changelog if needed, gcommit with a session message.
---

# okthanks — save session + hand off + commit work

This skill carries the user's **standing authorization** for actions that are otherwise blocked by `<workspace_root>/CLAUDE.md`:
- Running `git init` inside a workspace subfolder that has no repo yet.
- Running `git add -A` + `git commit` (via `gcommit`) without re-asking each time.
- Writing/overwriting `.claude/SESSION.md`, `.claude/sessions/*.md`, and appending a marked continuity block to `CLAUDE.md` inside those same folders.

The trigger phrase itself ("ok thanks") IS the permission. No further confirmation needed during the flow. If the user types just "save the session" with no commit intent, still run the full skill — that's the point of this skill existing.

This is a **rigid** skill. Follow the steps in order. Do not adapt.

---

## Step 0 — Load config

Read `~/.claude/skills/okthanks/config.json`. If that file does not exist, or if either
required value below is blank, **stop immediately** and tell the user:

> `okthanks` is not configured yet. Copy
> `~/.claude/skills/okthanks/config.example.json` to
> `~/.claude/skills/okthanks/config.json` and set `vault_path` (your Obsidian vault root)
> and `workspace_root` (the folder your projects live under). Then say "ok thanks" again.

Do not guess these paths, and do not proceed with a partial run — a session log written to
the wrong place is worse than none, because the user will not know to look for it.

**Required:**
- `vault_path` — Obsidian vault root. Must exist on disk.
- `workspace_root` — the umbrella folder your project folders live under. Never auto-init
  a repo at this path itself.

**Vault layout:**
- `sessions_subdir` — subfolder for dated session logs (default `Sessions`)
- `log_file` — running index file appended to (default `log.md`)

**Per-project handoff:**
- `project_pointer_file` — `.claude/SESSION.md` (overwritten each session)
- `project_sessions_subdir` — `.claude/sessions` (dated archive, never overwritten)
- `project_history_rows` — how many past sessions to keep in the pointer's history table
- `inject_claude_md_pointer` — whether to add the continuity block to the project's `CLAUDE.md`

**Git behavior** (`git` object):
- `git.mode` — `"plain"` (default: `git add -A` + `git commit`) or `"gcommit"` (SemVer bump
  + CHANGELOG via a PowerShell module). **On non-Windows, always treat this as `"plain"`**
  regardless of what the config says.
- `git.push` — default `false`. Only push when `true` **and** the repo has an `origin`
  remote. Never create a remote.
- `git.gcommit_module` — absolute path to `git-tools.psm1`. Only read when
  `git.mode` is `"gcommit"`.

**Auto-detected, not configured:**
- The Claude Code transcript directory is `$HOME/.claude/projects`
  (`$env:USERPROFILE\.claude\projects` on Windows). Referred to below as
  `<claude_projects_dir>`.

---

## Step 1 — Capture session identity (needed to resume)

You need three values. Get them **before** writing anything.

**`SESSION_ID`** — resolve in this order:
1. `$env:CLAUDE_CODE_SESSION_ID` — authoritative, set by the runtime. Use this.
2. Your own scratchpad path in the system prompt, shaped
   `...\Temp\claude\<project-key>\<SESSION_ID>\scratchpad` — the second-to-last segment.
3. Newest `.jsonl` in `<claude_projects_dir>/<project-key>/` (the live transcript).

```powershell
$sid = $env:CLAUDE_CODE_SESSION_ID
if (-not $sid) {
    # $launchCwd is the folder the session was STARTED in - not a touched subfolder.
    $key     = $launchCwd -replace '[:\\/]', '-'
    $projDir = Join-Path "$HOME/.claude/projects" $key
    $sid     = (Get-ChildItem $projDir -Filter *.jsonl |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1).BaseName
}
```

**`LAUNCH_CWD`** — the working directory this session was started in. **Not** the touched
subfolder. In the VS Code extension this is the folder VS Code has open; in the terminal it
is wherever `claude` was invoked.

**`ENTRYPOINT`** — `$env:CLAUDE_CODE_ENTRYPOINT`. `claude-vscode` means the VS Code
extension; anything else means the terminal CLI. This decides which resume
instructions go first in the handoff — but **always write both**, because the user
may switch.

> **The constraint that governs everything here.** Claude Code indexes sessions by
> the directory the session was launched from (`<claude_projects_dir>/<cwd with `:`,
> `\`, `/` → `-`>`). The `/resume` picker and `claude --resume` only see sessions
> belonging to the **current** folder. A session launched at `<workspace_root>`
> is invisible from `<workspace_root>\some-project`, and vice versa.
>
> So the handoff must name **the exact folder to open**, not just a session ID.
> Getting this wrong produces a file that looks helpful and silently doesn't work.

Build both resume forms once and reuse them verbatim in every file:

**VS Code:** open `<LAUNCH_CWD>` as the workspace folder → Claude panel → type
`/resume` → pick the entry matching `<SESSION_ID>` (the picker is a list; no UUID
typing needed).

**Terminal:**
```bash
cd <LAUNCH_CWD posix form>
claude --resume <SESSION_ID>
```

---

## Step 2 — Save session log to vault

Pick a short kebab-case topic slug (3–6 words) summarizing the session's main thread.

Write `<vault_path>/<sessions_subdir>/YYYY-MM-DD-<topic>.md` with sections:
- `## Summary` — 2–3 sentence recap
- `## Files Changed` — bulleted list with absolute paths
- `## Decisions` — non-obvious choices and why
- `## Follow-ups` — open items for next session
- `## Resume` — both resume forms from Step 1 (VS Code folder + `/resume`, and the
  `cd` + `claude --resume <SESSION_ID>` terminal block)

Append one line to `<vault_path>/<log_file>`:
```
- YYYY-MM-DD HH:MM — <topic> — see [[YYYY-MM-DD-<topic>]]
```

For each `[[wikilink]]` candidate, leave it as-is. Obsidian will resolve existing pages and mark unresolved ones as page-stubs to write later. **Do not modify existing wiki pages.**

---

## Step 3 — Identify folders touched this session

Build a set of distinct project roots from files edited, written, or created during this session. For each touched file path:

1. Walk up the directory tree looking for an existing `.git/` folder.
2. If found → use that repo root.
3. If not found before reaching the drive root → use the **immediate child of `workspace_root`** as the candidate root (i.e. `<workspace_root>/<some-folder>/`).
4. If the candidate root **equals** `workspace_root` itself → **skip it.** Never auto-init the umbrella.
5. If a file lives entirely outside `workspace_root` and has no enclosing `.git/` → **skip it.** Only auto-init inside the workspace.

Deduplicate. The result is the per-folder list used by Steps 4 and 5.

Also skip:
- The vault path itself (`<vault_path>/`) — that's the session log target, not project work.
- Anything under `~/.claude/` — these are Claude config dirs.

---

## Step 4 — Write the per-folder continuity files

**Run this BEFORE Step 5.** The commit phase does `git add -A`, so these files must
exist first or they land in the *next* session's commit.

For **each** project root from Step 3:

### 4a. Dated archive entry

Create `<repo>/<project_sessions_subdir>/` if missing, then write
`<repo>/<project_sessions_subdir>/YYYY-MM-DD-<slug>.md`. If that filename already
exists, suffix `-2`, `-3`, … Never overwrite a past archive entry.

Content: the same four sections as the vault log, but **scoped to this folder** —
`## Files Changed` lists only paths inside this repo.

### 4b. Pointer file (overwritten every session)

Before overwriting, **read the existing `<repo>/<project_pointer_file>`** and pull out
its `## Historial` table rows so they carry forward.

Write `<repo>/<project_pointer_file>` with exactly this shape:

```markdown
# 🔄 Última sesión — <slug>

## ▶ Retomar la conversación completa

**En VS Code** (abre esta carpeta, no otra):

> `<LAUNCH_CWD>`
>
> Panel de Claude → escribe `/resume` → elige la sesión `<SESSION_ID>`.

**En terminal:**

> ```bash
> cd <LAUNCH_CWD posix form>
> claude --resume <SESSION_ID>
> ```

> ⚠ La carpeta importa: el picker de `/resume` solo muestra sesiones lanzadas
> desde **esa misma carpeta**. Si abres una subcarpeta o el padre, la sesión no
> aparece — no está borrada, está indexada en otro sitio.

| | |
|---|---|
| **Fecha** | YYYY-MM-DD HH:MM |
| **Sesión** | `<SESSION_ID>` |
| **Carpeta a abrir** | `<LAUNCH_CWD>` |
| **Entorno** | VS Code / terminal |
| **Log completo** | `<vault_path>/<sessions_subdir>/YYYY-MM-DD-<slug>.md` |
| **Archivo local** | `<project_sessions_subdir>/YYYY-MM-DD-<slug>.md` |

## Dónde nos quedamos
<2–4 frases: estado real del proyecto al cerrar, no un resumen de lo que hiciste>

## Qué se tocó en esta carpeta
- `ruta/relativa.ext` — qué cambió y por qué

## Decisiones
- <decisión> — <razón>

## Próximos pasos
- [ ] <acción concreta>

## Historial
| Fecha | Tema | Resume ID |
|---|---|---|
| YYYY-MM-DD | <slug> | `<SESSION_ID>` |
<...hasta `project_history_rows` filas anteriores, más nuevas arriba...>
```

Rules for the pointer:
- **"Dónde nos quedamos" describes state, not activity.** "El endpoint `/sync` funciona
  pero no tiene tests" is useful. "Trabajamos en el endpoint de sync" is not.
- Keep it under ~60 lines. It is a handoff, not a transcript.
- Trim the history table to `project_history_rows` rows.

### 4c. Make the new terminal actually read it

Only if `inject_claude_md_pointer` is true.

`.claude/SESSION.md` is **not** auto-loaded by Claude Code — only `CLAUDE.md` is. So the
pointer has to be advertised there, or a fresh terminal will never look at it.

Check `<repo>/CLAUDE.md` for the marker `<!-- OKTHANKS:CONTINUITY:START -->`.
- If present → leave the file completely alone.
- If absent → **append** (never prepend, never rewrite) this block. Create `CLAUDE.md`
  with just this block if the file doesn't exist.

```markdown

<!-- OKTHANKS:CONTINUITY:START -->
## 🔄 Continuidad de sesión

Antes de responder cualquier cosa en este proyecto, lee `.claude/SESSION.md`.
Contiene el estado real al cerrar la última sesión, los próximos pasos, y el
comando exacto (`cd` + `claude --resume <id>`) para retomar la conversación
anterior con todo su contexto. El historial por fecha vive en `.claude/sessions/`.
<!-- OKTHANKS:CONTINUITY:END -->
```

---

## Step 5 — Per-folder commit phase

For **each** project root in the list, in order, run this exact PowerShell sequence via the `Bash` or `PowerShell` tool:

```powershell
# --- 5a. Ensure repo exists ---
$repo = "<absolute-folder-path>"
if (-not (Test-Path (Join-Path $repo ".git"))) {
    git -C $repo init -b main
    # Copy the bundled .gitignore only if none present.
    if (-not (Test-Path (Join-Path $repo ".gitignore"))) {
        Copy-Item "$HOME/.claude/skills/okthanks/gitignore-template.txt" (Join-Path $repo ".gitignore")
    }
}

# --- 5b. Guard: the continuity files must not be silently ignored ---
# If this repo's .gitignore excludes .claude/, `git add -A` would drop the
# handoff without a word. Force-add once: tracked files ignore .gitignore
# from then on, so this self-heals after the first session.
git -C $repo check-ignore -q ".claude/SESSION.md" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "NOTE: .claude/ is gitignored in $repo — force-adding continuity files."
    git -C $repo add -f ".claude/SESSION.md" ".claude/sessions"
}

# --- 5c. Quick gate: any changes? ---
$pending = git -C $repo status --porcelain
if (-not $pending) {
    Write-Host "Nothing to commit in $repo — skipping."
    continue   # move to next folder
}

# --- 5d. Commit ---
$slug  = "<topic-slug-from-step-2>"
$today = (Get-Date).ToString('yyyy-MM-dd')
$msg   = "chore: session $today $slug"

if ($gitMode -eq 'gcommit' -and $IsWindows) {
    # Optional SemVer + CHANGELOG path. Requires git.gcommit_module in config.json.
    Import-Module $gcommitModule -Force
    if (-not (Test-Path (Join-Path $repo "VERSION")) -or
        -not (Test-Path (Join-Path $repo "CHANGELOG.md"))) {
        Initialize-RepoChangelog -Path $repo
    }
    Save-Repo -Message $msg -Path $repo
} else {
    # Default path. Works everywhere.
    git -C $repo add -A
    git -C $repo commit -m $msg
}

# --- 5e. Push (only if explicitly enabled AND a remote exists) ---
if ($gitPush) {
    $hasRemote = (git -C $repo remote) -contains 'origin'
    if ($hasRemote) { git -C $repo push }
    else { Write-Host "git.push is true but $repo has no 'origin' remote - skipping push." }
}
```

Bash equivalent of 5d/5e for macOS / Linux (`gcommit` is Windows-only, so this is always
the plain path):

```bash
slug="<topic-slug-from-step-2>"
msg="chore: session $(date +%F) $slug"

git -C "$repo" add -A
git -C "$repo" commit -m "$msg"

if [ "$git_push" = "true" ]; then
  if git -C "$repo" remote | grep -qx origin; then
    git -C "$repo" push
  else
    echo "git.push is true but $repo has no 'origin' remote - skipping push."
  fi
fi
```

Notes:
- Use `git init -b main` for new repos.
- **`git.mode: "plain"` is the default and needs no extra tooling.** The `gcommit` branch is
  an opt-in for users who have a SemVer/CHANGELOG PowerShell module; if `git.mode` is
  `"gcommit"` but `git.gcommit_module` is blank or unimportable, fall back to plain and say
  so in the Step 6 summary. Never fail the whole run over the optional path.
- `Initialize-RepoChangelog` creates `VERSION` (0.1.0) and `CHANGELOG.md` (with a
  `<!-- CHANGELOG:ENTRIES -->` marker), and injects a `## Latest Changes` block into
  `README.md` (creating it if missing). `Save-Repo` parses the `chore:` prefix → patch bump,
  prepends a CHANGELOG entry, then `git add -A` + commits atomically.
- If a brand-new repo has no commits yet, this becomes the initial commit. That's correct.
- The Step 4 files are already on disk, so they ride along in this same commit.

Do **not** push. These repos are local-only by policy.

---

## Step 6 — Summary output

Print a one-block summary at the end:

```
✓ Session archived
  Vault:   <vault relative path of session file>
  Log:     appended to <log_file>
  Resume:  VS Code → abre <LAUNCH_CWD> → /resume → <SESSION_ID>
           terminal → cd <LAUNCH_CWD> && claude --resume <SESSION_ID>

✓ Handoff written
  - <folder-1>/.claude/SESSION.md   (+ CLAUDE.md pointer added)
  - <folder-2>/.claude/SESSION.md   (CLAUDE.md pointer already present)

✓ Commits
  - <folder-1>   v<old> → v<new>   <short-sha>
  - <folder-2>   v<old> → v<new>   <short-sha>
  - <folder-3>   skipped (nothing to commit)
  - <folder-4>   skipped (outside workspace)
```

---

## Hard rules

- **Never** push unless `git.push` is `true` **and** an `origin` remote already exists.
  Never add a remote.
- **Never** use `--force`, `--hard`, `--no-verify`, or `--amend`.
- **Never** init a repo at `workspace_root` itself.
- **Never** touch existing `.git/` internals.
- **Never** stage files inside the vault path or `~/.claude/` (those aren't project code).
- **Never** write secrets into `.claude/SESSION.md` or `.claude/sessions/*` — no API keys,
  passwords, tokens, or `.env` values. Reference them by variable name only
  (`STRIPE_SECRET_KEY in .env`). These files are committed and a repo can gain a remote later.
- **Never** rewrite an existing `CLAUDE.md`. Append the marked block once, or do nothing.
- **Never** overwrite a dated file in `.claude/sessions/` — suffix instead.
- Write the Step 4 files **before** the Step 5 commit, never after.
- If `git.mode` is `"gcommit"` but the module can't be imported (wrong path, not Windows,
  not PowerShell), fall back to plain `git add -A` + `git commit`, **skip the
  version-bump/changelog step entirely**, and note the fallback in the summary. Never fail
  the run over the optional path.
- If any step fails for a folder (commit hook failure, etc.): stop on that folder, report the error in the summary, but continue with remaining folders. Do not try to "fix" hook failures silently.
- Do not phone home.
