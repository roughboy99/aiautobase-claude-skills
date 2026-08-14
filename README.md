# Claude Code Skills — AI Auto Base

Twelve skills I actually use. The first one is the reason this repo exists.

---

## The problem I built `okthanks` to fix

You spend two hours with Claude Code working through something genuinely hard. You figure out
why the auth flow breaks on refresh. You decide against the obvious fix for a reason that took
forty minutes to find. You get it working.

Then you close the window.

Next week you open the project. `git log` says `wip`. The file is different from how you
remember it and you don't know why. The conversation where you worked all of this out is
somewhere on disk, indexed by a UUID you never saw, and you have no idea which one.

So you re-derive it. Badly, and slower than the first time.

That's not a memory problem. It's a **handoff** problem — and the handoff was never written.

---

## What `okthanks` does

You type **"ok thanks"**. That's the whole interface.

1. **Writes a dated session log to your Obsidian vault** — summary, files changed, decisions
   and *why*, open follow-ups.
2. **Drops a `.claude/SESSION.md` into every folder you touched** containing the exact command
   to resume *the conversation*, not just open the folder.
3. **Commits the work** in each of those folders, with a real message instead of `wip`.
4. **Advertises the handoff in `CLAUDE.md`** so a fresh session reads it before answering
   anything.

Point 3 matters more than it sounds. The continuity files are written *before* the commit, on
purpose — the commit does `git add -A`, so writing them after means they land in next week's
commit instead of this one. Small ordering detail, took a session to notice.

### The part that makes it worth having

Claude Code indexes sessions by **the folder the session was launched from**. Not the project.
Not the repo. The launch directory.

Which means `/resume` only shows you sessions belonging to the folder you're currently in. A
session you started in `~/work` is invisible from `~/work/my-project`, and the other way
round. It isn't deleted. It's indexed somewhere you aren't looking.

So a handoff note that says *"resume session `a1b2c3`"* is useless on its own. `okthanks`
writes **the exact folder to open** alongside the session ID, for both VS Code and the
terminal:

```markdown
## Resume this conversation

**VS Code** — open THIS folder, not a subfolder:
> /home/you/work
> Claude panel -> type /resume -> pick session a1b2c3...

**Terminal:**
> cd /home/you/work
> claude --resume a1b2c3...
```

I got this wrong the first time and produced a handoff file that looked perfectly helpful and
silently didn't work. That's the failure mode worth knowing about.

---

## Install

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/roughboy99/aiautobase-claude-skills/main/install.ps1 | iex
```

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/roughboy99/aiautobase-claude-skills/main/install.sh | bash
```

Or clone it and run the script directly — same result, and you get to read it first, which I'd
recommend for anything you pipe into a shell.

**It will not overwrite skills you already have.** If you have your own `mermaid`, yours wins
and the script tells you it skipped it.

---

## Configure `okthanks`

It needs two paths. Nothing else.

Edit `~/.claude/skills/okthanks/config.json`:

```json
{
  "vault_path": "/path/to/your/obsidian/vault",
  "workspace_root": "/path/to/where/your/projects/live"
}
```

That's it. Everything else has a working default.

If you skip this, `okthanks` stops and tells you what to fill in rather than guessing — a
session log written to the wrong place is worse than no session log, because you won't know to
go looking for it.

**Optional:** if you have a PowerShell module that does SemVer bumps and CHANGELOG entries, set
`git.mode` to `"gcommit"` and point `git.gcommit_module` at it. Leave it alone and you get a
plain `git commit`, which is what most people want. Set `git.push` to `true` only if you want
pushes; it defaults to off and never creates a remote.

### Requirements for `okthanks` specifically

- **Obsidian** — the vault log is the point of the skill, so this one isn't optional
- **git**
- Windows / PowerShell gets the full path including the optional SemVer mode

Honest caveat: the macOS and Linux code path is written but **I haven't tested it on those
platforms** — I build on Windows. It's plain `git add -A` and `git commit`, so there isn't much
to go wrong, but I'm not going to claim I verified something I didn't. Open an issue if it
misbehaves.

---

## The other eleven

| Skill | What it does | Needs |
|---|---|---|
| [`txt2csv`](skills/txt2csv/) | Paste a messy social post full of handles, timestamps and "Reply Share" junk, get a clean CSV of the actual content | nothing |
| [`director`](skills/director/) | Three-tier multi-agent orchestration for genuinely hard tasks — **read the warning below before running it** | Workflow tool |
| [`mermaid`](skills/mermaid/) | Flowcharts, sequence diagrams, Gantt, ER, mind maps | `mmdc` |
| [`plantuml`](skills/plantuml/) | UML and C4 architecture diagrams | Java + PlantUML JAR |
| [`python-diagrams`](skills/python-diagrams/) | AWS / GCP / Azure / Kubernetes architecture diagrams | Python + Graphviz |
| [`go-diagrams`](skills/go-diagrams/) | Infrastructure and network topology diagrams | Go + Graphviz |
| [`markmap`](skills/markmap/) | Turn a markdown outline into an interactive mind map | Node |
| [`json-canvas`](skills/json-canvas/) | Create and edit Obsidian `.canvas` files | nothing |
| [`ssh-remote-connection`](skills/ssh-remote-connection/) | Run commands, check logs and manage Docker on a remote box | SSH |
| [`write-a-skill`](skills/write-a-skill/) | Build your own skills with proper structure | nothing |
| [`find-skills`](skills/find-skills/) | Find and install skills for something you're trying to do | nothing |

Start with `write-a-skill` and `find-skills` if you want to stop downloading other people's
skills and write your own. That's the better end state.

### Before you run `director`

This one is different from the rest, so read this first.

`director` decomposes a task, hands each piece to a sub-director, and each of those fans out
to sub-agents — then verifies the work, retries what fails, and has the sub-directors
cross-check each other. Three tiers, each on the model that suits its job.

When it fits, it's genuinely better than one agent grinding through a hard problem alone.

**Two things to know:**

- **It costs real tokens.** Every other skill here is effectively free. This one spawns a
  fleet. Running `/director` on something a single agent would handle in one pass is a waste
  of your budget — the skill's own description says so and refuses that framing, but it'll
  still do what you ask.
- **It needs the `Workflow` tool.** That's part of the Claude Code harness, not something
  this repo can install. If your setup doesn't expose Workflow, `director` can't run at all
  — and it'll fail at the harness level rather than with a friendly message.

Use it for: a refactor spanning many files, an audit where you want findings independently
verified before you trust them, a migration with dozens of call sites. Not for: one bug, one
question, one file.

---

## What is a skill, if you're new to this

A folder with a `SKILL.md` in it, living in `~/.claude/skills/`. The frontmatter says when to
use it; the body says how. Claude Code reads the description, decides a skill is relevant, and
follows the instructions.

That's the entire mechanism. No plugin system, no build step, no API. You can write one in a
text editor in five minutes, and the good ones are mostly just clearly-written instructions
that encode something you learned the hard way.

See [docs/WHAT-ARE-SKILLS.md](docs/WHAT-ARE-SKILLS.md) for the longer version.

---

## A note on the SSH skill and your credentials

`ssh-remote-connection` ships with `config/.env.example` and **no** `.env`. You fill in your own
host, user and key path.

I mention it because the version I was running had my real credentials sitting in that folder
in plaintext, and I only noticed while preparing this repo. If you use it, your `.env` stays
local — check that your `.gitignore` covers it before you commit anything.

Every file in this repo was scanned twice before publishing: once for known credential shapes
(provider token prefixes, assigned passwords, private IPs, key bodies) and once for the ones
you can't predict by shape (high-entropy strings, JWTs, credentials hidden in URLs). The second
pass caught three credentials the first pass missed entirely, which is why there are two.

---

## Credits

`ssh-remote-connection` is from
[artwist-polyakov/polyakov-claude-skills](https://github.com/artwist-polyakov/polyakov-claude-skills),
MIT licensed, redistributed here with the author's copyright notice intact and the private host
configs removed. See [NOTICE](NOTICE).

Everything else is mine. MIT — take it, change it, ship it.

---

Built by [Hector Diaz](https://www.getorbix.com) for the
[AI Auto Base](https://aiautobase.com) community.

If one of these saves you an afternoon, tell me which one — that's how I know what to build
next.

— Hector

---

## 📋 Latest Changes

<!-- LATEST:BEGIN -->
## [0.1.1] - 2026-08-14

### Maintenance
- gitignore local session continuity files



## [0.1.0] - 2026-08-14

### Added
- Initial release. Project established with local-git versioning.
<!-- LATEST:END -->

See full [CHANGELOG.md](CHANGELOG.md) for complete history.


