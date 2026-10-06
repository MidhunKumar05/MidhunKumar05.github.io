#!/usr/bin/env bash
# Eunomia installer — clones the repo, generates secrets, and brings the
# stack up with Docker Compose (SurrealDB + Rust backend + Next.js frontend).
#
# Usage:
#   curl -fsSL https://midhunkumar05.github.io/eunomia/install.sh | bash
#   curl -fsSL https://midhunkumar05.github.io/eunomia/install.sh | bash -s -- --dir ~/eunomia --ref v1.1.3
#   curl -fsSL https://midhunkumar05.github.io/eunomia/install.sh | bash -s -- --yes
#
# Flags:
#   --dir <path>       install location (default: ./eunomia)
#   --ref <ref>        git ref to check out: a tag, branch, or "latest" (default: latest release)
#   --api-key <key>    OpenAI API key, written to .env (optional, can add later in Settings)
#   --base-url <url>   browser-reachable backend URL baked into the frontend (default: http://localhost:8001)
#   --yes, -y          skip interactive prompts, accept defaults
#   --no-color         disable ANSI colors/animation

set -euo pipefail

INSTALLER_VERSION="1.1.0"

# Never hang on a credential prompt -- fail fast instead (e.g. if the repo
# isn't public yet, or the network drops mid-clone).
export GIT_TERMINAL_PROMPT=0

REPO_URL="https://github.com/Qyrhal/Eunomia.git"
API_LATEST="https://api.github.com/repos/Qyrhal/Eunomia/releases/latest"
INSTALL_DIR="eunomia"
REF="latest"
ASSUME_YES=0
OPENAI_KEY=""
API_BASE_URL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) INSTALL_DIR="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --api-key) OPENAI_KEY="$2"; shift 2 ;;
    --base-url) API_BASE_URL="$2"; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --no-color) NO_COLOR=1; shift ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Terminal plumbing: when piped via `curl | bash`, stdin IS the script, so
# `read` can't prompt from it. Reopen stdin from the controlling tty when one
# exists, so prompts still work under the pipe-to-shell convention.
# ---------------------------------------------------------------------------
IS_TTY=0
if [ -t 1 ] && [ -r /dev/tty ]; then
  IS_TTY=1
  exec 3</dev/tty
fi

if [ "${NO_COLOR:-0}" = "1" ] || [ "$IS_TTY" -eq 0 ]; then
  BOLD=""; DIM=""; RESET=""; GREEN=""; CYAN=""; YELLOW=""; RED=""; GREY=""
else
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  GREEN=$'\033[38;5;72m'; CYAN=$'\033[38;5;80m'; YELLOW=$'\033[38;5;179m'
  RED=$'\033[38;5;174m'; GREY=$'\033[38;5;245m'
fi

ok()    { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
info()  { printf "  %s›%s %s\n" "$CYAN" "$RESET" "$1"; }
warn()  { printf "  %s!%s %s\n" "$YELLOW" "$RESET" "$1"; }
fail()  { printf "  %s✗%s %s\n" "$RED" "$RESET" "$1" >&2; exit 1; }

# Runs "$@" in the background with a spinner, tails output to a logfile,
# dumps it on failure. Falls back to plain sequential output on a non-tty
# (CI logs, redirected output) where a spinner would just be line noise.
spinner() {
  local label="$1"; shift
  local log; log="$(mktemp)"
  if [ "$IS_TTY" -eq 0 ]; then
    info "$label"
    if "$@" >"$log" 2>&1; then ok "$label"; rm -f "$log"; return 0
    else fail "$label failed:"; cat "$log" >&2; rm -f "$log"; exit 1; fi
  fi

  "$@" >"$log" 2>&1 &
  local pid=$!
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  printf "  %s %s" "${frames:0:1}" "$label"
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % ${#frames} ))
    printf "\r  %s%s%s %s" "$CYAN" "${frames:$i:1}" "$RESET" "$label"
    sleep 0.08
  done
  if wait "$pid"; then
    printf "\r  %s✓%s %s%s\n" "$GREEN" "$RESET" "$label" "$(printf ' %.0s' $(seq 1 10))"
    rm -f "$log"
  else
    printf "\r  %s✗%s %s\n" "$RED" "$RESET" "$label"
    echo "$DIM--- output ---$RESET" >&2
    cat "$log" >&2
    rm -f "$log"
    exit 1
  fi
}

prompt() {
  # prompt <var-name> <question> <default>
  local __var="$1" __q="$2" __default="$3" __ans
  if [ "$ASSUME_YES" -eq 1 ] || [ "$IS_TTY" -eq 0 ]; then
    printf -v "$__var" '%s' "$__default"
    return
  fi
  printf "  %s?%s %s %s[%s]%s " "$CYAN" "$RESET" "$__q" "$GREY" "$__default" "$RESET"
  read -r __ans <&3 || __ans=""
  printf -v "$__var" '%s' "${__ans:-$__default}"
}

# ---------------------------------------------------------------------------
banner() {
  [ "$IS_TTY" -eq 1 ] && printf '\033c' 2>/dev/null || true
  printf '%s' "$GREEN$BOLD"
  cat <<'EOF'

  ███████╗██╗   ██╗███╗   ██╗ ██████╗ ███╗   ███╗██╗ █████╗
  ██╔════╝██║   ██║████╗  ██║██╔═══██╗████╗ ████║██║██╔══██╗
  █████╗  ██║   ██║██╔██╗ ██║██║   ██║██╔████╔██║██║███████║
  ██╔══╝  ██║   ██║██║╚██╗██║██║   ██║██║╚██╔╝██║██║██╔══██║
  ███████╗╚██████╔╝██║ ╚████║╚██████╔╝██║ ╚═╝ ██║██║██║  ██║
  ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═╝
EOF
  printf '%s' "$RESET"
  printf "  %sa memory you can query%s %s(installer v%s)%s\n\n" "$GREY" "$RESET" "$GREY" "$INSTALLER_VERSION" "$RESET"
}

banner

for bin in git docker curl openssl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    fail "$bin is required but not installed."
  fi
done
ok "git, docker, curl, openssl found"

if ! docker compose version >/dev/null 2>&1; then
  fail "'docker compose' (the plugin, not docker-compose) is required."
fi
ok "docker compose plugin found"

if [ "$REF" = "latest" ]; then
  REF="$(curl -fsSL --max-time 8 "$API_LATEST" 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/' || true)"
  if [ -z "$REF" ]; then
    warn "no release found yet — using main"
    REF="main"
  else
    ok "latest release: ${BOLD}${REF}${RESET}"
  fi
fi

echo
info "current directory: ${PWD}"
prompt INSTALL_DIR "Install into which directory?" "$INSTALL_DIR"
if [ "$ASSUME_YES" -eq 0 ] && [ "$IS_TTY" -eq 1 ]; then
  if [ -z "$OPENAI_KEY" ]; then
    prompt WANT_KEY "Set an OpenAI API key now? (enables embeddings/chat — optional, can add later in Settings)" "skip"
    if [ "$WANT_KEY" != "skip" ] && [ -n "$WANT_KEY" ]; then
      OPENAI_KEY="$WANT_KEY"
    fi
  fi
  if [ -z "$API_BASE_URL" ]; then
    prompt API_BASE_URL "Backend API base URL (browser-reachable, used by the frontend)" "http://localhost:8001"
  fi
fi
API_BASE_URL="${API_BASE_URL:-http://localhost:8001}"
echo

if [ -d "$INSTALL_DIR/.git" ]; then
  spinner "Updating existing checkout" bash -c "git -C '$INSTALL_DIR' fetch --depth 1 origin '$REF' && git -C '$INSTALL_DIR' checkout '$REF'"
else
  spinner "Cloning Eunomia (${REF})" bash -c "git clone --depth 1 --branch '$REF' '$REPO_URL' '$INSTALL_DIR' 2>/dev/null || git clone '$REPO_URL' '$INSTALL_DIR'; git -C '$INSTALL_DIR' checkout '$REF' 2>/dev/null || true"
fi

cd "$INSTALL_DIR"

# Pull the prebuilt image matching the checked-out ref. Only release tags
# (v1.2.3) get an image of that name pushed -- branches fall back to "latest".
case "$REF" in
  v[0-9]*) export EUNOMIA_IMAGE_TAG="$REF" ;;
esac

if [ ! -f .env ]; then
  cp .env.example .env
  JWT_SECRET="$(openssl rand -base64 32)"
  ENCRYPTION_KEY="$(openssl rand -base64 32)"
  sed -i.bak "s#^JWT_SECRET=.*#JWT_SECRET=${JWT_SECRET}#" .env
  sed -i.bak "s#^ENCRYPTION_KEY=.*#ENCRYPTION_KEY=${ENCRYPTION_KEY}#" .env
  if [ -n "$OPENAI_KEY" ]; then
    sed -i.bak "s#^OPENAI_API_KEY=.*#OPENAI_API_KEY=${OPENAI_KEY}#" .env
  fi
  sed -i.bak "s#^NEXT_PUBLIC_API_URL=.*#NEXT_PUBLIC_API_URL=${API_BASE_URL}#" .env
  rm -f .env.bak
  ok "generated .env with fresh secrets"
  [ -z "$OPENAI_KEY" ] && info "no OpenAI key set — add one later from Settings to enable embeddings/chat"
else
  ok "existing .env found, left untouched"
fi

spinner "Pulling prebuilt images" docker compose pull surrealdb backend
if [ "$API_BASE_URL" = "http://localhost:8001" ]; then
  spinner "Pulling prebuilt images" docker compose pull frontend
else
  spinner "Building frontend (custom API URL)" docker compose build frontend
fi
spinner "Starting the stack" docker compose up -d

echo
printf "  %s%s" "$GREEN$BOLD"
cat <<'EOF'
  ┌─────────────────────────────────────────────┐
  │  Eunomia is up.                              │
EOF
printf "%s\n" "$RESET"
printf "  %s│%s  Frontend  %shttp://localhost:3000%s\n" "$GREEN" "$RESET" "$CYAN" "$RESET"
printf "  %s│%s  Backend   %shttp://localhost:8001/healthz%s\n" "$GREEN" "$RESET" "$CYAN" "$RESET"
printf "  %s└─────────────────────────────────────────────┘%s\n" "$GREEN" "$RESET"
echo
info "status any time with: (cd ${INSTALL_DIR} && docker compose ps)"
echo
