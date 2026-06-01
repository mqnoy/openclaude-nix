#!/usr/bin/env bash
#
# update.sh — Automatically update openclaude to the latest (or specified) npm version.
#
# Usage:
#   ./update.sh              # update to latest version on npm
#   ./update.sh 0.16.1       # update to a specific version
#   ./update.sh --check      # just print latest version without updating
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
NIX_FILE="$REPO_DIR/openclaude.nix"
LOCK_DIR="$REPO_DIR/packages/openclaude"
NPM_PACKAGE="@gitlawb/openclaude"
NPM_REGISTRY="https://registry.npmjs.org"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*" >&2; }
step()  { echo -e "\n${BOLD}▶ $*${NC}"; }

# ── Dependency check ─────────────────────────────────────────────────────────
for cmd in curl nix-prefetch-url nix-build nix sed; do
  if ! command -v "$cmd" &>/dev/null; then
    err "Required command '$cmd' not found in PATH"
    exit 1
  fi
done

# ── Get current version from openclaude.nix ──────────────────────────────────
get_current_version() {
  sed -n 's/^  version = "\([^"]*\)".*/\1/p' "$NIX_FILE"
}

# ── Get latest version from npm ──────────────────────────────────────────────
get_latest_version() {
  curl -sf "$NPM_REGISTRY/$NPM_PACKAGE" \
    | sed -n 's/.*"latest":"\([^"]*\)".*/\1/p'
}

# ── Main ─────────────────────────────────────────────────────────────────────
CURRENT_VERSION="$(get_current_version)"
info "Current version: ${BOLD}$CURRENT_VERSION${NC}"

# Handle --check flag
if [[ "${1:-}" == "--check" ]]; then
  LATEST="$(get_latest_version)"
  info "Latest version on npm: ${BOLD}$LATEST${NC}"
  if [[ "$CURRENT_VERSION" == "$LATEST" ]]; then
    ok "Already up to date."
  else
    warn "Update available: $CURRENT_VERSION → $LATEST"
  fi
  exit 0
fi

# Determine target version
if [[ -n "${1:-}" ]]; then
  TARGET_VERSION="$1"
  info "Target version (manual): ${BOLD}$TARGET_VERSION${NC}"
else
  TARGET_VERSION="$(get_latest_version)"
  info "Latest version on npm:   ${BOLD}$TARGET_VERSION${NC}"
fi

if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]]; then
  ok "Already at version $TARGET_VERSION. Nothing to do."
  exit 0
fi

info "Updating: ${BOLD}$CURRENT_VERSION${NC} → ${BOLD}$TARGET_VERSION${NC}"

TARBALL_URL="$NPM_REGISTRY/$NPM_PACKAGE/-/openclaude-$TARGET_VERSION.tgz"

# ── Step 1: Verify the tarball exists ────────────────────────────────────────
step "Verifying tarball exists on npm"
HTTP_CODE=$(curl -sfL -o /dev/null -w "%{http_code}" "$TARBALL_URL")
if [[ "$HTTP_CODE" != "200" ]]; then
  err "Tarball not found at $TARBALL_URL (HTTP $HTTP_CODE)"
  err "Is version '$TARGET_VERSION' published to npm?"
  exit 1
fi
ok "Tarball exists (HTTP $HTTP_CODE)"

# ── Step 2: Generate package-lock.json ───────────────────────────────────────
step "Generating vendored package-lock.json"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

curl -sL "$TARBALL_URL" -o "$TEMP_DIR/openclaude.tgz"
mkdir -p "$TEMP_DIR/extract"
tar -xzf "$TEMP_DIR/openclaude.tgz" -C "$TEMP_DIR/extract"

pushd "$TEMP_DIR/extract/package" > /dev/null
npm install --package-lock-only --ignore-scripts 2>&1 | tail -5
popd > /dev/null

mkdir -p "$LOCK_DIR"
cp "$TEMP_DIR/extract/package/package-lock.json" "$LOCK_DIR/package-lock.json"
ok "package-lock.json updated at $LOCK_DIR/package-lock.json"

# ── Step 3: Compute source tarball hash ──────────────────────────────────────
step "Computing source tarball SRI hash"
HASH_BASE32="$(nix-prefetch-url --type sha256 "$TARBALL_URL" 2>/dev/null)"
SRC_HASH="$(nix hash convert --hash-algo sha256 --to sri "$HASH_BASE32")"
ok "Source hash: $SRC_HASH"

# ── Step 4: Update version + source hash in openclaude.nix ──────────────────
step "Updating openclaude.nix (version + source hash)"
sed -i "s|version = \"$CURRENT_VERSION\"|version = \"$TARGET_VERSION\"|" "$NIX_FILE"
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$SRC_HASH\"|" "$NIX_FILE"

# Temporarily blank the npmDepsHash so nix-build reports the correct one
sed -i 's|npmDepsHash = "sha256-[^"]*"|npmDepsHash = ""|' "$NIX_FILE"
ok "Version and source hash updated, npmDepsHash blanked for discovery"

# ── Step 5: Discover correct npmDepsHash ─────────────────────────────────────
step "Discovering npmDepsHash (this will download all npm deps)"
DEPS_HASH=""
BUILD_OUTPUT="$(nix-build "$REPO_DIR" 2>&1 || true)"
DEPS_HASH="$(echo "$BUILD_OUTPUT" | sed -n 's/.*got: *\(sha256-[^ ]*\)/\1/p' | head -1)"

if [[ -z "$DEPS_HASH" ]]; then
  err "Failed to extract npmDepsHash from nix-build output."
  err "Build output:"
  echo "$BUILD_OUTPUT" | tail -20
  # Restore the original version so we don't leave a broken state
  sed -i "s|version = \"$TARGET_VERSION\"|version = \"$CURRENT_VERSION\"|" "$NIX_FILE"
  exit 1
fi
ok "npmDepsHash: $DEPS_HASH"

# ── Step 6: Set the real npmDepsHash ─────────────────────────────────────────
step "Setting npmDepsHash in openclaude.nix"
sed -i "s|npmDepsHash = \"\"|npmDepsHash = \"$DEPS_HASH\"|" "$NIX_FILE"
ok "npmDepsHash set"

# ── Step 7: Final verification build ────────────────────────────────────────
step "Running final verification build"
if RESULT="$(nix-build "$REPO_DIR" 2>&1)"; then
  STORE_PATH="$(echo "$RESULT" | tail -1)"
  ok "Build successful!"
  ok "Store path: $STORE_PATH"
  echo ""
  echo -e "${GREEN}${BOLD}✓ Updated openclaude: $CURRENT_VERSION → $TARGET_VERSION${NC}"
  echo ""
  echo "  Files changed:"
  echo "    • openclaude.nix  (version, hash, npmDepsHash)"
  echo "    • packages/openclaude/package-lock.json"
  echo ""
  echo "  Don't forget to commit:"
  echo "    git add openclaude.nix packages/openclaude/package-lock.json"
  echo "    git commit -m \"openclaude: $CURRENT_VERSION → $TARGET_VERSION\""
else
  err "Verification build failed!"
  echo "$RESULT" | tail -20
  exit 1
fi
