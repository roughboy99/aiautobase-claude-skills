export const meta = {
  name: 'director',
  description: 'Three-tier hierarchical orchestration: Director decomposes and sets acceptance criteria, Sub-directors plan/fan-out/verify per sub-goal, Sub-agents do the work — with per-tier model routing, a verify-and-retry loop, and a peer cross-check barrier.',
  whenToUse: 'Non-trivial tasks worth decomposing, delegating to the best model per unit, verifying, cross-checking between agents, and judging against acceptance criteria.',
  phases: [
    { title: 'Decompose', detail: 'Director writes acceptance criteria + independent sub-goals', model: 'opus' },
    { title: 'Plan & Execute', detail: 'Each sub-director plans units and fans out sub-agents, verifying with a retry loop' },
    { title: 'Cross-Check', detail: 'Barrier: sub-directors reconcile overlaps/contradictions from a digest of peers' },
    { title: 'Verdict', detail: 'Director judges the combined result: ACCEPT / REJECT', model: 'opus' },
  ],
}

// ─────────────────────────────────────────────────────────────────────────────
// MODEL ROUTING — "best model for the task". Edit here to change the cost profile.
// The Director may override per-run (bump a hard sub-goal to opus; drop a trivial
// unit to haiku). Verification runs hotter than the work it checks, because
// catching a subtly-wrong answer is harder than producing a plausible one.
// ─────────────────────────────────────────────────────────────────────────────
const ROUTING = {
  director:    { model: 'opus',   effort: 'high'   }, // decomposition + final judgment
  subdirector: { model: 'sonnet', effort: 'high'   }, // planning + verification of workers
  verify:      { effort: 'high'   },                  // effort floor for any verify call
  worker:      { model: 'sonnet', effort: 'medium' }, // substantive implementation/analysis
  cheap:       { model: 'haiku',  effort: 'low'    }, // mechanical high-volume units
}

const MAX_RETRIES = 2 // per sub-agent unit; hit the cap → surfaced as ❌, never silently passed

// ─────────────────────────────────────────────────────────────────────────────
// STRUCTURED CONTRACTS (JSON Schemas). agent({schema}) validates at the tool
// layer and makes the agent retry on malformed output, so the JS never parses text.
// ─────────────────────────────────────────────────────────────────────────────
const DECOMPOSE_SCHEMA = {
  type: 'object',
  required: ['criteria', 'cross_check_needed', 'subgoals'],
  properties: {
    criteria: { type: 'array', items: { type: 'string' }, description: 'Explicit, testable acceptance criteria for the whole task.' },
    cross_check_needed: { type: 'boolean', description: 'True if sub-goals share global state and could overlap/contradict; false if genuinely independent.' },
    subgoals: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'title', 'description'],
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          description: { type: 'string' },
          model: { type: 'string', enum: ['opus', 'sonnet', 'haiku'], description: 'Optional per-sub-goal override for the sub-director.' },
          effort: { type: 'string', enum: ['low', 'medium', 'high', 'xhigh', 'max'] },
          rationale: { type: 'string', description: 'Why this model/effort for this sub-goal.' },
        },
      },
    },
  },
}

const PLAN_SCHEMA = {
  type: 'object',
  required: ['units'],
  properties: {
    units: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'description'],
        properties: {
          id: { type: 'string' },
          description: { type: 'string' },
          model: { type: 'string', enum: ['opus', 'sonnet', 'haiku'] },
          effort: { type: 'string', enum: ['low', 'medium', 'high', 'xhigh', 'max'] },
          cheap: { type: 'boolean', description: 'Mechanical/high-volume unit → route to the cheap tier.' },
        },
      },
    },
  },
}

// Sub-agent → sub-director
const SUBAGENT_SCHEMA = {
  type: 'object',
  required: ['unit', 'result', 'evidence', 'self_check'],
  properties: {
    unit: { type: 'string' },
    result: { type: 'string' },
    evidence: { type: 'string', description: 'Concrete support: file:line, a repro, a quote, a measurement.' },
    self_check: { type: 'string', description: 'How the agent checked its own work before returning.' },
  },
}

const VERIFY_SCHEMA = {
  type: 'object',
  required: ['passes', 'defects'],
  properties: {
    passes: { type: 'boolean' },
    defects: { type: 'array', items: { type: 'string' }, description: 'Specific, actionable defects to send back. Empty when it passes.' },
    notes: { type: 'string' },
  },
}

const PEER_SCHEMA = {
  type: 'object',
  required: ['peer_notes', 'revised_result'],
  properties: {
    peer_notes: { type: 'string', description: 'Overlaps reconciled, duplicates merged, contradictions flagged.' },
    revised_result: { type: 'string', description: 'The result after reconciling with peers (unchanged if nothing to reconcile).' },
  },
}

// Director verdict
const VERDICT_SCHEMA = {
  type: 'object',
  required: ['verdict', 'reason', 'summary'],
  properties: {
    verdict: { type: 'string', enum: ['ACCEPT', 'REJECT'] },
    failing_subgoals: { type: 'array', items: { type: 'string' } },
    reason: { type: 'string' },
    summary: { type: 'string', description: 'Short synthesis of the combined verified result.' },
  },
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE STATUS BOARD — refreshed via log() at every state transition.
// ─────────────────────────────────────────────────────────────────────────────
const ICONS = { waiting: '⏸️', running: '⏳', verifying: '🔄', crosscheck: '🔄', done: '✅', failed: '❌' }
const board = {}          // id -> { label, title, status, note }
const boardOrder = []     // preserves sub-director order

function setBoard(id, patch) {
  board[id] = Object.assign(board[id] || {}, patch)
  renderBoard()
}

function renderBoard() {
  const lines = ['DIRECTOR — global task: ' + globalTask]
  for (const id of boardOrder) {
    const b = board[id]
    lines.push('  ' + (ICONS[b.status] || '⏳') + ' ' + b.label + '  ' + b.title + '  (' + b.note + ')')
  }
  lines.push('Legend: ✅ done · 🔄 verifying · ⏳ running · ⏸️ waiting · ❌ failed cap')
  log(lines.join('\n'))
}

// ─────────────────────────────────────────────────────────────────────────────
// Retry-until-verified loop for ONE unit of work. Not a pipeline stage —
// pipelines fan out, they don't loop; ordinary JS control flow does the looping.
// ─────────────────────────────────────────────────────────────────────────────
async function runUnitWithVerification(unit, subgoal, criteria, sd) {
  const route = unit.cheap ? ROUTING.cheap : { model: unit.model || ROUTING.worker.model, effort: unit.effort || ROUTING.worker.effort }
  let attempt = 0
  let feedback = null
  let last = null

  while (attempt <= MAX_RETRIES) {
    const workPrompt =
      'You are a sub-agent under sub-director "' + sd.title + '" for the global task:\n' + globalTask +
      '\n\nYour unit of work:\n' + unit.description +
      '\n\nAcceptance criteria for the parent sub-goal:\n- ' + criteria.join('\n- ') +
      (feedback ? '\n\nA PRIOR ATTEMPT WAS REJECTED. Fix exactly these defects and resubmit:\n- ' + feedback : '') +
      '\n\nDo the unit and return the structured result with concrete evidence.'

    const work = await agent(workPrompt, {
      label: sd.label + '·' + unit.id + (attempt ? ' retry' + attempt : ''),
      phase: 'Plan & Execute',
      model: route.model,
      effort: route.effort,
      schema: SUBAGENT_SCHEMA,
    })
    if (!work) { // agent died on a terminal error / was skipped
      return { unit: unit.id, result: null, evidence: null, verified: false, retries_used: attempt, defect: 'sub-agent produced no result', model: route.model }
    }
    last = work

    const verdict = await agent(
      'You are the sub-director "' + sd.title + '" verifying a sub-agent result against the sub-goal criteria.' +
      '\n\nCriteria:\n- ' + criteria.join('\n- ') +
      '\n\nUnit: ' + unit.description +
      '\n\nSub-agent result:\n' + work.result +
      '\n\nEvidence offered:\n' + work.evidence +
      '\n\nBe adversarial. It passes ONLY if it fully meets the criteria and the evidence actually supports it. ' +
      'If not, list specific, actionable defects to send back.',
      { label: sd.label + '·' + unit.id + ' verify', phase: 'Plan & Execute', model: ROUTING.subdirector.model, effort: ROUTING.verify.effort, schema: VERIFY_SCHEMA },
    )

    if (verdict && verdict.passes) {
      return { unit: unit.id, result: work.result, evidence: work.evidence, verified: true, retries_used: attempt, model: route.model }
    }
    feedback = verdict ? verdict.defects.join('; ') : 'verifier returned no verdict'
    attempt++
  }

  // Hit the retry cap — surface it, never silently pass it.
  return { unit: unit.id, result: last ? last.result : null, evidence: last ? last.evidence : null, verified: false, retries_used: MAX_RETRIES, defect: feedback, model: route.model }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLOBAL TASK — from args ({task:"..."} or a bare string). The default is a
// self-contained sample so the template runs as-is for a smoke test.
// ─────────────────────────────────────────────────────────────────────────────
const DEFAULT_TASK = 'Research and summarize the tradeoffs between REST and GraphQL for a mid-size SaaS API, and give a clear recommendation with reasoning.'
const globalTask = (typeof args === 'string' && args.trim()) ? args : (args && args.task) ? args.task : DEFAULT_TASK

// Budget-aware sub-goal cap: scale the fan-out to any token target the user set.
const SUBGOAL_CAP = budget.total ? Math.max(2, Math.min(6, Math.floor(budget.total / 150000))) : 5

// ── TIER 1: DIRECTOR decomposes ──────────────────────────────────────────────
phase('Decompose')
log('DIRECTOR (' + ROUTING.director.model + '/' + ROUTING.director.effort + ') — writing acceptance criteria and decomposing the task…')

const plan = await agent(
  'You are the DIRECTOR of a hierarchical multi-agent team. The global task is:\n\n' + globalTask +
  '\n\n1) Write explicit, testable ACCEPTANCE CRITERIA for the whole task.' +
  '\n2) Decompose the task into INDEPENDENT sub-goals (at most ' + SUBGOAL_CAP + '). Each becomes one sub-director. ' +
  'Prefer sub-goals that can proceed without waiting on each other.' +
  '\n3) For each sub-goal, optionally recommend a model/effort (opus for unusually hard, sonnet default, haiku for trivial) with a one-line rationale.' +
  '\n4) Set cross_check_needed=true only if the sub-goals share global state and could overlap or contradict; false if they are genuinely independent.',
  { label: 'director:decompose', phase: 'Decompose', model: ROUTING.director.model, effort: ROUTING.director.effort, schema: DECOMPOSE_SCHEMA },
)

if (!plan || !plan.subgoals || !plan.subgoals.length) {
  return { verdict: 'REJECT', reason: 'Director failed to decompose the task into sub-goals.', summary: '', board }
}

let subgoals = plan.subgoals
if (subgoals.length > SUBGOAL_CAP) {
  log('⚠️  Director proposed ' + subgoals.length + ' sub-goals; capping to ' + SUBGOAL_CAP + ' for the budget. Dropped: ' +
      subgoals.slice(SUBGOAL_CAP).map(function (s) { return s.title }).join(', '))
  subgoals = subgoals.slice(0, SUBGOAL_CAP)
}

// Seed the status board.
subgoals.forEach(function (sg, i) {
  sg.label = 'SD' + (i + 1)
  boardOrder.push(sg.id)
  board[sg.id] = { label: sg.label, title: sg.title, status: 'waiting', note: 'queued' }
})
renderBoard()

// ── TIERS 2 & 3: each SUB-DIRECTOR plans, fans out SUB-AGENTS, verifies ───────
// pipeline() runs each sub-goal through plan → execute with NO barrier between
// stages, so a fast sub-goal can be executing while a slow one is still planning.
// The `await` on pipeline() collects every verified result together — that IS
// the barrier the cross-check round needs.
phase('Plan & Execute')

const sdResults = await pipeline(
  subgoals,

  // Stage 1 — sub-director plans its units of work.
  async function planStage(sg) {
    setBoard(sg.id, { status: 'running', note: 'planning' })
    const sdModel = sg.model || ROUTING.subdirector.model
    const sdEffort = sg.effort || ROUTING.subdirector.effort
    const planned = await agent(
      'You are sub-director "' + sg.title + '" for the global task:\n' + globalTask +
      '\n\nYour sub-goal:\n' + sg.description +
      '\n\nGlobal acceptance criteria (your work must help satisfy these):\n- ' + plan.criteria.join('\n- ') +
      '\n\nDecompose your sub-goal into concrete units of work, one sub-agent each. ' +
      'Mark cheap=true for mechanical/high-volume units (grep, rename, format) so they route to a cheaper model. ' +
      'Keep the number of units proportional to the sub-goal — do not pad.',
      { label: sg.label + ':plan', phase: 'Plan & Execute', model: sdModel, effort: sdEffort, schema: PLAN_SCHEMA },
    )
    const units = planned && planned.units && planned.units.length ? planned.units : [{ id: 'u1', description: sg.description }]
    return { sg: sg, sdModel: sdModel, units: units }
  },

  // Stage 2 — fan out sub-agents (each with its own retry-until-verified loop),
  // then assemble this sub-director's report.
  async function executeStage(planned) {
    const sg = planned.sg
    setBoard(sg.id, { status: 'verifying', note: planned.units.length + ' sub-agents' })

    const unitResults = await parallel(planned.units.map(function (unit) {
      return function () { return runUnitWithVerification(unit, sg, plan.criteria, sg) }
    }))

    const done = unitResults.filter(Boolean)
    const capped = done.filter(function (u) { return !u.verified })
    const status = capped.length ? 'needs_rework' : 'accept'

    setBoard(sg.id, {
      status: capped.length ? 'failed' : 'done',
      note: capped.length
        ? (planned.units.length + ' sub-agents, ' + capped.length + ' hit retry cap')
        : (planned.units.length + ' sub-agents, verified'),
    })

    const resultText = done.map(function (u) {
      return '• [' + u.unit + (u.verified ? '' : ' ❌ UNVERIFIED') + '] ' + (u.result || '(no result)')
    }).join('\n')

    return {
      subgoal: sg.title,
      subgoalId: sg.id,
      label: sg.label,
      status: status,
      result: resultText,
      verified_by: sg.label + ' (' + ROUTING.subdirector.model + '/' + ROUTING.verify.effort + ')',
      retries_used: done.reduce(function (a, u) { return a + (u.retries_used || 0) }, 0),
      capped_units: capped.map(function (u) { return u.unit }),
      peer_notes: '',
      models_used: Array.from(new Set(done.map(function (u) { return u.model }))),
    }
  },
)

const verified = sdResults.filter(Boolean)

// ── PEER CROSS-CHECK (barrier + shared-notes) ────────────────────────────────
// Real agent-to-agent chat isn't possible (agents are isolated), so each
// sub-director instead reads a compact digest of every OTHER sub-director's
// result and reconciles. Skip entirely when sub-goals are independent.
if (plan.cross_check_needed && verified.length > 1) {
  phase('Cross-Check')
  verified.forEach(function (r) { setBoard(r.subgoalId, { status: 'crosscheck', note: 'reconciling with peers' }) })

  const reconciled = await parallel(verified.map(function (r) {
    return async function () {
      const digest = verified
        .filter(function (o) { return o.subgoalId !== r.subgoalId })
        .map(function (o) { return '### ' + o.label + ' — ' + o.subgoal + '\n' + o.result })
        .join('\n\n')
      const peer = await agent(
        'You are sub-director "' + r.subgoal + '". Before reporting up, reconcile your result with your peers.' +
        '\n\nYOUR result:\n' + r.result +
        '\n\nYOUR PEERS\' results:\n' + digest +
        '\n\nReconcile overlaps, merge duplicates, and flag any contradiction between your result and a peer\'s. ' +
        'If a peer found something that changes your answer, revise it. Otherwise keep it and say so.',
        { label: r.label + ':crosscheck', phase: 'Cross-Check', model: ROUTING.subdirector.model, effort: ROUTING.verify.effort, schema: PEER_SCHEMA },
      )
      if (peer) { r.peer_notes = peer.peer_notes; r.result = peer.revised_result || r.result }
      setBoard(r.subgoalId, { status: r.capped_units.length ? 'failed' : 'done', note: r.capped_units.length ? (r.capped_units.length + ' hit retry cap') : 'verified, reconciled' })
      return r
    }
  }))
  reconciled.forEach(function (r, i) { if (r) verified[i] = r })
} else {
  log('ℹ️  Cross-check skipped: ' + (verified.length <= 1 ? 'only one sub-director.' : 'the Director marked the sub-goals independent (no shared global state).'))
}

// ── TIER 1: DIRECTOR judges the combined result ──────────────────────────────
phase('Verdict')
const combined = verified.map(function (r) {
  return '### ' + r.label + ' — ' + r.subgoal + ' [' + r.status + ', ' + r.retries_used + ' retries' +
    (r.capped_units.length ? ', ❌ ' + r.capped_units.length + ' hit cap' : '') + ']\n' +
    r.result + (r.peer_notes ? '\n(peer notes: ' + r.peer_notes + ')' : '')
}).join('\n\n')

const verdict = await agent(
  'You are the DIRECTOR judging the combined, verified result of your team against the global acceptance criteria.' +
  '\n\nGlobal task:\n' + globalTask +
  '\n\nAcceptance criteria:\n- ' + plan.criteria.join('\n- ') +
  '\n\nCombined sub-director results:\n' + combined +
  '\n\nReturn ACCEPT only if the criteria are met. If any are unmet (including anything that hit the retry cap and was load-bearing), ' +
  'return REJECT, name the failing sub-goals, and give the reason. Include a short synthesis of the combined result either way.',
  { label: 'director:verdict', phase: 'Verdict', model: ROUTING.director.model, effort: ROUTING.director.effort, schema: VERDICT_SCHEMA },
)

renderBoard()

// ── RUN LOG (deliverable #4) ─────────────────────────────────────────────────
const runLog = {
  models: {
    director: ROUTING.director.model + '/' + ROUTING.director.effort,
    subdirectors: ROUTING.subdirector.model + '/' + ROUTING.subdirector.effort + ' (verify at ' + ROUTING.verify.effort + ')',
    workers: verified.reduce(function (acc, r) { acc[r.label] = r.models_used; return acc }, {}),
  },
  total_retries: verified.reduce(function (a, r) { return a + r.retries_used }, 0),
  hit_retry_cap: verified.filter(function (r) { return r.capped_units.length }).map(function (r) { return { subdirector: r.label, units: r.capped_units } }),
  cross_check: (plan.cross_check_needed && verified.length > 1) ? 'ran' : 'skipped',
  subgoals_dropped_for_budget: Math.max(0, plan.subgoals.length - subgoals.length),
}

return {
  verdict: verdict || { verdict: 'REJECT', reason: 'Director verdict agent returned nothing.', summary: '' },
  criteria: plan.criteria,
  subdirectors: verified,
  runLog: runLog,
  board: board,
}
