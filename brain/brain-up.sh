#!/usr/bin/env bash
#
# Bring the stack up correctly — the one command to run before a class,
# a rehearsal, or after any reboot.
#
#   bash brain-up.sh
#
# Why this exists instead of just `docker compose up -d`:
#
#   1. `depends_on` only orders containers during `compose up`. After a HOST
#      or VM reboot, Docker's restart policy brings both back simultaneously
#      (measured: 3 milliseconds apart), n8n loses the race to Postgres, gives
#      up after 5 retries, and then serves:
#          {"code":503,"message":"Database is not ready!"}
#      The container says "Up". Nothing looks broken. It is broken.
#
#   2. An abrupt shutdown can leave the compose network in a zombie state:
#      both containers attached, both with valid IPs, and n8n still unable to
#      resolve or reach `postgres`. `docker compose restart` does NOT fix that
#      — it reuses the same network. Only `down` + `up` recreates it.
#
# So: verify first, and if the stack is sick, recreate rather than restart.

set -uo pipefail
cd "$(dirname "$0")" || exit 1

D="docker"; docker info >/dev/null 2>&1 || D="sudo docker"

green() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn()  { printf '  \033[33m!\033[0m %s\n' "$*"; }

usable() {
  local h w
  h=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5678/healthz 2>/dev/null)
  w=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5678/webhook/brain 2>/dev/null)
  [ "$h" = "200" ] && [ "$w" = "200" ]
}

echo "==> Starting the stack"
$D compose up -d >/dev/null 2>&1

echo "==> Waiting (n8n needs ~25s from cold, longer on first ever run)"
for i in $(seq 1 24); do
  usable && { green "n8n is up and the webhook answers"; break; }
  sleep 5
done

# Not just "is the container running" — is the thing actually usable.
if ! usable; then
  warn "n8n is not answering. Recreating the network — restart would not fix this."
  $D compose down >/dev/null 2>&1
  $D compose up -d >/dev/null 2>&1
  for i in $(seq 1 24); do
    usable && { green "recovered after recreate"; break; }
    sleep 5
  done
fi

echo
if usable; then
  rows=$($D compose exec -T postgres psql -U brain -d brain -tAc "SELECT count(*) FROM messages;" 2>/dev/null | tr -d '\r ')
  green "healthz 200 · webhook 200 · ${rows:-0} rows in brain.messages"
  echo
  echo "  n8n        http://localhost:5678"
  echo "             (the root path 404s on n8n 2.x — that is normal)"
  echo "  dashboard  open dashboard.html"
  echo
  echo "  Run the demo workflow, then watch the dashboard fill."
  echo "  Start over with an empty table:"
  echo "    $D compose exec -T postgres psql -U brain -d brain -c 'TRUNCATE messages;'"
else
  warn "Still not healthy. Look at the logs:"
  echo "    $D compose logs --tail 40 n8n"
  $D compose ps --format 'table {{.Name}}\t{{.Status}}'
  exit 1
fi
