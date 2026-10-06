#!/usr/bin/env bash
# Eunomia installer — clones the repo, generates secrets, and brings the
# stack up with Docker Compose (SurrealDB + Rust backend + Next.js frontend).
#
# Usage:
#   curl -fsSL https://midhunkumar05.github.io/eunomia/install.sh | bash
#   curl -fsSL https://midhunkumar05.github.io/eunomia/install.sh | bash -s -- --dir ~/eunomia --ref v1.1.3
#
# Flags:
#   --dir <path>   install location (default: ./eunomia)
#   --ref <ref>    git ref to check out: a tag, branch, or "latest" (default: latest release)

set -euo pipefail

REPO_URL="https://github.com/Qyrhal/Eunomia.git"
API_LATEST="https://api.github.com/repos/Qyrhal/Eunomia/releases/latest"
INSTALL_DIR="eunomia"
REF="latest"

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) INSTALL_DIR="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

for bin in git docker; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: $bin is required but not installed." >&2
    exit 1
  fi
done

if ! docker compose version >/dev/null 2>&1; then
  echo "error: 'docker compose' (the plugin, not docker-compose) is required." >&2
  exit 1
fi

if [ "$REF" = "latest" ]; then
  echo "Looking up the latest release..."
  REF="$(curl -fsSL "$API_LATEST" 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/')"
  if [ -z "$REF" ]; then
    echo "Couldn't find a release yet, falling back to main."
    REF="main"
  fi
fi

echo "Installing Eunomia (${REF}) into ./${INSTALL_DIR} ..."

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "Found an existing checkout, fetching..."
  git -C "$INSTALL_DIR" fetch --depth 1 origin "$REF"
  git -C "$INSTALL_DIR" checkout "$REF"
else
  git clone --depth 1 --branch "$REF" "$REPO_URL" "$INSTALL_DIR" 2>/dev/null \
    || git clone "$REPO_URL" "$INSTALL_DIR"
  git -C "$INSTALL_DIR" checkout "$REF" 2>/dev/null || true
fi

cd "$INSTALL_DIR"

if [ ! -f .env ]; then
  echo "Generating .env with fresh secrets..."
  cp .env.example .env
  JWT_SECRET="$(openssl rand -base64 32)"
  ENCRYPTION_KEY="$(openssl rand -base64 32)"
  # portable in-place sed (no -i difference between GNU/BSD when a backup suffix is given)
  sed -i.bak "s#^JWT_SECRET=.*#JWT_SECRET=${JWT_SECRET}#" .env
  sed -i.bak "s#^ENCRYPTION_KEY=.*#ENCRYPTION_KEY=${ENCRYPTION_KEY}#" .env
  rm -f .env.bak
  echo "Note: set OPENAI_API_KEY in .env (or add it later from Settings) to enable embeddings/chat."
else
  echo "Found an existing .env, leaving it as-is."
fi

echo "Building and starting the stack (this can take a few minutes the first time)..."
docker compose up -d --build

echo
echo "Eunomia is starting up."
echo "  Frontend: http://localhost:3000"
echo "  Backend:  http://localhost:8001/healthz"
echo
echo "Check status any time with: (cd ${INSTALL_DIR} && docker compose ps)"
