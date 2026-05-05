# Contributing to OpenShell Hummingbird Images

## Overview

This repository maintains Hummingbird-based rebuilds of OpenShell and
OpenShell-Community container images. The upstream sources are:

- **Core images** (gateway, supervisor): [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell)
- **Sandbox images** (base, openclaw, ollama, gemini, droid): [NVIDIA/OpenShell-Community](https://github.com/NVIDIA/OpenShell-Community)

## Repository Structure

```
core/                    # Core infrastructure images (distroless)
  gateway/Containerfile
  supervisor/Containerfile
sandboxes/               # Sandbox images (builder variants)
  base/                  # Foundation sandbox - all others build on this
  openclaw/
  openclaw-nvidia/
  ollama/
  gemini/
  droid/
scripts/                 # Build and maintenance scripts
.github/workflows/       # CI/CD pipelines
```

## Key Differences from Upstream

All images use [Project Hummingbird](https://hummingbird-project.io) base
images instead of `nvcr.io/nvidia/base/ubuntu:noble`. This means:

1. **Package manager**: `dnf` (Fedora) instead of `apt-get` (Ubuntu)
2. **Package names**: Some differ (see `PLAN.md` for the translation table)
3. **Library paths**: Fedora uses `/usr/lib64` for 64-bit libraries
4. **Filesystem policy**: `policy.yaml` files include `/lib64` in `read_only`

## Adding a New Sandbox Image

1. Create a directory under `sandboxes/<name>/`
2. Create a `Containerfile` that starts with:
   ```dockerfile
   ARG BASE_IMAGE=ghcr.io/lobstertrap/openshell-hummingbird-images/sandboxes/base:latest
   FROM ${BASE_IMAGE}
   ```
3. Create a `policy.yaml` with Fedora-appropriate filesystem paths (include
   `/lib64` in `read_only`)
4. The CI will auto-detect the new sandbox via the `detect-changes` job

## Modifying Existing Images

### Containerfiles and policy.yaml

These are maintained in this repository with Fedora/Hummingbird-specific
adaptations. Edit them directly.

### Support files (JS, proto, UI extensions)

Files like `policy-proxy.js`, `inference-options.js`, proto definitions, and
the NeMoClaw UI extension are synced from upstream without modification:

```bash
./scripts/sync-upstream.sh [--ref REF]
```

Do not edit these files directly -- changes will be overwritten by the next
sync. If a support file needs Fedora-specific changes, move it out of the
sync scope and document the divergence.

## Package Name Reference

When translating Ubuntu packages to Fedora for Containerfiles:

| Ubuntu | Fedora |
|--------|--------|
| `apt-get update && apt-get install -y` | `dnf install -y --setopt=install_weak_deps=False` |
| `rm -rf /var/lib/apt/lists/*` | `dnf clean all && rm -rf /var/cache/dnf` |
| `dnsutils` | `bind-utils` |
| `iproute2` | `iproute` |
| `iptables` | `iptables-nft` |
| `iputils-ping` | `iputils` |
| `netcat-openbsd` | `nmap-ncat` |
| `openssh-sftp-server` | `openssh-server` |
| `procps` | `procps-ng` |
| `build-essential` | `gcc gcc-c++ make` |
| `vim-tiny` | `vim-minimal` |

## Testing Locally

Build individual images:

```bash
# Base sandbox
docker build -f sandboxes/base/Containerfile -t openshell-base sandboxes/base/

# Derivative (after building base)
docker build -f sandboxes/gemini/Containerfile \
  --build-arg BASE_IMAGE=openshell-base \
  -t openshell-gemini sandboxes/gemini/
```

Run smoke tests:

```bash
./scripts/verify-images.sh localhost latest
```

## CI/CD

- **Push to `main`** with changes in `core/` or `sandboxes/` triggers builds
- **Tag `v*.*.*`** triggers a full release (all images rebuilt, tagged, released)
- **Manual dispatch** rebuilds everything

## License

Apache License 2.0. See [LICENSE](LICENSE).
