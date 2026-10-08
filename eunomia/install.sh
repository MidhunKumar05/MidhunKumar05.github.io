#!/usr/bin/env bash
# Eunomia installer — clones the latest release, generates secrets, starts the
# stack with Docker Compose (SurrealDB + Rust backend + Next.js frontend),
# with one-click updates built in, and connects your AI agents over MCP.
#
# Usage:
#   curl -fsSL https://midhunkumar05.github.io/eunomia/install.sh | bash
#   curl -fsSL https://midhunkumar05.github.io/eunomia/install.sh | bash -s -- --yes --dir ~/eunomia
#
# Run by an AI agent (non-interactive)? It installs with defaults, creates an
# account + API token, and adds Eunomia's MCP server to *that* agent. Run by a
# person, it adds it to every supported agent (Claude Code, Codex, Hermes,
# Gemini CLI, Cursor, Windsurf, OpenCode, VS Code, Claude Desktop) so each one has it from its first run.
#
# Flags:
#   --dir <path>              install location (default: ./eunomia)
#   --ref <ref>               git ref: a tag, branch, or "latest" (default: latest release)
#   --backend-port <port>     host port for the backend (default: 8001)
#   --frontend-port <port>    host port for the frontend (default: 3000)
#   --domain <name>           serve over HTTPS at this domain with a free Let's Encrypt
#                             certificate (needs DNS pointing here and ports 80/443 open)
#   --acme-email <email>      email for Let's Encrypt (required with --domain)
#   --openai-base-url <url>   OpenAI-compatible endpoint (default: https://api.openai.com/v1)
#   --api-key <key>           API key for that endpoint. Optional: your AI agent can be the
#                             model; a key just saves its tokens (embeddings + answer synthesis)
#   --email <email>           Eunomia account to create (default: your git email)
#   --password <password>     its password (default: generated, saved to .eunomia-credentials)
#   --agents <list>           auto (default) | all | none | claude,codex,hermes,gemini,cursor,windsurf,opencode
#   --agent <name>            say which agent is running this, if it isn't detected automatically
#   --no-agents               same as --agents none
#   --no-install-deps         don't install missing git/Docker/jq; just say what's missing
#   --yes, -y                 skip prompts, accept defaults
#   --no-color                disable ANSI colors/animation

set -euo pipefail

INSTALLER_VERSION="1.7.0"

# Never hang on a credential prompt -- fail fast instead.
export GIT_TERMINAL_PROMPT=0

REPO_URL="${EUNOMIA_REPO_URL:-https://github.com/Qyrhal/Eunomia.git}" # overridable for forks/tests
API_LATEST="https://api.github.com/repos/Qyrhal/Eunomia/releases/latest"
RAW_BASE="${EUNOMIA_RAW_BASE:-https://raw.githubusercontent.com/Qyrhal/Eunomia/main}"
INSTALL_DIR="eunomia"
REF="latest"
ASSUME_YES=0
OPENAI_KEY=""
OPENAI_BASE_URL=""
BACKEND_PORT="8001"
FRONTEND_PORT="3000"
EMAIL="${EUNOMIA_EMAIL:-}"
PASSWORD="${EUNOMIA_PASSWORD:-}"
AGENTS="auto"
AGENT_NAME="${EUNOMIA_AGENT:-}"
INSTALL_DEPS=1
DOMAIN=""
ACME_EMAIL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) INSTALL_DIR="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --api-key) OPENAI_KEY="$2"; shift 2 ;;
    --openai-base-url) OPENAI_BASE_URL="$2"; shift 2 ;;
    --backend-port) BACKEND_PORT="$2"; shift 2 ;;
    --frontend-port) FRONTEND_PORT="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --acme-email) ACME_EMAIL="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    --agents) AGENTS="$2"; shift 2 ;;
    --agent) AGENT_NAME="$2"; shift 2 ;;
    --no-agents) AGENTS="none"; shift ;;
    --no-install-deps) INSTALL_DEPS=0; shift ;;
    --no-auto-update) shift ;; # deprecated: updates only ever apply when you click Update now
    --yes|-y) ASSUME_YES=1; shift ;;
    --no-color) NO_COLOR=1; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" 2>/dev/null | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1 (see --help)" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Terminal plumbing. Piped via `curl | bash`, stdin IS the script, so prompts
# read from the controlling tty when there is one. No tty = unattended (an AI
# agent, CI): take every default, print plain output.
# ---------------------------------------------------------------------------
IS_TTY=0
if [ -t 1 ] && [ -r /dev/tty ]; then
  IS_TTY=1
  exec 3</dev/tty
fi
INTERACTIVE=0
[ "$IS_TTY" -eq 1 ] && [ "$ASSUME_YES" -eq 0 ] && INTERACTIVE=1

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
note()  { printf "    %s%s%s\n" "$GREY" "$1" "$RESET"; }

TOTAL_STEPS=4
step() { printf "\n  %s%s[%s/%s]%s %s%s%s\n\n" "$GREEN" "$BOLD" "$1" "$TOTAL_STEPS" "$RESET" "$BOLD" "$2" "$RESET"; }

trap 'printf "\n  %s!%s interrupted — nothing is half-installed that re-running this script can'"'"'t resume.\n" "$YELLOW" "$RESET"; exit 130' INT

# Runs "$@" with a spinner, dumps its output on failure. Plain lines on a non-tty.
spinner() {
  local label="$1"; shift
  local log; log="$(mktemp)"
  if [ "$IS_TTY" -eq 0 ]; then
    info "$label"
    if "$@" >"$log" 2>&1; then ok "$label"; rm -f "$log"; return 0
    else printf "  ✗ %s failed:\n" "$label" >&2; cat "$log" >&2; rm -f "$log"; exit 1; fi
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

# ask <var> <question> <default> [help line] — Enter keeps the default.
ask() {
  local __var="$1" __q="$2" __default="$3" __help="${4:-}" __ans
  if [ "$INTERACTIVE" -eq 0 ]; then printf -v "$__var" '%s' "$__default"; return; fi
  [ -z "$__help" ] || note "$__help"
  printf "  %s?%s %s %s[%s]%s " "$CYAN" "$RESET" "$__q" "$GREY" "$__default" "$RESET"
  read -r __ans <&3 || __ans=""
  printf -v "$__var" '%s' "${__ans:-$__default}"
}

# ask_secret <var> <question> [help line] — typed input is hidden; Enter = empty.
ask_secret() {
  local __var="$1" __q="$2" __help="${3:-}" __ans=""
  if [ "$INTERACTIVE" -eq 0 ]; then return; fi
  [ -z "$__help" ] || note "$__help"
  printf "  %s?%s %s %s(hidden, Enter to skip)%s " "$CYAN" "$RESET" "$__q" "$GREY" "$RESET"
  read -rs __ans <&3 || __ans=""
  echo
  printf -v "$__var" '%s' "$__ans"
}

# yes_no <question> <Y|N default> [help] -> exit 0 for yes
yes_no() {
  local __ans __d="$2" __hint="Y/n"
  [ "$__d" = "N" ] && __hint="y/N"
  if [ "$INTERACTIVE" -eq 0 ]; then [ "$__d" = "Y" ]; return; fi
  [ -z "${3:-}" ] || note "$3"
  printf "  %s?%s %s %s[%s]%s " "$CYAN" "$RESET" "$1" "$GREY" "$__hint" "$RESET"
  read -r __ans <&3 || __ans=""
  case "${__ans:-$__d}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# --domain/--acme-email end up in .env and a Caddyfile, so only plain DNS
# names and addresses get through (same rules as the updater and backend):
# labels of letters/digits/hyphens ending in an alphabetic TLD -- no IPs.
valid_domain() {
  local label='[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
  [ "${#1}" -le 253 ] && [[ "$1" =~ ^($label\.)+[A-Za-z]{2,63}$ ]]
}
valid_email() {
  [ "${#1}" -le 254 ] && [[ "$1" =~ ^[A-Za-z0-9._%+-]{1,64}@(.+)$ ]] && valid_domain "${BASH_REMATCH[1]}"
}
check_https_args() {
  [ -n "$DOMAIN" ] || return 0
  DOMAIN="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')"
  valid_domain "$DOMAIN" || fail "--domain: '$DOMAIN' isn't a domain name like eunomia.example.com (no http://, port or IP)"
  [ -n "$ACME_EMAIL" ] || fail "--domain needs --acme-email <email> (Let's Encrypt's contact for certificate notices)"
  valid_email "$ACME_EMAIL" || fail "--acme-email: '$ACME_EMAIL' isn't a valid email address"
}
check_https_args

# ---------------------------------------------------------------------------
banner() {
  printf '\n%s' "$GREEN$BOLD"
  cat <<'EOF'
  ███████╗██╗   ██╗███╗   ██╗ ██████╗ ███╗   ███╗██╗ █████╗
  ██╔════╝██║   ██║████╗  ██║██╔═══██╗████╗ ████║██║██╔══██╗
  █████╗  ██║   ██║██╔██╗ ██║██║   ██║██╔████╔██║██║███████║
  ██╔══╝  ██║   ██║██║╚██╗██║██║   ██║██║╚██╔╝██║██║██╔══██║
  ███████╗╚██████╔╝██║ ╚████║╚██████╔╝██║ ╚═╝ ██║██║██║  ██║
  ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═╝
EOF
  printf '%s' "$RESET"
  printf "  %sa memory you can query%s %s(installer v%s)%s\n" "$GREY" "$RESET" "$GREY" "$INSTALLER_VERSION" "$RESET"
}
banner

# ---------------------------------------------------------------------------
step 1 "Checking your machine"
# ---------------------------------------------------------------------------
# Missing tools are installed with the system package manager (Homebrew on
# macOS; apt/dnf/yum/pacman/zypper/apk on Linux). Docker on macOS comes from
# Colima -- headless, no GUI or licence prompt, so an agent can do it too.
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if [ "$INTERACTIVE" -eq 1 ]; then SUDO="sudo"; else SUDO="sudo -n"; fi # never hang on a password prompt unattended
fi
OS="$(uname -s)"

pkg_install() { # pkg_install <package...>
  if [ "$OS" = Darwin ]; then
    if ! command -v brew >/dev/null 2>&1; then
      info "installing Homebrew (needed to install $*)"
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null || return 1
      for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)"; done
    fi
    brew install "$@"
  elif command -v apt-get >/dev/null 2>&1; then $SUDO apt-get update -qq && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
  elif command -v dnf >/dev/null 2>&1; then $SUDO dnf install -y -q "$@"
  elif command -v yum >/dev/null 2>&1; then $SUDO yum install -y -q "$@"
  elif command -v pacman >/dev/null 2>&1; then $SUDO pacman -Sy --noconfirm --needed "$@"
  elif command -v zypper >/dev/null 2>&1; then $SUDO zypper -n install "$@"
  elif command -v apk >/dev/null 2>&1; then $SUDO apk add --no-cache "$@"
  else return 1; fi
}

install_docker() {
  if [ "$OS" = Darwin ]; then
    pkg_install colima docker docker-compose || return 1
    mkdir -p "$HOME/.docker/cli-plugins"
    ln -sfn "$(brew --prefix)/opt/docker-compose/bin/docker-compose" "$HOME/.docker/cli-plugins/docker-compose"
  elif command -v apk >/dev/null 2>&1; then pkg_install docker docker-cli-compose
  elif command -v pacman >/dev/null 2>&1; then pkg_install docker docker-compose
  else
    curl -fsSL https://get.docker.com | $SUDO sh || return 1 # Docker's official script (Debian/Ubuntu/Fedora/RHEL/…)
  fi
}

start_docker() {
  if [ "$OS" = Darwin ]; then
    if [ -d /Applications/OrbStack.app ]; then open -a OrbStack
    elif [ -d /Applications/Docker.app ]; then open -a Docker
    elif command -v colima >/dev/null 2>&1; then colima start >/dev/null 2>&1 || return 1
    else return 1; fi
  else
    { command -v systemctl >/dev/null 2>&1 && $SUDO systemctl enable --now docker >/dev/null 2>&1; } \
      || { command -v service >/dev/null 2>&1 && $SUDO service docker start >/dev/null 2>&1; } \
      || ($SUDO dockerd >/tmp/eunomia-dockerd.log 2>&1 &) # no init system (containers, WSL)
  fi
  for _ in $(seq 1 90); do docker info >/dev/null 2>&1 && return 0; sleep 2; done
  return 1
}

need=""
for bin in git curl openssl; do command -v "$bin" >/dev/null 2>&1 || need="$need $bin"; done
command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 || need="$need docker"
# connecting agents edits their JSON configs: jq or python3
command -v jq >/dev/null 2>&1 || python3 -c 'import json' >/dev/null 2>&1 || need="$need jq"
need="${need# }"

if [ -n "$need" ]; then
  if [ "$INSTALL_DEPS" -eq 0 ]; then
    fail "missing: $need. Install them (Docker: https://docs.docker.com/get-docker/), or re-run without --no-install-deps."
  fi
  yes_no "Install what's missing ($need)?" Y "Uses your package manager$([ -n "$SUDO" ] && echo " and sudo")." \
    || fail "can't continue without: $need"
  for dep in $need; do
    if [ "$dep" = docker ]; then
      spinner "Installing Docker" install_docker \
        || fail "couldn't install Docker — install it from https://docs.docker.com/get-docker/ and re-run"
    else
      spinner "Installing $dep" pkg_install "$dep" || fail "couldn't install $dep — install it and re-run"
    fi
  done
fi

# Linux right after installing Docker: this shell isn't in the docker group
# yet, so talk to the daemon through sudo for the rest of the run.
if ! docker info >/dev/null 2>&1 && [ -n "$SUDO" ] && $SUDO docker info >/dev/null 2>&1; then
  docker() { $SUDO docker "$@"; }
  [ "$OS" = Darwin ] || $SUDO usermod -aG docker "$(id -un)" >/dev/null 2>&1 || true
fi
if ! docker info >/dev/null 2>&1; then
  if [ "$INSTALL_DEPS" -eq 1 ]; then
    spinner "Starting Docker" start_docker || fail "Docker is installed but won't start — start it (Docker Desktop, OrbStack, or 'colima start') and re-run."
  else
    fail "Docker is installed but not running — start it and re-run."
  fi
fi
ok "git, docker (running, with compose), curl, openssl$(command -v jq >/dev/null 2>&1 && echo ", jq")"
[ -z "${EUNOMIA_DEPS_ONLY:-}" ] || exit 0 # test hook: stop after the dependency step

# Best-effort LAN IP, only to print the address other devices can open.
detect_lan_ip() {
  if command -v ipconfig >/dev/null 2>&1; then
    for iface in en0 en1; do
      ipconfig getifaddr "$iface" 2>/dev/null && return 0
    done
  fi
  if command -v ip >/dev/null 2>&1; then
    ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1
    return 0
  fi
  if command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1}'
  fi
}
LAN_IP="$(detect_lan_ip || true)"

if [ "$REF" = "latest" ]; then
  REF="$(curl -fsSL --max-time 8 "$API_LATEST" 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/' || true)"
  if [ -z "$REF" ]; then
    warn "no release found yet — using main"
    REF="main"
  else
    ok "latest release: ${BOLD}${REF}${RESET}"
  fi
fi

# ---------------------------------------------------------------------------
step 2 "Choosing your setup"
# ---------------------------------------------------------------------------
if [ "$INTERACTIVE" -eq 1 ]; then
  note "Press Enter to accept the value in [brackets]."
  echo
elif [ "$IS_TTY" -eq 0 ]; then
  info "no terminal — running unattended with defaults (flags override them)"
fi

ask INSTALL_DIR "Install into which folder?" "$INSTALL_DIR" "Relative to $PWD"
ask FRONTEND_PORT "Web app port?" "$FRONTEND_PORT" "Where you'll open Eunomia in your browser."
ask BACKEND_PORT "API port?" "$BACKEND_PORT" "Used by agents (the MCP server lives here) and the web app."

# OpenAI is optional and URL-first: the endpoint decides whether a key is needed at all.
if [ -z "$OPENAI_BASE_URL" ] || [ -z "$OPENAI_KEY" ]; then
  if [ "$INTERACTIVE" -eq 1 ]; then
    echo
    info "${BOLD}Optional: OpenAI-compatible model${RESET}"
    note "Not required — AI agents you connect (Claude, Codex, …) recall and write memory with their own model."
    note "Recommended: it saves their tokens, because Eunomia then does embeddings and answer synthesis itself."
  fi
  [ -n "$OPENAI_BASE_URL" ] || ask OPENAI_BASE_URL "API base URL?" "https://api.openai.com/v1" "Any OpenAI-compatible endpoint works — a local server or proxy too."
  [ -n "$OPENAI_KEY" ] || ask_secret OPENAI_KEY "API key?" "Leave empty to skip; add one later in Settings."
fi
OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://api.openai.com/v1}"

GIT_EMAIL="$(git config --get user.email 2>/dev/null || true)"
if [ "$AGENTS" != "none" ]; then
  if [ "$INTERACTIVE" -eq 1 ]; then
    echo
    info "${BOLD}Connect your AI agents${RESET}"
    note "Creates your Eunomia account and a separate API token per agent, and adds Eunomia's MCP server to"
    note "Claude Code, Codex, Hermes, Gemini CLI, Cursor, Windsurf, OpenCode, VS Code and Claude Desktop — even ones you haven't run yet."
    if yes_no "Connect them?" Y; then
      ask EMAIL "Email for your Eunomia account?" "${EMAIL:-${GIT_EMAIL:-me@eunomia.local}}" "You'll sign in to the web app with this."
      if [ -z "$PASSWORD" ]; then
        ask_secret PASSWORD "Password (8+ characters)?" "Leave empty to generate one (saved to .eunomia-credentials)."
      fi
    else
      AGENTS="none"
    fi
  fi
fi
EMAIL="${EMAIL:-${GIT_EMAIL:-me@eunomia.local}}"

if [ "$INTERACTIVE" -eq 1 ] && [ -z "$DOMAIN" ]; then
  echo
  if yes_no "Serve over HTTPS with a free Let's Encrypt certificate?" N \
    "Needs a domain pointing at this machine and ports 80/443 open. You can also turn it on later in Settings → HTTPS."; then
    ask DOMAIN "Domain?" "eunomia.example.com" "The name your DNS points at this machine, without http://."
    ask ACME_EMAIL "Email for Let's Encrypt?" "$EMAIL" "Only used for certificate expiry notices."
    check_https_args
  fi
fi

if [ "$INTERACTIVE" -eq 1 ]; then
  echo
  printf "  %sReady to install%s\n" "$BOLD" "$RESET"
  printf "    folder         %s\n" "$INSTALL_DIR"
  printf "    release        %s\n" "$REF"
  printf "    web app / API  :%s / :%s\n" "$FRONTEND_PORT" "$BACKEND_PORT"
  printf "    HTTPS          %s\n" "$([ -n "$DOMAIN" ] && echo "https://$DOMAIN (Let's Encrypt, $ACME_EMAIL)" || echo "off — turn on later in Settings → HTTPS")"
  printf "    model          %s (%s)\n" "$OPENAI_BASE_URL" "$([ -n "$OPENAI_KEY" ] && echo "key set" || echo "no key — agents are the model")"
  printf "    updates        one-click, from Settings → Updates\n"
  printf "    AI agents      %s\n" "$([ "$AGENTS" = "none" ] && echo "not connected" || echo "connect ($AGENTS) as $EMAIL")"
  echo
  yes_no "Go?" Y || { info "cancelled — nothing was changed"; exit 0; }
fi

port_in_use() { (exec 4<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
# Only on a fresh install -- re-running over an existing one finds its own
# containers already on these ports.
if [ ! -d "$INSTALL_DIR/.git" ]; then
  for p in "$FRONTEND_PORT" "$BACKEND_PORT"; do
    port_in_use "$p" && fail "port $p is already in use — stop whatever is on it, or pick another with --frontend-port/--backend-port"
  done
fi
# HTTPS needs 80 (Let's Encrypt's check) and 443 -- unless this install's own
# caddy already holds them.
if [ -n "$DOMAIN" ] && ! grep -qx 'COMPOSE_PROFILES=https' "$INSTALL_DIR/.env" 2>/dev/null; then
  for p in 80 443; do
    port_in_use "$p" && fail "port $p is already in use — HTTPS needs ports 80 and 443 free (stop the web server on it, or install without --domain)"
  done
fi

# ---------------------------------------------------------------------------
step 3 "Installing"
# ---------------------------------------------------------------------------
if [ -d "$INSTALL_DIR/.git" ]; then
  # A tag fetched by name lands only in FETCH_HEAD, so ask for the tag ref itself
  # (falling back to a branch); then check out what was fetched.
  spinner "Updating existing checkout" bash -c "cd '$INSTALL_DIR' && { git fetch --depth 1 --force origin 'refs/tags/$REF:refs/tags/$REF' 2>/dev/null || git fetch --depth 1 origin '$REF'; } && git checkout --quiet '$REF' 2>/dev/null || git checkout --quiet FETCH_HEAD"
else
  spinner "Cloning Eunomia (${REF})" bash -c "git clone --depth 1 --branch '$REF' '$REPO_URL' '$INSTALL_DIR' 2>/dev/null || git clone '$REPO_URL' '$INSTALL_DIR'; git -C '$INSTALL_DIR' checkout '$REF' 2>/dev/null || true"
fi

cd "$INSTALL_DIR"
INSTALL_PATH="$PWD"

if [ ! -f .env ]; then
  cp .env.example .env
  sed -i.bak "s#^JWT_SECRET=.*#JWT_SECRET=$(openssl rand -base64 32)#" .env
  sed -i.bak "s#^ENCRYPTION_KEY=.*#ENCRYPTION_KEY=$(openssl rand -base64 32)#" .env
  sed -i.bak "s#^SURREAL_PASS=.*#SURREAL_PASS=$(openssl rand -hex 24)#" .env
  sed -i.bak "s#^OPENAI_BASE_URL=.*#OPENAI_BASE_URL=${OPENAI_BASE_URL}#" .env
  [ -z "$OPENAI_KEY" ] || sed -i.bak "s#^OPENAI_API_KEY=.*#OPENAI_API_KEY=${OPENAI_KEY}#" .env
  sed -i.bak "s#^BACKEND_PORT=.*#BACKEND_PORT=${BACKEND_PORT}#" .env
  sed -i.bak "s#^FRONTEND_PORT=.*#FRONTEND_PORT=${FRONTEND_PORT}#" .env
  rm -f .env.bak
  ok "generated .env with fresh secrets"
else
  ok "existing .env found — secrets left untouched"
  # Eunomia v1.3+ refuses to start without an ENCRYPTION_KEY of 16+ characters
  # (older versions silently used a known fallback). Give older installs one.
  key="$(sed -n 's/^ENCRYPTION_KEY=//p' .env | tail -1)"
  if [ "${#key}" -lt 16 ]; then
    if grep -q '^ENCRYPTION_KEY=' .env; then
      sed -i.bak "s#^ENCRYPTION_KEY=.*#ENCRYPTION_KEY=$(openssl rand -base64 32)#" .env && rm -f .env.bak
    else
      echo "ENCRYPTION_KEY=$(openssl rand -base64 32)" >> .env
    fi
    warn "no encryption key was set — generated one. Re-enter saved connector credentials and API keys in the app."
  fi
  FRONTEND_PORT="$(sed -n 's/^FRONTEND_PORT=//p' .env | tail -1)"; FRONTEND_PORT="${FRONTEND_PORT:-3000}"
  BACKEND_PORT="$(sed -n 's/^BACKEND_PORT=//p' .env | tail -1)"; BACKEND_PORT="${BACKEND_PORT:-8001}"
fi

# Pin the prebuilt images to the checked-out release (saved in .env so later
# `docker compose` runs and the updater agree). Only release tags (v1.2.3)
# get images of that name -- branches use "latest".
IMAGE_TAG="latest"
case "$REF" in v[0-9]*) IMAGE_TAG="$REF" ;; esac
if grep -q '^EUNOMIA_IMAGE_TAG=' .env; then
  sed -i.bak "s#^EUNOMIA_IMAGE_TAG=.*#EUNOMIA_IMAGE_TAG=${IMAGE_TAG}#" .env && rm -f .env.bak
else
  echo "EUNOMIA_IMAGE_TAG=${IMAGE_TAG}" >> .env
fi

# HTTPS: the `caddy` service (compose profile "https") gets the certificate.
# Values were validated by check_https_args, so they're safe in sed.
if [ -n "$DOMAIN" ]; then
  if grep -q '^  caddy:' docker-compose.yml 2>/dev/null; then
    for kv in "EUNOMIA_DOMAIN=$DOMAIN" "EUNOMIA_ACME_EMAIL=$ACME_EMAIL" "COMPOSE_PROFILES=https"; do
      if grep -q "^${kv%%=*}=" .env; then sed -i.bak "s#^${kv%%=*}=.*#${kv}#" .env && rm -f .env.bak
      else echo "$kv" >> .env; fi
    done
    ok "HTTPS on for ${DOMAIN}"
  else
    warn "${REF} predates built-in HTTPS — installing without it (re-run with a newer release)"
    DOMAIN=""
  fi
elif grep -qx 'COMPOSE_PROFILES=https' .env; then
  DOMAIN="$(sed -n 's/^EUNOMIA_DOMAIN=//p' .env | tail -1)" # re-run of an HTTPS install: keep it
fi

# Created here so Docker doesn't create it root-owned for the bind mount,
# which the host-side updater then couldn't write to.
mkdir -p update-status

spinner "Pulling prebuilt images" docker compose pull
spinner "Starting the stack" docker compose up -d
spinner "Waiting for Eunomia to come up" bash -c "for i in \$(seq 1 90); do curl -sf -o /dev/null http://localhost:${BACKEND_PORT}/healthz && curl -sf -o /dev/null http://localhost:${FRONTEND_PORT}/login && exit 0; sleep 1; done; exit 1"

# Not fatal: DNS or a firewall may just not be ready yet, and Caddy keeps
# retrying the certificate on its own.
HTTPS_OK=0
if [ -n "$DOMAIN" ]; then
  info "waiting for https://${DOMAIN} (Let's Encrypt usually takes under a minute)"
  for _ in $(seq 1 45); do
    curl -sf -o /dev/null --max-time 5 "https://${DOMAIN}/login" && { HTTPS_OK=1; break; }
    sleep 2
  done
  if [ "$HTTPS_OK" -eq 1 ]; then ok "https://${DOMAIN} is up with a Let's Encrypt certificate"
  else
    warn "https://${DOMAIN} isn't answering yet. Check that ${DOMAIN}'s DNS points at this machine and ports 80/443"
    warn "are reachable from the internet; Caddy keeps retrying. Status: Settings → HTTPS, logs: docker compose logs caddy"
  fi
fi

# ---------------------------------------------------------------------------
step 4 "Connecting"
# ---------------------------------------------------------------------------

# One-click updates: the stack's own `updater` service applies them when you
# click "Update now" in Settings -- nothing to schedule on this machine.
if grep -q '^  updater:' docker-compose.yml 2>/dev/null; then
  # not fatal: Settings explains what to check if the updater never reports in
  for _ in $(seq 1 60); do [ -f update-status/status.json ] && break; sleep 1; done
  if [ -f update-status/status.json ]; then ok "one-click updates ready (Settings → Updates)"
  else warn "the updater hasn't reported yet — see Settings → Updates in a minute (docker compose logs updater)"; fi
else
  warn "${REF} predates one-click updates — re-run this installer once a newer release is out"
fi

# AI agents: account + one API token per agent + MCP entry in each agent's config.
# Agents use the HTTPS address once it answers (it works from anywhere);
# until then, the local API port.
AGENT_URL="http://localhost:${BACKEND_PORT}"
[ "$HTTPS_OK" -eq 0 ] || AGENT_URL="https://${DOMAIN}"
CREDS_FILE=".eunomia-credentials"
GENERATED_PASSWORD=0
CONNECTED=0
connect_agents() {
  local script="scripts/connect-agents.sh" tmp=""
  if [ ! -f "$script" ]; then
    tmp="$(mktemp)"; script="$tmp"
    curl -fsSL --max-time 15 "$RAW_BASE/scripts/connect-agents.sh" -o "$script" || { rm -f "$tmp"; warn "couldn't fetch the agent connector"; return 1; }
  fi
  # A previous run's generated login lets re-runs reconnect without asking.
  if [ -z "$PASSWORD" ] && [ -f "$CREDS_FILE" ]; then
    EMAIL="$(sed -n 's/^EMAIL=//p' "$CREDS_FILE" | tail -1)"
    PASSWORD="$(sed -n 's/^PASSWORD=//p' "$CREDS_FILE" | tail -1)"
  fi
  if [ -z "$PASSWORD" ]; then
    PASSWORD="$(openssl rand -hex 12)"; GENERATED_PASSWORD=1
  fi
  local rc=0
  EUNOMIA_PASSWORD="$PASSWORD" bash "$script" --url "$AGENT_URL" --email "$EMAIL" \
    --agents "$AGENTS" ${AGENT_NAME:+--agent "$AGENT_NAME"} || rc=$?
  [ -z "$tmp" ] || rm -f "$tmp"
  if [ "$rc" -eq 0 ] && [ "$GENERATED_PASSWORD" -eq 1 ]; then
    (umask 077; printf 'EMAIL=%s\nPASSWORD=%s\n' "$EMAIL" "$PASSWORD" > "$CREDS_FILE")
  fi
  return "$rc"
}

if [ "$AGENTS" = "none" ]; then
  info "AI agents not connected — add Eunomia's MCP server later from the dashboard, or re-run with --agents all"
elif connect_agents; then
  CONNECTED=1
else
  warn "some agents weren't connected. If the account already exists, re-run with --email and --password."
  warn "Or create a token in Settings → API tokens and run: ./scripts/connect-agents.sh --token <token>"
fi

# ---------------------------------------------------------------------------
echo
printf "  %s%sEunomia is up.%s\n\n" "$GREEN" "$BOLD" "$RESET"
[ -z "$DOMAIN" ] || printf "  Open it          %shttps://%s%s%s\n" "$CYAN" "$DOMAIN" "$RESET" "$([ "$HTTPS_OK" -eq 1 ] || echo " (once the certificate is issued)")"
printf "  Open it          %shttp://localhost:%s%s\n" "$CYAN" "$FRONTEND_PORT" "$RESET"
[ -z "$LAN_IP" ] || printf "  Other devices    %shttp://%s:%s%s\n" "$CYAN" "$LAN_IP" "$FRONTEND_PORT" "$RESET"
printf "  MCP server       %s%s/mcp%s\n" "$CYAN" "$AGENT_URL" "$RESET"
if [ "$CONNECTED" -eq 1 ]; then
  printf "  Sign in with     %s" "$EMAIL"
  if [ "$GENERATED_PASSWORD" -eq 1 ]; then printf "  /  %s  %s(saved in %s/%s)%s" "$PASSWORD" "$GREY" "$INSTALL_PATH" "$CREDS_FILE" "$RESET"
  elif [ -f "$CREDS_FILE" ]; then printf "  %s(password in %s/%s)%s" "$GREY" "$INSTALL_PATH" "$CREDS_FILE" "$RESET"; fi
  echo
else
  printf "  First visit      create your account at the web app\n"
fi
echo
if [ "$CONNECTED" -eq 1 ]; then
  info "restart your AI agent(s) to load Eunomia's tools (Claude Code: exit, then claude --continue)"
fi
if [ -z "$OPENAI_KEY" ]; then
  info "no model key set: your agents do the thinking. To save their tokens, add one in Settings → OpenAI"
fi
info "status:  (cd ${INSTALL_DIR} && docker compose ps)    logs:  docker compose logs -f"
echo
