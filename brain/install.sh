#!/usr/bin/env bash
#
# The Brain — Class 2 installer
# Docker + n8n (with ffmpeg) + Postgres, from nothing to running.
#
#   curl -fsSL https://raw.githubusercontent.com/roughboy99/aiautobase-claude-skills/main/brain/install.sh -o brain-install.sh && bash brain-install.sh
# or
#   bash install.sh
#
# Idempotent: safe to run twice. It will not overwrite an existing .env,
# because that file holds the encryption key that decrypts your credentials.
#
# Tested against Docker 29.3.1 / n8n 2.34.5 / ffmpeg 8.1.2 on 2026-08-12.

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/brain}"
TZ_DEFAULT="${GENERIC_TIMEZONE:-America/New_York}"

# ── output helpers ───────────────────────────────────────────────────────────
if [ -t 1 ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'
else
  B=''; G=''; Y=''; R=''; D=''; N=''
fi
say()  { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '  %sx%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

# ── 0. sanity ────────────────────────────────────────────────────────────────
case "$(uname -s)" in
  Linux) ;;
  Darwin|MINGW*|MSYS*|CYGWIN*)
    warn "This script installs Docker Engine, which is Linux-only."
    warn "On Mac/Windows install Docker Desktop by hand first, then re-run —"
    warn "the rest of the script works fine once Docker is present."
    ;;
esac

# ── 1. Docker ────────────────────────────────────────────────────────────────
say "Checking Docker"
if command -v docker >/dev/null 2>&1; then
  ok "docker present — $(docker --version)"
else
  if [ "$(uname -s)" != "Linux" ]; then
    die "Docker not found. Install Docker Desktop, then re-run this script."
  fi
  say "Installing Docker (get.docker.com)"
  curl -fsSL https://get.docker.com | sh
  ok "docker installed"

  # Fresh install: the daemon is not necessarily running yet.
  say "Starting the Docker service"
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now docker >/dev/null 2>&1 || true
  else
    sudo service docker start >/dev/null 2>&1 || true
  fi

  # Let this user run docker without sudo, for FUTURE shells.
  if [ "$(id -u)" -ne 0 ]; then
    sudo usermod -aG docker "$USER" || true
    warn "Added $USER to the 'docker' group (applies to your NEXT login)."
  fi
fi

# ── 1b. how do we talk to the daemon? ────────────────────────────────────────
# The classic fresh-install trap: `usermod -aG docker` does NOT affect the shell
# you are standing in, so the very next docker command fails with a permission
# error and the whole install looks broken. Rather than telling you to log out
# and start over, work out what actually works right now and use that.
DK="docker"
if ! docker info >/dev/null 2>&1; then
  if sudo -n docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
    DK="sudo docker"
    warn "Using 'sudo docker' for this run — your group membership needs a new login."
  else
    # Give a just-started daemon a moment before giving up on it.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 2
      docker info >/dev/null 2>&1 && { DK="docker"; break; }
      sudo docker info >/dev/null 2>&1 && { DK="sudo docker"; break; }
    done
  fi
fi
if ! $DK info >/dev/null 2>&1; then
  die "Docker is installed but the daemon isn't reachable. Start it, then re-run."
fi
ok "docker daemon reachable ($DK)"

# compose v2 ships as a docker plugin; the old docker-compose binary is not it.
if ${DK:-docker} compose version >/dev/null 2>&1; then
  ok "compose plugin present — $(${DK:-docker} compose version --short 2>/dev/null || echo v2)"
else
  die "'docker compose' not available. Install the compose plugin (docker-compose-plugin)."
fi

# ── 2. folder ────────────────────────────────────────────────────────────────
say "Creating $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
ok "working in $(pwd)"

# ── 3. .env — generated once, never overwritten ──────────────────────────────
say "Writing .env"
if [ -f .env ]; then
  warn ".env already exists — leaving it alone."
  warn "It holds N8N_ENCRYPTION_KEY; replacing it makes stored credentials undecryptable."
else
  gen() { openssl rand -hex "$1" 2>/dev/null || head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }
  PG_PASS="$(gen 24)"
  ENC_KEY="$(gen 32)"
  cat > .env <<EOF
# generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by install.sh — keep this file private
POSTGRES_USER=brain
POSTGRES_PASSWORD=${PG_PASS}
# n8n's own database. Our email data lives in a second database, 'brain',
# created by schema.sql.
POSTGRES_DB=n8n

# Encrypts every credential stored in n8n. BACK THIS UP off this machine.
N8N_ENCRYPTION_KEY=${ENC_KEY}

N8N_HOST=localhost
N8N_PROTOCOL=http
N8N_EDITOR_BASE_URL=http://localhost:5678/
N8N_WEBHOOK_URL=http://localhost:5678/
# must be false over plain http, or the login cookie is refused
N8N_SECURE_COOKIE=false

GENERIC_TIMEZONE=${TZ_DEFAULT}
EOF
  chmod 600 .env
  ok ".env written (chmod 600), secrets generated"
fi

# ── 3b. load .env into this shell ────────────────────────────────────────────
# Needed later to build the demo credential. Without this, ${POSTGRES_USER} is
# unset and `set -u` aborts the script right before it finishes — silently,
# because everything up to that point already printed success.
set -a
# shellcheck disable=SC1091
. ./.env
set +a
ok "loaded .env (POSTGRES_DB=${POSTGRES_DB}, user=${POSTGRES_USER})"

# ── 4. schema.sql ────────────────────────────────────────────────────────────
say "Writing schema.sql"
cat > schema.sql <<'SQLEOF'
-- The brain's memory. A SEPARATE database from n8n's own, on purpose:
-- n8n keeps ~125 tables in its database and its schema moves fast (it already
-- has chat_hub_messages, agents_messages, instance_ai_messages). A table
-- called `messages` beside those is a collision waiting for the next image
-- pull. Same container, two databases — migrations can't cross the boundary.

CREATE DATABASE brain;

\connect brain

CREATE TABLE IF NOT EXISTS messages (
    id            BIGSERIAL PRIMARY KEY,
    account       TEXT        NOT NULL,          -- 'business' | 'personal'
    message_id    TEXT        UNIQUE,            -- RFC Message-ID; stops double-inserts
    from_email    TEXT        NOT NULL,
    from_name     TEXT,
    subject       TEXT,
    body_excerpt  TEXT,                          -- first ~800 chars, what the model saw
    received_at   TIMESTAMPTZ NOT NULL,
    category      TEXT        NOT NULL,          -- client|lead|invoice|vendor|newsletter|personal|noise
    reason        TEXT,
    needs_reply   BOOLEAN     NOT NULL DEFAULT FALSE,
    replied       BOOLEAN     NOT NULL DEFAULT FALSE,
    replied_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_received ON messages (received_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_category ON messages (category);
CREATE INDEX IF NOT EXISTS idx_messages_followup ON messages (needs_reply, replied)
    WHERE needs_reply AND NOT replied;

CREATE OR REPLACE VIEW needs_followup AS
SELECT id, account, from_email, from_name, subject, category, reason, received_at
FROM   messages
WHERE  needs_reply AND NOT replied
ORDER  BY received_at DESC;

CREATE OR REPLACE VIEW category_counts_7d AS
SELECT account, category, COUNT(*) AS n
FROM   messages
WHERE  received_at > NOW() - INTERVAL '7 days'
GROUP  BY account, category
ORDER  BY n DESC;
SQLEOF
# Postgres reads this INSIDE the container as uid 70, not as you. A restrictive
# umask (0007/0077) makes the file unreadable there and initdb silently skips it
# with "Permission denied" -- the brain database then never gets created.
chmod 644 schema.sql
ok "schema.sql written"

# ── 5. docker-compose.yml ────────────────────────────────────────────────────
say "Writing docker-compose.yml"
cat > docker-compose.yml <<'YMLEOF'
services:
  postgres:
    image: postgres:16-alpine
    container_name: bi-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./schema.sql:/docker-entrypoint-initdb.d/01-schema.sql:ro
    # not published to the host — only n8n needs it, over the internal network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 10

  n8n:
    # n8n with ffmpeg baked in. The official image has no ffmpeg, and adding it
    # later means building your own.
    image: rxchi1d/n8n-ffmpeg:latest
    container_name: bi-n8n
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      # Postgres, never SQLite: SQLite drops in-flight Wait executions on
      # restart, so delayed workflows silently stop working after a reboot.
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}

      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}

      N8N_HOST: ${N8N_HOST}
      N8N_PORT: 5678
      N8N_PROTOCOL: ${N8N_PROTOCOL}
      N8N_EDITOR_BASE_URL: ${N8N_EDITOR_BASE_URL}
      N8N_WEBHOOK_URL: ${N8N_WEBHOOK_URL}
      N8N_TRUST_PROXY: "true"
      N8N_SECURE_COOKIE: ${N8N_SECURE_COOKIE}

      GENERIC_TIMEZONE: ${GENERIC_TIMEZONE}
      TZ: ${GENERIC_TIMEZONE}
      NODE_ENV: production
      N8N_RELEASE_TYPE: stable
      N8N_DIAGNOSTICS_ENABLED: "false"
      N8N_COMMUNITY_PACKAGES_ENABLED: "true"
      N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE: "true"

      # ── the unlocks ──────────────────────────────────────────────────────
      # Empty list = exclude nothing. This is what re-enables Execute Command,
      # which modern n8n ships disabled. People assume it was removed; it wasn't.
      NODES_EXCLUDE: "[]"
      NODE_FUNCTION_ALLOW_BUILTIN: "*"
      NODE_FUNCTION_ALLOW_EXTERNAL: "openai,anthropic,elevenlabs,google-api-python-client,html-to-docx"
      # Workflows may read the container env and the filesystem. Needed for
      # ffmpeg work. Safe here because this file injects NO third-party API
      # keys — put those in n8n's credential store, which is encrypted and
      # stripped on export.
      N8N_BLOCK_ENV_ACCESS_IN_NODE: "false"
      N8N_RESTRICT_FILE_ACCESS_TO: ""
      N8N_RUNNERS_MODE: regular

    ports:
      - "5678:5678"
    volumes:
      - n8n_data:/home/node/.n8n
      # uncomment when you start doing ffmpeg work:
      # - ./videos:/videos

volumes:
  postgres_data:
  n8n_data:
YMLEOF
ok "docker-compose.yml written"

# ── 6. up ────────────────────────────────────────────────────────────────────
say "Starting the stack (first run pulls ~415 MB, be patient)"
$DK compose up -d

# ── 7. wait properly ─────────────────────────────────────────────────────────
# /healthz answers ~20s BEFORE migrations finish. Waiting on it alone gives you
# a green light on a database that has no tables yet. Wait on the table count.
say "Waiting for n8n to finish its database migrations"
printf '  '
for i in $(seq 1 60); do
  n=$($DK compose exec -T postgres psql -U brain -d "${POSTGRES_DB:-n8n}" -tAc \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null | tr -d '\r ' || echo 0)
  if [ "${n:-0}" -gt 100 ]; then printf '\n'; ok "migrations complete ($n tables)"; break; fi
  printf '.'; sleep 5
done
[ "${n:-0}" -gt 100 ] || warn "still migrating after 5 min — check: docker compose logs -f n8n"

# ── 8. verify, don't assume ──────────────────────────────────────────────────
say "Verifying"
$DK compose ps --format 'table {{.Name}}\t{{.Status}}' | sed 's/^/  /'

if $DK compose exec -T n8n sh -c 'ffmpeg -version' >/dev/null 2>&1; then
  ok "ffmpeg: $($DK compose exec -T n8n sh -c 'ffmpeg -version 2>/dev/null | head -1' | cut -d' ' -f1-3)"
else
  warn "ffmpeg not found in the container"
fi

if $DK compose exec -T postgres psql -U brain -d brain -tAc \
     "SELECT to_regclass('public.messages');" 2>/dev/null | grep -q messages; then
  ok "brain database + messages table ready"
else
  warn "the 'brain' database is missing — check: docker compose logs postgres"
fi

# On a RE-RUN the migration wait above returns instantly (the tables already
# exist) while the recreated n8n container is still booting, so give /healthz
# up to 90s instead of a single shot.
code=000
for _ in $(seq 1 18); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5678/healthz 2>/dev/null) || code=000
  [ "$code" = "200" ] && break
  sleep 5
done
[ "$code" = "200" ] && ok "n8n healthy (/healthz 200)" || warn "/healthz returned $code after 90s — check: docker compose logs n8n"

# ── 9. demo workflow — runs with NO credentials of yours ─────────────────────
# The point: you can record the whole pipeline working without ever opening an
# IMAP credential on camera. The only fake part is the source (a Code node with
# sample emails). Classification, the database write and the dashboard are real.
say "Seeding the demo workflow"
mkdir -p demo
cat > demo/01-email-sort-DEMO.json <<'WFEOF'
{
  "id": "brainDemoEmail01",
  "name": "01 — Email Sort (DEMO, no credentials)",
  "nodes": [
    {
      "parameters": {},
      "id": "a1000000-0000-4000-8000-000000000001",
      "name": "Click to run",
      "type": "n8n-nodes-base.manualTrigger",
      "typeVersion": 1,
      "position": [
        -220,
        0
      ]
    },
    {
      "parameters": {
        "jsCode": "// A fake inbox. This is the ONLY thing standing in for IMAP.\n// Everything downstream is the real pipeline.\nconst now = Date.now();\nconst h = (n) => new Date(now - n * 3600 * 1000).toISOString();\n\nconst inbox = [\n  { account:'business', from_email:'jane@elmstreetproperties.com', from_name:'Jane Roe',\n    subject:'Quote for a full tear-off on Elm St',\n    body:'Hi, we have a 2,400 sq ft roof that needs a full tear-off. Can you come out this week and give us a number?', received_at:h(2) },\n  { account:'business', from_email:'billing@supplyco.com', from_name:'SupplyCo Billing',\n    subject:'Invoice 4471 — $1,240.00 due',\n    body:'Please find attached invoice 4471 for materials delivered on the 4th. Net 30. Amount due $1,240.00.', received_at:h(9) },\n  { account:'business', from_email:'mark@harborviewhoa.org', from_name:'Mark Ellis',\n    subject:'Re: gutter replacement — approved',\n    body:'The board approved the quote. When can your crew start? We would like it done before the rain.', received_at:h(20) },\n  { account:'business', from_email:'news@roofingtoday.com', from_name:'Roofing Today',\n    subject:'10 shingle trends for 2026',\n    body:'This week in roofing: architectural shingles keep gaining share, plus a look at labor costs.', received_at:h(30) },\n  { account:'business', from_email:'no-reply@fastquotes.io', from_name:'FastQuotes',\n    subject:'You have 3 new matched leads',\n    body:'Unlock 3 new homeowner leads in your area. Upgrade to Pro to see contact details.', received_at:h(46) },\n  { account:'personal', from_email:'mom@family.net', from_name:'Mom',\n    subject:'Sunday dinner?',\n    body:'Are you coming over Sunday? Let me know so I can get enough food. Bring the kids.', received_at:h(5) }\n];\n\n// message_id must be stable so re-running does NOT duplicate rows —\n// that is the ON CONFLICT guard doing its job.\nreturn inbox.map((m, i) => ({\n  json: {\n    ...m,\n    message_id: `<demo-${i + 1}@brain.local>`,\n    body_excerpt: m.body.slice(0, 800)\n  }\n}));"
      },
      "id": "a1000000-0000-4000-8000-000000000002",
      "name": "Sample Inbox",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [
        0,
        0
      ]
    },
    {
      "parameters": {
        "mode": "runOnceForEachItem",
        "jsCode": "// OFFLINE classifier — keyword rules, no API key, no cost, no network.\n// On camera this node gets REPLACED by an HTTP Request to OpenRouter.\n// Same input, same output shape, so nothing downstream changes.\n//\n// ORDER MATTERS. An existing client writing \"the board approved the quote\"\n// contains the word \"quote\" — check the client signal BEFORE the lead signal\n// or you label a paying customer as a new prospect.\nconst j = $json;\nconst subject = (j.subject || '');\nconst text = `${subject} ${j.body_excerpt}`.toLowerCase();\nconst from = (j.from_email || '').toLowerCase();\nconst isReply = /^\\s*re:/i.test(subject);\n\nlet category = 'noise';\nlet reason = 'No strong signal';\nlet needs_reply = false;\n\nif (/invoice|amount due|net 30|receipt|statement/.test(text)) {\n  category = 'invoice'; reason = 'Vendor invoice or receipt'; needs_reply = false;\n} else if (/no-reply|noreply|unsubscribe|upgrade to pro|newsletter|this week in/.test(text + ' ' + from)) {\n  category = 'newsletter'; reason = 'Marketing, nothing to do'; needs_reply = false;\n} else if (isReply || /approved|when can|crew start|reschedul|already booked/.test(text)) {\n  category = 'client'; reason = 'Existing job needs an answer'; needs_reply = true;\n} else if (/quote|estimate|tear-off|how much|give us a number|pricing/.test(text)) {\n  category = 'lead'; reason = 'Prospect asking for a price'; needs_reply = true;\n}\n\nif (j.account === 'personal' && category === 'noise') {\n  category = 'personal'; reason = 'Personal message'; needs_reply = true;\n}\n\nreturn { json: { ...j, category, reason, needs_reply } };"
      },
      "id": "a1000000-0000-4000-8000-000000000003",
      "name": "Classify (offline)",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [
        220,
        0
      ]
    },
    {
      "parameters": {
        "operation": "executeQuery",
        "query": "INSERT INTO messages (account, message_id, from_email, from_name, subject, body_excerpt, received_at, category, reason, needs_reply) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT (message_id) DO NOTHING;",
        "options": {
          "queryReplacement": "={{ $json.account }},{{ $json.message_id }},{{ $json.from_email }},{{ $json.from_name }},{{ $json.subject }},{{ $json.body_excerpt }},{{ $json.received_at }},{{ $json.category }},{{ $json.reason }},{{ $json.needs_reply }}"
        }
      },
      "id": "a1000000-0000-4000-8000-000000000004",
      "name": "Save to brain",
      "type": "n8n-nodes-base.postgres",
      "typeVersion": 2.4,
      "position": [
        440,
        0
      ],
      "credentials": {
        "postgres": {
          "id": "brainPg0000000001",
          "name": "Brain Postgres"
        }
      }
    }
  ],
  "connections": {
    "Click to run": {
      "main": [
        [
          {
            "node": "Sample Inbox",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Sample Inbox": {
      "main": [
        [
          {
            "node": "Classify (offline)",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Classify (offline)": {
      "main": [
        [
          {
            "node": "Save to brain",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  },
  "active": false,
  "settings": {
    "executionOrder": "v1"
  },
  "tags": []
}
WFEOF

# The Postgres credential, built from the .env this script just generated.
# It is a local container password, not a secret you own — but it still goes
# into n8n's encrypted credential store rather than into the workflow.
cat > demo/credentials.json <<EOF
[
  {
    "id": "brainPg0000000001",
    "name": "Brain Postgres",
    "type": "postgres",
    "data": {
      "host": "postgres",
      "port": 5432,
      "database": "brain",
      "user": "${POSTGRES_USER}",
      "password": "${POSTGRES_PASSWORD}",
      "ssl": "disable",
      "allowUnauthorizedCerts": false
    }
  }
]
EOF

$DK compose cp demo bi-n8n:/tmp/demo >/dev/null 2>&1 || $DK cp demo bi-n8n:/tmp/demo >/dev/null 2>&1
if $DK compose exec -T n8n sh -c 'n8n import:credentials --input=/tmp/demo/credentials.json' 2>&1 | grep -q "Successfully imported"; then
  ok "credential 'Brain Postgres' imported"
else
  warn "credential import failed — add it by hand in n8n (host postgres, db brain)"
fi
if $DK compose exec -T n8n sh -c 'n8n import:workflow --input=/tmp/demo/01-email-sort-DEMO.json' 2>&1 | grep -q "Successfully imported"; then
  ok "demo workflow imported"
else
  warn "workflow import failed — import demo/01-email-sort-DEMO.json from the n8n UI"
fi
rm -f demo/credentials.json || true   # generated fresh each run; never left on disk

# ── 10. what now ─────────────────────────────────────────────────────────────
ENC=$(grep '^N8N_ENCRYPTION_KEY=' .env | cut -d= -f2-)
cat <<EOF

${B}Done.${N}

  Open       ${B}http://localhost:5678${N}   (create your owner account on first visit)
             note: ${D}http://localhost:5678/ may return 404 — that's normal on some n8n 2.x builds,
             the editor lives at /home/workflows${N}

  Folder     $(pwd)
  Postgres   host ${B}postgres${N}  port 5432  database ${B}brain${N}  <- not 'n8n'
             (that's what you type into the Postgres credential inside n8n)

  ${Y}Back this up somewhere that is not this machine:${N}
  N8N_ENCRYPTION_KEY=${ENC}
  ${D}It decrypts every credential you save in n8n. Lose it and you re-enter
  all of them by hand.${N}

  Useful:
    docker compose logs -f n8n      # follow the logs
    docker compose ps               # what's running
    docker compose down             # stop (keeps data)
    docker compose down -v          # stop AND delete all data

EOF
