---
name: director
description: Run a three-tier hierarchical multi-agent orchestration (Director → Sub-directors → Sub-agents) for any non-trivial task, with per-tier model routing, a verify-and-retry loop, and a peer cross-check round. Use this whenever the user types /director or says "use the director", "orchestrate this", "run the director on…", "fan out and verify", "decompose this into sub-directors", or otherwise asks for hierarchical multi-agent orchestration where work is decomposed, delegated to the best model per task, verified, cross-checked between agents, and judged against acceptance criteria. Built on the Workflow tool, so each run needs the workflow opt-in — invoking /director or saying "use the director" counts as that explicit opt-in. NOT for: a single quick edit or one-shot question (just answer it), a plain parallel search with no verification (use Explore/Agent), or a review with a fixed checklist (use /code-review).
trigger: /director
---

# director

Runs a **three-tier hierarchical multi-agent orchestration** for a non-trivial task: a **Director**
sets acceptance criteria and decomposes the task, **Sub-directors** plan and fan out per sub-goal,
and **Sub-agents** do the units of work — each tier on the best model for its job. Sub-directors
verify their workers with a retry loop, cross-check each other, and report up; the Director returns
a final **ACCEPT / REJECT** verdict.

## When and how this runs

The engine is the **Workflow** tool — deterministic JS orchestration with `agent()`, `parallel()`,
`pipeline()`, `log()`, and per-agent `model`/`effort`. You author a Workflow script from the
template in `references/director-workflow.js`, adapt it to the task, and run it. **Every run needs
the workflow opt-in.** When the user invokes `/director` or says "use the director" / "orchestrate
this", that *is* the explicit opt-in — you don't need to ask again.

Do not hand-spawn Agents in a loop for this. The whole point is that the Workflow runtime makes the
fan-out, the concurrency cap, the schema validation, and the budget accounting deterministic and
resumable. If a run dies partway, it can be resumed from its `runId` instead of restarted.

## The hierarchy

```
DIRECTOR  (top — owns the global task, sets acceptance criteria, gives the final verdict)
   │  decomposes the global task into N independent sub-goals
   ▼
SUB-DIRECTORS  (one per sub-goal — each picks the best model for its sub-goal)
   │  each fans out into M sub-agents
   ▼
SUB-AGENTS  (workers — each runs on the best model for its specific unit of work)
```

## Flow (implement exactly)

1. **Director** receives the global task, writes explicit, testable **acceptance criteria**, then
   decomposes the task into independent sub-goals and spawns one **sub-director** per sub-goal.
2. Each **sub-director** decomposes its sub-goal into units of work and spawns **sub-agents**,
   choosing the best model per unit (see Model Routing).
3. Each **sub-agent** does its unit and **reports its result to its sub-director** as
   schema-validated structured output.
4. The **sub-director verifies** each result against the sub-goal's criteria. **If a result is wrong
   or incomplete, it sends the work back to the sub-agent with the specific defect and asks for a
   correction** — looping until it passes or the retry cap is hit (default **2** retries). Anything
   still failing at the cap is logged and surfaced as ❌ — never silently passed.
5. Before reporting up, sub-directors on the same global task **compare notes** — a cross-check
   round (see Peer Cross-Check) where each sees the others' results, reconciles overlaps/duplicates,
   and flags contradictions.
6. Each **sub-director reports its verified, reconciled result to the Director.**
7. The **Director judges** the combined result against the global acceptance criteria and returns
   **ACCEPT** or **REJECT + reason**. On REJECT it may re-dispatch the failing sub-goal(s).

## Model Routing ("best model for the task")

Route each agent to a tier by the *nature of the work*, not one-size-fits-all. This block lives at
the top of the Workflow template (the `ROUTING` object) so it's easy to edit. The Director may
**override per-run** — bump a sub-goal to `opus` when it's unusually hard, drop a unit to `haiku`
when it's trivial.

| Work type | Model | Effort |
|---|---|---|
| Global decomposition, final acceptance judgment (Director) | `opus` | `high` |
| Sub-goal planning + verification of worker output (Sub-director) | `opus` or `sonnet` | `high` for verify |
| Substantive implementation / analysis / writing (Sub-agent) | `sonnet` | `medium` |
| Mechanical, cheap, high-volume units (rename, extract, format) | `haiku` | `low` |

The reason verification runs at **high** effort even when the work ran at medium is that catching a
subtle wrong answer is harder than producing a plausible one — the checker needs more room to think
than the worker did.

## Peer Cross-Check between sub-directors

Real-time agent-to-agent chat isn't how the runtime works — agents are isolated. Implement "the
sub-directors talk between them" as a **barrier + shared-notes synthesis round**:

- Run all sub-directors to their verified-result stage. `await pipeline(...)` returning every result
  together **is** the barrier — that array is the synchronization point.
- Feed each sub-director a compact digest of every *other* sub-director's result and ask it to:
  reconcile overlaps, surface contradictions, and note anything a peer found that changes its own
  answer. Only after this round do they report up.
- If the sub-goals are genuinely independent (no shared global state), **skip** the round and say so
  in the status output — don't pay the barrier cost for nothing. The Director signals this by
  setting `cross_check_needed: false` during decomposition.

## Live Status Board (required)

Maintain and print a status board throughout the run via `log()` narrator lines, refreshed at every
state transition, so the user can see what each sub-director is doing.

```
DIRECTOR — global task: <one line>
  ✅ SD1  Research competitors        (done — 3 sub-agents, verified)
  🔄 SD2  Draft the spec              (verifying — 1 retry in flight)
  ⏳ SD3  Build the test matrix        (running — 4 sub-agents)
  ⏸️  SD4  Cross-check pending
Legend: ✅ done · 🔄 verifying · ⏳ running · ⏸️ waiting · ❌ failed cap
```

Each line shows the sub-director's label, current status, sub-agent count, and a checkmark when
finished. The template's `renderBoard()` helper does this — call it on every transition.

## Structured contracts (JSON Schemas)

Use the Workflow `agent(..., { schema })` option so validation happens at the tool layer and agents
retry on malformed output. The three contracts:

- **Sub-agent → sub-director:** `{ unit, result, evidence, self_check }`
- **Sub-director → director:** `{ subgoal, status: "accept" | "needs_rework", result, verified_by, retries_used, peer_notes }`
- **Director verdict:** `{ verdict: "ACCEPT" | "REJECT", failing_subgoals, reason, summary }`

Full schema objects are defined at the top of `references/director-workflow.js`.

## Deliverables each run

1. The live status board, refreshed to completion.
2. The Director's final **ACCEPT / REJECT** verdict with the reason.
3. A short synthesis of the combined verified result.
4. A run log: which model each tier used, retry counts, and anything that hit the retry cap.

## Guardrails

- **Retry cap** per sub-agent (default 2) — never loop forever, never silently accept a failing
  unit; surface it as ❌ on the board.
- **Concurrency** — rely on the Workflow runtime's built-in cap; don't spawn unbounded agents.
- **Cost awareness** — honor `budget.total` if a token target is set; scale the number of
  sub-directors / sub-agents to the budget and `log()` anything dropped.
- **No silent truncation** — if the Director caps sub-goals or samples, say so in the output.

## How to run it (step by step)

1. Copy `references/director-workflow.js` into a working script (or read it and adapt inline).
2. Adjust the `ROUTING` table only if this task needs a different cost profile than the balanced
   default.
3. Invoke the **Workflow** tool, passing the global task as `args`:
   `Workflow({ script: <the adapted script>, args: { task: "<the user's global task>" } })`.
   The template also runs as-is with no args on a sample task, so you can smoke-test it first.
4. The workflow runs in the background and streams the status board via `log()`. When it returns,
   relay the four deliverables above to the user — the workflow's return value is not shown to them.
5. If it hit the retry cap on anything (❌) or the Director returned **REJECT**, surface that
   plainly and offer to re-dispatch the failing sub-goal(s).

## Worked example

**User:** `/director audit this repo for correctness bugs and propose fixes`

- **Director** (opus/high) writes acceptance criteria — "every reported bug names a file:line, a
  concrete failing input, and a proposed fix; no duplicate reports" — then decomposes into 3
  independent sub-goals and sets `cross_check_needed: true` (they may find overlapping bugs):
  - **SD1 — Core logic & data flow** (sonnet)
  - **SD2 — Error handling & edge cases** (sonnet)
  - **SD3 — Concurrency & resource lifecycle** (opus, flagged unusually hard)
- Each **sub-director** splits its sub-goal into per-module units and fans out **sub-agents**
  (sonnet/medium for analysis; a haiku/low unit just greps for `TODO`/`FIXME` and unhandled
  rejections). Each sub-agent returns `{ unit, result, evidence, self_check }`.
- Each **sub-director verifies** every finding against the criteria. A finding with no failing input
  gets sent back once with the defect "no concrete repro"; the sub-agent returns a repro; it passes.
  One flaky finding hits the retry cap and is surfaced as ❌.
- **Cross-check barrier**: all three sub-directors' verified results are collected, then each gets a
  digest of the others'. SD1 and SD2 both flagged the same null-deref; they reconcile it to one
  finding in `peer_notes`.
- Each **sub-director reports up** `{ subgoal, status, result, verified_by, retries_used, peer_notes }`.
- **Director judges**: criteria met except the one ❌ → returns **REJECT** naming SD's flaky unit,
  or **ACCEPT** with the ❌ noted, depending on whether that unit was load-bearing. Either way the
  verdict, the synthesis, and the run log are surfaced to the user.

The status board over the run looks like:

```
DIRECTOR — global task: audit this repo for correctness bugs and propose fixes
  ✅ SD1  Core logic & data flow         (done — 4 sub-agents, verified)
  🔄 SD2  Error handling & edge cases    (verifying — 1 retry in flight)
  ⏳ SD3  Concurrency & resource lifecycle (running — 3 sub-agents)
Legend: ✅ done · 🔄 verifying · ⏳ running · ⏸️ waiting · ❌ failed cap
```

## Reference

- `references/director-workflow.js` — the full Workflow script template: the `ROUTING` table, the
  three JSON schemas, the Director decomposition agent, the sub-goal `pipeline()` (plan → execute
  with the retry-until-verified loop), the `parallel()` cross-check barrier, the Director verdict,
  the `renderBoard()` status helper, and budget-aware sub-goal capping. Runs as-is on a sample task;
  adapt the prompts to the real task.
