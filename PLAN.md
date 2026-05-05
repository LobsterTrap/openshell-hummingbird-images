# OpenShell Hummingbird Images — Implementation Plan

This document tracks the plan to rebase all OpenShell and OpenShell-Community
container images onto Project Hummingbird base images, hosted in this repository
and published to `ghcr.io/lobstertrap/openshell-hummingbird-images/`.

## Table of Contents

- [Decisions](#decisions)
- [Upstream Image Inventory](#upstream-image-inventory)
- [Hummingbird Base Image Mapping](#hummingbird-base-image-mapping)
- [Package Translation (Ubuntu to Fedora)](#package-translation-ubuntu-to-fedora)
- [Gap Analysis and Risks](#gap-analysis-and-risks)
- [Repository Structure](#repository-structure)
- [Registry Layout](#registry-layout)
- [CI/CD Pipeline Design](#cicd-pipeline-design)
- [Implementation Phases](#implementation-phases)
- [Session Tracking](#session-tracking)

---

## Decisions

These decisions were made during the planning session and inform all
implementation work.

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Image scope | All core (gateway, supervisor) + all community sandboxes | Full coverage of published images |
| Cluster image | **Excluded** | Too specialized, bundles k3s/k9s/Helm/NVIDIA CTK in a privileged container |
| CI image | **Excluded** | Internal-only, not user-facing |
| Sandbox base strategy | Hummingbird `-builder` variants | Sandboxes require bash, dnf, and interactive tools |
| Core infra base strategy | Hummingbird distroless | Gateway and supervisor are single Rust binaries |
| Registry namespace | `ghcr.io/lobstertrap/openshell-hummingbird-images/*` | Flat namespace under this repo |
| Binary sourcing (core) | Build from source | Clone NVIDIA/OpenShell, compile Rust binaries in CI |
| Policy files | Adapt for Fedora | Filesystem paths differ between Ubuntu and Fedora |
| Build tooling | **Podman** (native commands) | No Docker dependency; uses podman build/manifest/push |
| Multi-arch strategy | `podman manifest` + `qemu-user-static` | Per-arch builds merged into multi-arch manifests |

---

## Upstream Image Inventory

### OpenShell Core (NVIDIA/OpenShell)

All currently based on `nvcr.io/nvidia/base/ubuntu:noble-20251013`.

| Image | Registry Path | Purpose | In Scope |
|-------|--------------|---------|----------|
| gateway | `ghcr.io/nvidia/openshell/gateway` | Control-plane API, sandbox lifecycle management | Yes |
| supervisor | `ghcr.io/nvidia/openshell/supervisor` | In-sandbox policy enforcement (fs, net, process) | Yes |
| cluster | `ghcr.io/nvidia/openshell/cluster` | Self-contained k3s cluster w/ embedded supervisor | No |
| ci | `ghcr.io/nvidia/openshell/ci` | Internal CI runner | No |

Build details:
- Rust binaries are compiled natively (not inside Docker) via `shadow-rust-native-build.yml`
- Pre-built binaries are staged at `deploy/docker/.build/prebuilt-binaries/<arch>/`
- `Dockerfile.images` is a multi-target Dockerfile with separate stages for gateway, supervisor, cluster
- Multi-arch: linux/amd64 + linux/arm64

### OpenShell-Community Sandboxes (NVIDIA/OpenShell-Community)

All currently based on `nvcr.io/nvidia/base/ubuntu:noble-20251013` (via base image).

| Image | Registry Path | Base | Purpose | Downloads |
|-------|--------------|------|---------|-----------|
| base | `ghcr.io/nvidia/openshell-community/sandboxes/base` | Ubuntu Noble (NGC) | Foundation: Node.js 22, Python 3.13, Claude, OpenCode, Codex, Copilot, gh | 48.1k |
| openclaw | `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` | base | + OpenClaw agent CLI | 25.6k |
| openclaw-nvidia | `ghcr.io/nvidia/openshell-community/sandboxes/openclaw-nvidia` | openclaw | + NeMoClaw DevX UI, policy proxy, gRPC | 717 |
| ollama | `ghcr.io/nvidia/openshell-community/sandboxes/ollama` | base | + Ollama for local inference | 1.09k |
| gemini | `ghcr.io/nvidia/openshell-community/sandboxes/gemini` | base | + Google Gemini CLI | 124 |
| droid | `ghcr.io/nvidia/openshell-community/sandboxes/droid` | base | + Factory Droid CLI | 28 |
| sdg | — | — | **Placeholder only** (`.gitkeep`, no Dockerfile) | 0 |

### Upstream Dependency Chain

```
nvcr.io/nvidia/base/ubuntu:noble-20251013
├── gateway
├── supervisor
└── sandboxes/base
    ├── COPY --from ghcr.io/astral-sh/uv:0.10.8 (uv binary)
    ├── sandboxes/openclaw
    │   └── sandboxes/openclaw-nvidia
    ├── sandboxes/ollama
    ├── sandboxes/gemini
    └── sandboxes/droid
```

---

## Hummingbird Base Image Mapping

### About Project Hummingbird

Project Hummingbird is a Red Hat initiative providing minimal, hardened,
distroless container images built from Fedora Rawhide. Key properties:

- Near-zero CVE target
- Hermetic, reproducible builds with SLSA provenance
- Content-based layers via chunkah (package-grouped, shareable)
- Full SBOM and cosign signatures
- Hosted at `quay.io/hummingbird/`
- Multi-arch: amd64 + arm64
- MIT licensed, freely redistributable at GA
- Variants: distroless (default, no shell) and builder (bash + dnf)

Docs: https://hummingbird-project.io

### Core Infrastructure → Distroless

| Image | Hummingbird Base | Rationale |
|-------|-----------------|-----------|
| gateway | `quay.io/hummingbird/core-runtime` | Minimal glibc runtime for compiled binary |
| supervisor | `quay.io/hummingbird/core-runtime` | Minimal glibc runtime for compiled binary |

### Sandbox Images → Builder Variants

| Image | Hummingbird Base | Rationale |
|-------|-----------------|-----------|
| sandboxes/base | `quay.io/hummingbird/nodejs:22-builder` | Pre-installed Node.js 22 + bash + dnf. Python via uv. |
| sandboxes/openclaw | Our own `sandboxes/base` | Same layering pattern as upstream |
| sandboxes/openclaw-nvidia | Our own `sandboxes/openclaw` | Same layering pattern as upstream |
| sandboxes/ollama | Our own `sandboxes/base` | Same layering pattern as upstream |
| sandboxes/gemini | Our own `sandboxes/base` | Same layering pattern as upstream |
| sandboxes/droid | Our own `sandboxes/base` | Same layering pattern as upstream |

### New Dependency Chain

```
quay.io/hummingbird/core-runtime (distroless)
├── gateway
└── supervisor

quay.io/hummingbird/nodejs:22-builder
├── COPY --from ghcr.io/astral-sh/uv:0.10.8
└── sandboxes/base
    ├── sandboxes/openclaw
    │   └── sandboxes/openclaw-nvidia
    ├── sandboxes/ollama
    ├── sandboxes/gemini
    └── sandboxes/droid
```

---

## Package Translation (Ubuntu to Fedora)

The sandbox base image currently installs Ubuntu packages via `apt-get`. These
must be translated to Fedora equivalents for `dnf`.

### System Packages

| Ubuntu (apt-get) | Fedora (dnf) | Notes |
|------------------|-------------|-------|
| `ca-certificates` | `ca-certificates` | Same |
| `curl` | `curl` | Same |
| `dnsutils` | `bind-utils` | Different name |
| `iproute2` | `iproute` | Different name |
| `iptables` | `iptables-nft` | Fedora uses nftables backend |
| `iputils-ping` | `iputils` | Different name |
| `net-tools` | `net-tools` | Same |
| `netcat-openbsd` | `nmap-ncat` | Different tool/name |
| `openssh-sftp-server` | `openssh-server` | sftp-server is bundled in openssh-server on Fedora |
| `procps` | `procps-ng` | Different name |
| `traceroute` | `traceroute` | Same |

### Additional Tools

| Tool | Upstream Install Method | Hummingbird Strategy |
|------|------------------------|---------------------|
| Node.js 22 | NodeSource apt repo | Pre-installed in `nodejs:22-builder` base |
| npm 11 | Upgraded via `npm install -g npm@11.11.0` | Same (upgrade from base) |
| Python 3.13 | Installed via `uv` (COPY binary from uv image) | Same approach |
| Claude CLI | `claude.ai/install.sh` | Same; test on Fedora, fallback to npm if needed |
| GitHub CLI (gh) | GitHub apt repo | `dnf install gh` (available in Fedora repos) or binary from GitHub Releases |
| OpenCode | `npm install -g opencode-ai` | Same |
| Codex | `npm install -g @openai/codex` | Same |
| Copilot | `npm install -g @github/copilot` | Same |
| jq (openclaw-nvidia) | `apt-get install jq` | `dnf install jq` |
| zstd (ollama) | `apt-get install zstd` | `dnf install zstd` |

---

## Gap Analysis and Risks

### Existing Gaps

1. **SDG sandbox** — Reserved directory with `.gitkeep` in upstream, no
   Dockerfile exists. Not actionable until upstream defines scope.

### Compatibility Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Policy.yaml filesystem paths | Medium | Fedora uses `/usr/lib64` for 64-bit libs vs Ubuntu's `/usr/lib`. Verify and adapt each policy file. Binary paths (`/usr/bin/node`, `/usr/bin/python3`) should be consistent. |
| Claude CLI installer | Low | `claude.ai/install.sh` may not detect Fedora. Fallback: install via npm (`@anthropic-ai/claude-cli`). |
| Hummingbird Node.js version drift | Low | Upstream pins Node.js `22.22.1`. Hummingbird may ship a different 22.x patch version. Functionally equivalent. |
| Non-root user differences | Low | Hummingbird defaults to UID 65532. Must create `sandbox` (UID 1000) and `supervisor` users explicitly, matching upstream. |
| Hummingbird early access stability | Medium | Images at `quay.io/hummingbird/` may change. Pin specific tags, not `:latest`. |
| Rust build complexity | Medium | NVIDIA/OpenShell uses `mise` for task orchestration. Need to replicate or simplify the build pipeline for gateway and supervisor binaries. |
| openssh-sftp-server path | Low | On Fedora, sftp-server binary is at `/usr/libexec/openssh/sftp-server` vs Ubuntu's `/usr/lib/openssh/sftp-server`. Policy files referencing this path must be updated. |

---

## Repository Structure

```
openshell-hummingbird-images/
├── LICENSE                              # Apache 2.0 (exists)
├── README.md                            # Project overview, image catalog, usage
├── PLAN.md                              # This file
├── .github/
│   └── workflows/
│       ├── build-core.yml               # Build gateway + supervisor
│       ├── build-sandboxes.yml          # Build sandbox images (change-aware)
│       └── release.yml                  # Tag-triggered: semver + latest
├── core/
│   ├── gateway/
│   │   └── Containerfile                # FROM quay.io/hummingbird/core-runtime
│   └── supervisor/
│       └── Containerfile                # FROM quay.io/hummingbird/core-runtime
├── sandboxes/
│   ├── base/
│   │   ├── Containerfile                # FROM quay.io/hummingbird/nodejs:22-builder
│   │   ├── policy.yaml
│   │   └── skills/                      # Agent skills directory
│   ├── openclaw/
│   │   ├── Containerfile
│   │   ├── policy.yaml
│   │   └── openclaw-start
│   ├── openclaw-nvidia/
│   │   ├── Containerfile
│   │   ├── policy.yaml
│   │   ├── policy-proxy.js
│   │   ├── inference-options.js
│   │   ├── openclaw-nvidia-start
│   │   └── devx/                        # NeMoClaw DevX extension sources
│   ├── ollama/
│   │   ├── Containerfile
│   │   ├── policy.yaml
│   │   ├── entrypoint.sh
│   │   └── update-ollama.sh
│   ├── gemini/
│   │   ├── Containerfile
│   │   └── policy.yaml
│   └── droid/
│       ├── Containerfile
│       └── policy.yaml
└── scripts/
    ├── sync-upstream.sh                 # Pull latest configs from upstream repos
    └── verify-images.sh                 # Smoke tests for built images
```

---

## Registry Layout

All images published under the `ghcr.io/lobstertrap/openshell-hummingbird-images/` namespace:

```
ghcr.io/lobstertrap/openshell-hummingbird-images/gateway
ghcr.io/lobstertrap/openshell-hummingbird-images/supervisor
ghcr.io/lobstertrap/openshell-hummingbird-images/sandboxes/base
ghcr.io/lobstertrap/openshell-hummingbird-images/sandboxes/openclaw
ghcr.io/lobstertrap/openshell-hummingbird-images/sandboxes/openclaw-nvidia
ghcr.io/lobstertrap/openshell-hummingbird-images/sandboxes/ollama
ghcr.io/lobstertrap/openshell-hummingbird-images/sandboxes/gemini
ghcr.io/lobstertrap/openshell-hummingbird-images/sandboxes/droid
```

**Tag strategy:**

| Tag Pattern | When Applied | Example |
|-------------|--------------|---------|
| `<commit-sha>` | Every CI build on `main` | `a1b2c3d` |
| `<semver>` | On release tag push (`v*.*.*`) | `0.1.0` |
| `latest` | On release tag push | `latest` |

All images are multi-arch manifests: `linux/amd64` + `linux/arm64`.

---

## CI/CD Pipeline Design

### build-core.yml — Core Infrastructure

**Triggers:** Push to `main` (paths: `core/**`), release tags, manual dispatch.

**Jobs:**
1. **build-rust** (per-arch: amd64, arm64)
   - Check out `NVIDIA/OpenShell` at a pinned tag/commit
   - Install Rust toolchain
   - Build `openshell-gateway` and `openshell-sandbox` (supervisor) binaries
   - Upload binaries as workflow artifacts
2. **build-images** (per-arch, depends on build-rust)
   - Download pre-built binaries
   - Build `gateway` Containerfile (FROM `quay.io/hummingbird/core-runtime`)
   - Build `supervisor` Containerfile (FROM `quay.io/hummingbird/core-runtime`)
   - Push per-arch images to GHCR
3. **merge-manifests** (depends on build-images)
   - `podman manifest create/add/push` to merge amd64 + arm64 into multi-arch manifest

### build-sandboxes.yml — Sandbox Images

**Triggers:** Push to `main` (paths: `sandboxes/**`), release tags, manual dispatch.

**Jobs:**
1. **detect-changes**
   - Diff changed files against `sandboxes/`
   - If `sandboxes/base/` changed → rebuild ALL sandboxes
   - Otherwise → only rebuild changed sandboxes
2. **build-base** (multi-arch, runs if base changed or manual/release)
   - Build `sandboxes/base` Containerfile
   - Push to GHCR
3. **build-derivatives** (matrix job, depends on build-base)
   - For each changed sandbox: build its Containerfile using our base image
   - Push to GHCR
4. **merge-manifests** for each image

### release.yml — Release Pipeline

**Triggers:** Push of `v*.*.*` tag.

**Jobs:**
1. Trigger `build-core.yml` and `build-sandboxes.yml` (build everything)
2. Run `scripts/verify-images.sh` smoke tests
3. Re-tag all images with semver + `latest` via `podman manifest create/push`
4. Create GitHub Release with image manifest

---

## Implementation Phases

### Phase 1: Repository Scaffolding (Session 1)
- [x] Write PLAN.md
- [x] Create directory structure (`core/`, `sandboxes/`, `scripts/`, `.github/workflows/`)
- [x] Write README.md (project overview, image catalog, usage instructions)

### Phase 2: Core Infrastructure Images (Session 2)
- [x] Write `core/gateway/Containerfile`
- [x] Write `core/supervisor/Containerfile`
- [x] Write `build-core.yml` workflow (including Rust build-from-source)
- [x] Test gateway and supervisor image builds (CI verified — all green)

### Phase 3: Sandbox Base Image (Session 2)
- [x] Write `sandboxes/base/Containerfile` (full Ubuntu→Fedora translation)
- [x] Adapt `sandboxes/base/policy.yaml` for Fedora filesystem paths
- [x] Copy/adapt agent skills
- [x] Test base sandbox image (CI verified — all green)

### Phase 4: Sandbox Derivative Images (Session 2)
- [x] Write `sandboxes/openclaw/Containerfile` + policy.yaml + openclaw-start
- [x] Write `sandboxes/openclaw-nvidia/Containerfile` + all support files
- [x] Write `sandboxes/ollama/Containerfile` + policy.yaml + scripts
- [x] Write `sandboxes/gemini/Containerfile` + policy.yaml
- [x] Write `sandboxes/droid/Containerfile` + policy.yaml
- [x] Run `scripts/sync-upstream.sh` to populate openclaw-nvidia JS/proto/UI files
- [x] Test each derivative image (CI verified — all green)

### Phase 5: CI/CD + Release (Session 2)
- [x] Write `build-sandboxes.yml` with change detection
- [x] Write `release.yml`
- [x] Write `scripts/verify-images.sh`
- [x] Write `scripts/sync-upstream.sh`

### Phase 6: Documentation + Review (Session 3)
- [x] Finalize README.md with full usage examples
- [x] Contributing guide (`CONTRIBUTING.md`)
- [x] Code review of all Containerfiles and workflows
- [x] Fixed: openclaw-nvidia missing `USER sandbox` (security)
- [x] Fixed: build-core.yml and build-sandboxes.yml missing `workflow_call` triggers
- [x] Fixed: release.yml SHA tag mismatch (full SHA vs short SHA)
- [x] Fixed: gateway migrations chmod (755 -> 644)
- [x] Fixed: base Containerfile Claude CLI fallback for Fedora
- [x] Fixed: build-sandboxes.yml detect-changes logic for workflow_call/tag events

### Phase 7: Docker → Podman Migration (Session 4)
- [x] Rewrite `build-core.yml`: replace Docker actions with native podman commands
- [x] Rewrite `build-sandboxes.yml`: replace Docker actions with native podman commands
- [x] Rewrite `release.yml`: replace Docker CLI with podman CLI
- [x] Remove `# syntax=docker/dockerfile:1` from all 8 Containerfiles
- [x] Update all build comments from `docker build` to `podman build`
- [x] Update `scripts/verify-images.sh` to use podman
- [x] Update README.md, CONTRIBUTING.md, PLAN.md to reference podman
- [x] Verify zero Docker references in project-owned files
- [x] CI verified: all 8 images build and push with podman

### Phase 8: Hummingbird Compatibility Fixes (Sessions 3-4)
- [x] Fixed: `USER root` required for Hummingbird builder stages (default UID 65532)
- [x] Fixed: `ca-certificates` and `curl` already in Hummingbird base (skip)
- [x] Fixed: networking tools not in Hummingbird repos (use `--skip-unavailable`)
- [x] Fixed: `vim-minimal` and `nano` not in Hummingbird repos (use `--skip-unavailable`)
- [x] Fixed: `gh` CLI not in Hummingbird repos (install from GitHub Releases binary)
- [x] Fixed: `tar` not in Hummingbird builder base (add to dnf install)
- [x] Fixed: `gawk` needed for Ollama install script (add to dnf install)

---

## Session Tracking

| Session | Date | Scope | Status |
|---------|------|-------|--------|
| 1 | 2026-05-05 | Research, planning, scaffolding | Complete |
| 2 | 2026-05-05 | Core + sandbox + CI/CD (all phases) | Complete |
| 3 | 2026-05-05 | Sync, review, bugfixes, docs | Complete |
| 4 | 2026-05-05 | Docker→Podman migration, CI stabilization | Complete |

---

## Reference Links

- **This repo:** https://github.com/LobsterTrap/openshell-hummingbird-images
- **OpenShell:** https://github.com/NVIDIA/OpenShell
- **OpenShell-Community:** https://github.com/NVIDIA/OpenShell-Community
- **Hummingbird Project:** https://hummingbird-project.io
- **Hummingbird images:** https://quay.io/organization/hummingbird
- **Hummingbird source:** https://gitlab.com/redhat/hummingbird
