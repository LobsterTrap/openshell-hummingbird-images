#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0

# verify-images.sh — Smoke tests for built container images
#
# Verifies that each image starts correctly and key tools are functional.
# Intended to run in CI after image builds or locally for validation.
#
# Usage:
#   ./scripts/verify-images.sh [REGISTRY_PREFIX] [TAG]
#
# Examples:
#   ./scripts/verify-images.sh ghcr.io/lobstertrap/openshell-hummingbird-images latest
#   ./scripts/verify-images.sh localhost:5000 dev

set -euo pipefail

REGISTRY="${1:-ghcr.io/lobstertrap/openshell-hummingbird-images}"
TAG="${2:-latest}"
FAILURES=0

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; FAILURES=$((FAILURES + 1)); }

run_test() {
    local image="$1"
    local description="$2"
    shift 2
    if podman run --rm "$image" "$@" > /dev/null 2>&1; then
        pass "$description"
    else
        fail "$description"
    fi
}

# ---------------------------------------------------------------------------
# Core infrastructure
# ---------------------------------------------------------------------------
echo ""
echo "=== Core: gateway ==="
GATEWAY="${REGISTRY}/gateway:${TAG}"
if podman pull "$GATEWAY" > /dev/null 2>&1; then
    run_test "$GATEWAY" "gateway --version" --version
else
    fail "Could not pull $GATEWAY"
fi

echo ""
echo "=== Core: supervisor ==="
SUPERVISOR="${REGISTRY}/supervisor:${TAG}"
if podman pull "$SUPERVISOR" > /dev/null 2>&1; then
    run_test "$SUPERVISOR" "supervisor --version" --version
else
    fail "Could not pull $SUPERVISOR"
fi

# ---------------------------------------------------------------------------
# Sandbox images
# ---------------------------------------------------------------------------
echo ""
echo "=== Sandbox: base ==="
BASE="${REGISTRY}/sandboxes/base:${TAG}"
if podman pull "$BASE" > /dev/null 2>&1; then
    run_test "$BASE" "node --version" -c "node --version"
    run_test "$BASE" "python3 --version" -c "python3 --version"
    run_test "$BASE" "npm --version" -c "npm --version"
    run_test "$BASE" "gh --version" -c "gh --version"
    run_test "$BASE" "git --version" -c "git --version"
    run_test "$BASE" "uv --version" -c "uv --version"
    run_test "$BASE" "opencode --version" -c "opencode --version"
    run_test "$BASE" "claude --version" -c "claude --version"
    run_test "$BASE" "policy.yaml exists" -c "test -f /etc/openshell/policy.yaml"
    run_test "$BASE" "sandbox user exists" -c "id sandbox"
    run_test "$BASE" "bash available" -c "bash --version"
else
    fail "Could not pull $BASE"
fi

echo ""
echo "=== Sandbox: openclaw ==="
OPENCLAW="${REGISTRY}/sandboxes/openclaw:${TAG}"
if podman pull "$OPENCLAW" > /dev/null 2>&1; then
    run_test "$OPENCLAW" "openclaw --version" -c "openclaw --version"
    run_test "$OPENCLAW" "openclaw-start exists" -c "test -x /usr/local/bin/openclaw-start"
else
    fail "Could not pull $OPENCLAW"
fi

echo ""
echo "=== Sandbox: openclaw-nvidia ==="
OPENCLAW_NV="${REGISTRY}/sandboxes/openclaw-nvidia:${TAG}"
if podman pull "$OPENCLAW_NV" > /dev/null 2>&1; then
    run_test "$OPENCLAW_NV" "openclaw --version" -c "openclaw --version"
    run_test "$OPENCLAW_NV" "jq --version" -c "jq --version"
    run_test "$OPENCLAW_NV" "openclaw-nvidia-start exists" -c "test -x /usr/local/bin/openclaw-nvidia-start"
    run_test "$OPENCLAW_NV" "policy-proxy.js exists" -c "test -f /usr/local/lib/policy-proxy.js"
else
    fail "Could not pull $OPENCLAW_NV"
fi

echo ""
echo "=== Sandbox: ollama ==="
OLLAMA="${REGISTRY}/sandboxes/ollama:${TAG}"
if podman pull "$OLLAMA" > /dev/null 2>&1; then
    run_test "$OLLAMA" "ollama binary exists" -c "test -x /sandbox/bin/ollama"
    run_test "$OLLAMA" "entrypoint exists" -c "test -x /usr/local/bin/entrypoint"
    run_test "$OLLAMA" "update-ollama exists" -c "test -x /sandbox/bin/update-ollama"
else
    fail "Could not pull $OLLAMA"
fi

echo ""
echo "=== Sandbox: gemini ==="
GEMINI="${REGISTRY}/sandboxes/gemini:${TAG}"
if podman pull "$GEMINI" > /dev/null 2>&1; then
    run_test "$GEMINI" "gemini --version" -c "gemini --version"
else
    fail "Could not pull $GEMINI"
fi

echo ""
echo "=== Sandbox: droid ==="
DROID="${REGISTRY}/sandboxes/droid:${TAG}"
if podman pull "$DROID" > /dev/null 2>&1; then
    run_test "$DROID" "droid --version" -c "droid --version"
else
    fail "Could not pull $DROID"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
if [ "$FAILURES" -eq 0 ]; then
    echo "All tests passed."
else
    echo "FAILURES: ${FAILURES}"
    exit 1
fi
