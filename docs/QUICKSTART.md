# Quickstart

## 1. Install

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/roughboy99/aiautobase-claude-skills/main/install.ps1 | iex
```

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/roughboy99/aiautobase-claude-skills/main/install.sh | bash
```

**Or clone first, which I'd recommend** — reading a script before piping it into your shell
is a good habit:

```bash
git clone https://github.com/roughboy99/aiautobase-claude-skills.git
cd aiautobase-claude-skills
./install.sh          # or: pwsh ./install.ps1
```

Skills you already have are left alone. The script prints what it skipped.

## 2. Verify they loaded

Restart Claude Code, then ask:

```
what skills do you have available?
```

You should see the eleven listed. If not, check they landed in `~/.claude/skills/` —
one folder per skill, each with a `SKILL.md` inside.

## 3. Configure `okthanks`

The only skill here that needs setup. Two paths:

```json
{
  "vault_path": "/path/to/your/obsidian/vault",
  "workspace_root": "/path/to/where/your/projects/live"
}
```

in `~/.claude/skills/okthanks/config.json`.

- **`vault_path`** — your Obsidian vault root. The dated session log goes in
  `<vault>/Sessions/`, and a one-line index entry gets appended to `<vault>/log.md`.
- **`workspace_root`** — the umbrella folder your projects live under. `okthanks` uses this
  to decide which touched folders are yours to commit. It will never init a repo at this
  path itself, only in folders beneath it.

If either is blank, `okthanks` stops and tells you. It won't guess.

## 4. Try the others

Nothing to configure. Just ask:

| Ask for this | Skill that fires |
|---|---|
| "diagram the auth flow as a sequence diagram" | `mermaid` |
| "draw our AWS architecture" | `python-diagrams` |
| "turn this outline into a mind map" | `markmap` |
| paste a messy social post, "make this a CSV" | `txt2csv` |
| "check the logs on my server" | `ssh-remote-connection` |
| "is there a skill for X?" | `find-skills` |
| "use the director on this refactor" | `director` (see the cost note in the README first) |

Some need a binary installed — `mmdc` for mermaid, Graphviz for the diagram skills, Java
for PlantUML. Each skill's `SKILL.md` says which.

## 5. End a session

Type:

```
ok thanks
```

You get:

- a dated log in your vault with what happened, what you decided, and what's left
- a `.claude/SESSION.md` in every folder you touched, with the exact command to resume
  *the conversation*
- a commit in each of those folders

Then check `.claude/SESSION.md` in one of them. If the resume command names the right
folder, it's working.

---

## Troubleshooting

**A skill doesn't trigger.** Its description decides when it fires. Ask for it by name
(`/okthanks`, or "use the mermaid skill") to confirm it's installed, then look at whether
your phrasing matches the description.

**`okthanks` says it isn't configured.** That's the intended behavior with a blank
`vault_path` or `workspace_root`. Fill both in.

**`okthanks` committed nothing.** It only touches folders you actually edited files in
during that session, and it skips anything outside `workspace_root` that isn't already a
git repo. The summary at the end lists what it skipped and why.

**A resumed session isn't in the `/resume` list.** Almost always the folder. Claude Code
indexes sessions by the directory the session was *launched* from — open exactly the folder
named in `SESSION.md`, not a parent and not a subfolder.

**On macOS or Linux and something's off with `okthanks`.** Fair warning: the bash path is
written but untested on those platforms. It's plain `git add -A` and `git commit`, so
there's little to break, but open an issue and I'll fix it.
