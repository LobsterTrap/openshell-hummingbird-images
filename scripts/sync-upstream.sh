#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0

# sync-upstream.sh — Pull support files from upstream OpenShell-Community repo
#
# This script syncs files that are used as-is from upstream (application code,
# proto definitions, UI extensions) without modification. It does NOT sync
# Containerfiles or policy.yaml files, which are maintained separately in this
# repo with Hummingbird/Fedora adaptations.
#
# Usage:
#   ./scripts/sync-upstream.sh [--ref REF]
#
# Options:
#   --ref REF   Git ref to sync from (default: main)

set -euo pipefail

UPSTREAM_REPO="NVIDIA/OpenShell-Community"
UPSTREAM_REF="main"
WORK_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

trap 'rm -rf "$WORK_DIR"' EXIT

while [ "$#" -gt 0 ]; do
    case "$1" in
        --ref)
            if [ "$#" -lt 2 ]; then
                echo "Error: --ref requires a value" >&2
                exit 1
            fi
            UPSTREAM_REF="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: ./scripts/sync-upstream.sh [--ref REF] [REF]"
            exit 0
            ;;
        -*)
            echo "Error: unknown option: $1" >&2
            exit 1
            ;;
        *)
            UPSTREAM_REF="$1"
            shift
            ;;
    esac
done

echo "Syncing from ${UPSTREAM_REPO}@${UPSTREAM_REF}..."

# Clone upstream (shallow)
git clone --depth 1 --branch "$UPSTREAM_REF" \
    "https://github.com/${UPSTREAM_REPO}.git" \
    "$WORK_DIR/upstream" 2>/dev/null || \
git clone --depth 1 \
    "https://github.com/${UPSTREAM_REPO}.git" \
    "$WORK_DIR/upstream"

UPSTREAM="$WORK_DIR/upstream"

# ---------------------------------------------------------------------------
# openclaw-nvidia support files (application code, not config)
# ---------------------------------------------------------------------------
echo "Syncing openclaw-nvidia support files..."

# policy-proxy.js and inference-options.js
for f in policy-proxy.js inference-options.js; do
    if [ -f "$UPSTREAM/sandboxes/openclaw-nvidia/$f" ]; then
        cp "$UPSTREAM/sandboxes/openclaw-nvidia/$f" \
           "$REPO_ROOT/sandboxes/openclaw-nvidia/$f"
        echo "  Synced: openclaw-nvidia/$f"
    fi
done

# Proto files
if [ -d "$UPSTREAM/sandboxes/openclaw-nvidia/proto" ]; then
    rm -rf "$REPO_ROOT/sandboxes/openclaw-nvidia/proto"
    cp -r "$UPSTREAM/sandboxes/openclaw-nvidia/proto" \
       "$REPO_ROOT/sandboxes/openclaw-nvidia/proto"
    echo "  Synced: openclaw-nvidia/proto/"
fi

# NeMoClaw UI extension
if [ -d "$UPSTREAM/sandboxes/openclaw-nvidia/nemoclaw-ui-extension" ]; then
    rm -rf "$REPO_ROOT/sandboxes/openclaw-nvidia/nemoclaw-ui-extension"
    cp -r "$UPSTREAM/sandboxes/openclaw-nvidia/nemoclaw-ui-extension" \
       "$REPO_ROOT/sandboxes/openclaw-nvidia/nemoclaw-ui-extension"
    echo "  Synced: openclaw-nvidia/nemoclaw-ui-extension/"
fi

# ---------------------------------------------------------------------------
# Report upstream versions for tracking
# ---------------------------------------------------------------------------
echo ""
echo "Upstream commit: $(cd "$UPSTREAM" && git rev-parse HEAD)"
echo "Upstream date:   $(cd "$UPSTREAM" && git log -1 --format='%ci')"
echo ""
echo "Sync complete. Files that need manual review/translation are NOT synced:"
echo "  - Containerfiles (contain dnf/Fedora-specific instructions)"
echo "  - policy.yaml files (contain Fedora filesystem paths)"
echo ""
echo "Run 'git diff' to review changes before committing."
