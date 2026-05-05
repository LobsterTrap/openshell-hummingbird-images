# OpenShell Hummingbird Images

Container images for [OpenShell](https://github.com/NVIDIA/OpenShell) and
[OpenShell-Community](https://github.com/NVIDIA/OpenShell-Community), rebased
onto [Project Hummingbird](https://hummingbird-project.io) minimal, hardened
base images.

## Why Hummingbird?

The upstream OpenShell images use `nvcr.io/nvidia/base/ubuntu:noble` as their
base. This project rebuilds them on Project Hummingbird images, which provide:

- Near-zero CVE attack surface
- Hermetic, reproducible builds with SLSA provenance
- Full SBOM and cosign signatures
- Content-based layers (smaller, more cacheable updates)
- Built from Fedora Rawhide packages

## Image Catalog

All images are published to `ghcr.io/lobstertrap/openshell-hummingbird-images/`.

### Core Infrastructure

These run the OpenShell control plane. Built on `quay.io/hummingbird/core-runtime`
(distroless — no shell, minimal attack surface).

| Image | Purpose |
|-------|---------|
| `gateway` | Control-plane API; manages sandbox lifecycle and auth |
| `supervisor` | In-sandbox policy enforcement (filesystem, network, process) |

### Sandbox Images

Pre-configured environments for AI coding agents. Built on
`quay.io/hummingbird/nodejs:22-builder` (includes bash + dnf for interactive use).

| Image | Base | Purpose |
|-------|------|---------|
| `sandboxes/base` | Hummingbird Node.js 22 | Foundation: Node.js, Python 3.13, Claude, OpenCode, Codex, Copilot, gh |
| `sandboxes/openclaw` | base | + OpenClaw agent CLI |
| `sandboxes/openclaw-nvidia` | openclaw | + NeMoClaw DevX UI, policy proxy, gRPC |
| `sandboxes/ollama` | base | + Ollama for local LLM inference |
| `sandboxes/gemini` | base | + Google Gemini CLI |
| `sandboxes/droid` | base | + Factory Droid CLI |

### Image Dependency Chain

```
quay.io/hummingbird/core-runtime (distroless)
├── gateway
└── supervisor

quay.io/hummingbird/nodejs:22-builder
└── sandboxes/base
    ├── sandboxes/openclaw
    │   └── sandboxes/openclaw-nvidia
    ├── sandboxes/ollama
    ├── sandboxes/gemini
    └── sandboxes/droid
```

## Usage

Pull images directly:

```bash
# Core infrastructure
docker pull ghcr.io/lobstertrap/openshell-hummingbird-images/gateway:latest
docker pull ghcr.io/lobstertrap/openshell-hummingbird-images/supervisor:latest

# Sandbox images
docker pull ghcr.io/lobstertrap/openshell-hummingbird-images/sandboxes/base:latest
docker pull ghcr.io/lobstertrap/openshell-hummingbird-images/sandboxes/openclaw:latest
```

Use with OpenShell CLI (point to this registry):

```bash
openshell sandbox create \
  --image ghcr.io/lobstertrap/openshell-hummingbird-images/sandboxes/base:latest
```

## Architecture

All images are multi-arch (`linux/amd64` + `linux/arm64`).

## Tags

| Tag | Meaning |
|-----|---------|
| `latest` | Most recent release |
| `x.y.z` | Specific release version |
| `<sha>` | Specific commit build |

## Differences from Upstream

These images differ from the official NVIDIA-published images in their base
layer only:

| | Upstream | This Project |
|---|---------|-------------|
| Base (core) | `nvcr.io/nvidia/base/ubuntu:noble` | `quay.io/hummingbird/core-runtime` |
| Base (sandboxes) | `nvcr.io/nvidia/base/ubuntu:noble` | `quay.io/hummingbird/nodejs:22-builder` |
| Package manager | apt (Ubuntu/Debian) | dnf (Fedora) |
| CVE posture | Standard Ubuntu | Near-zero CVE (Hummingbird hardened) |
| Build provenance | Standard | SLSA provenance + SBOM |

Application-level content (binaries, tools, configurations, policies) is
functionally equivalent.

## Related Projects

- [OpenShell](https://github.com/NVIDIA/OpenShell) — Safe, private runtime for autonomous AI agents
- [OpenShell-Community](https://github.com/NVIDIA/OpenShell-Community) — Community sandbox images, skills, and integrations
- [Project Hummingbird](https://hummingbird-project.io) — Minimal, hardened container images

## License

[Apache License 2.0](LICENSE)
