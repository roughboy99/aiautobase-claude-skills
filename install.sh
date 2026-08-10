#!/usr/bin/env bash
#
# Installs the aiautobase-claude-skills into ~/.claude/skills/.
#
# Works two ways:
#   1. From a clone:  ./install.sh
#   2. Piped:         curl -fsSL https://.../install.sh | bash
#
# When piped there is no script file on disk, so we shallow-clone to a temp dir
# first. Nothing is ever overwritten - a skill you already have wins.

set -euo pipefail

REPO_URL="https://github.com/roughboy99/aiautobase-claude-skills.git"
SKILLS=(
  okthanks mermaid plantuml python-diagrams go-diagrams markmap
  json-canvas txt2csv ssh-remote-connection write-a-skill find-skills
)

# Colors only when attached to a terminal.
if [ -t 1 ]; then
  C_STEP=$'\033[36m'; C_OK=$'\033[32m'; C_SKIP=$'\033[33m'; C_OFF=$'\033[0m'
else
  C_STEP=''; C_OK=''; C_SKIP=''; C_OFF=''
fi
step() { printf '%s==> %s%s\n' "$C_STEP" "$1" "$C_OFF"; }
ok()   { printf '%s    %s%s\n' "$C_OK"   "$1" "$C_OFF"; }
skip() { printf '%s    %s%s\n' "$C_SKIP" "$1" "$C_OFF"; }

TEMP_CLONE=""
cleanup() { [ -n "$TEMP_CLONE" ] && [ -d "$TEMP_CLONE" ] && rm -rf "$TEMP_CLONE" || true; }
trap cleanup EXIT

# --- Locate the source tree -------------------------------------------------
# When piped, BASH_SOURCE points at nothing useful, so test for a real skills/
# directory rather than trusting the script path.
SOURCE_DIR=""
SELF_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -n "$SELF_DIR" ] && [ -d "$SELF_DIR/skills" ]; then
  SOURCE_DIR="$SELF_DIR"
  step "Installing from local clone: $SOURCE_DIR"
else
  command -v git >/dev/null 2>&1 || {
    echo "Error: git is required to install this way." >&2
    echo "Install git, or clone the repo manually and run ./install.sh from inside it." >&2
    exit 1
  }
  TEMP_CLONE="$(mktemp -d "${TMPDIR:-/tmp}/aiab-skills-XXXXXXXX")"
  step "Downloading $REPO_URL"
  git clone --depth 1 --quiet "$REPO_URL" "$TEMP_CLONE"
  SOURCE_DIR="$TEMP_CLONE"
fi

SRC_SKILLS="$SOURCE_DIR/skills"
[ -d "$SRC_SKILLS" ] || { echo "Error: no skills/ directory in $SOURCE_DIR" >&2; exit 1; }

# --- Target ----------------------------------------------------------------
TARGET="$HOME/.claude/skills"
step "Target: $TARGET"
if [ ! -d "$TARGET" ]; then
  mkdir -p "$TARGET"
  ok "created $TARGET"
fi

# --- Install ---------------------------------------------------------------
installed=()
skipped=()

step "Installing skills"
for s in "${SKILLS[@]}"; do
  from="$SRC_SKILLS/$s"
  to="$TARGET/$s"

  if [ ! -d "$from" ]; then
    skip "$s - not in this repo, skipping"
    continue
  fi

  if [ -e "$to" ]; then
    skipped+=("$s")
    skip "$s - already installed, left untouched"
  else
    cp -R "$from" "$TARGET/"
    installed+=("$s")
    ok "$s"
  fi
done

# --- okthanks config -------------------------------------------------------
OK_DIR="$TARGET/okthanks"
OK_CONFIG="$OK_DIR/config.json"
OK_EXAMPLE="$OK_DIR/config.example.json"
needs_setup=0

if [ -f "$OK_EXAMPLE" ] && [ ! -f "$OK_CONFIG" ]; then
  cp "$OK_EXAMPLE" "$OK_CONFIG"
  needs_setup=1
fi

# --- Summary ---------------------------------------------------------------
echo
printf '%sDone.%s\n' "$C_OK" "$C_OFF"
if [ ${#installed[@]} -gt 0 ]; then
  echo "  installed: ${#installed[@]} - ${installed[*]}"
else
  echo "  installed: 0"
fi
if [ ${#skipped[@]} -gt 0 ]; then
  printf '%s  skipped:   %s - %s%s\n' "$C_SKIP" "${#skipped[@]}" "${skipped[*]}" "$C_OFF"
  printf '%s             (you already had these; your versions were kept)%s\n' "$C_SKIP" "$C_OFF"
fi

if [ "$needs_setup" -eq 1 ]; then
  cat <<EOF

One more step - okthanks needs two paths before it will run:

  Edit: $OK_CONFIG

    "vault_path":     your Obsidian vault root
    "workspace_root": the folder your projects live under

Then say 'ok thanks' at the end of a Claude Code session.
EOF
fi
