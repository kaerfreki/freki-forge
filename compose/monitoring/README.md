# Monitoring (GPU + optional inference scrapes)

Lightweight Prometheus + Grafana stack for the host GPU. Independent of
Ollama / vLLM / ComfyUI — start this project alone; run inference compose
projects separately when you want load on the card.

## Why `nvidia_gpu_exporter` (not DCGM)

| | **utkuozdemir/nvidia_gpu_exporter** | **NVIDIA DCGM Exporter** |
| --- | --- | --- |
| **Fit** | Consumer GeForce/RTX, workstations, homelab | Datacenter GPUs + GPU Operator |
| **Weight** | ~35 MB image; runs `nvidia-smi` via Container Toolkit | Heavier DCGM stack; more fragile on desktop drivers |
| **Metrics** | Util, VRAM, temp, power, clocks, … | Richer counter set on supported cards |

This repo targets a single consumer GPU (tested: RTX 4080). The Go exporter
is the simplest reliable option with NVIDIA Container Toolkit: no DCGM
install, same `deploy.resources` GPU reservation pattern as the inference
services.

Pinned image: `utkuozdemir/nvidia_gpu_exporter:1.13.1`.

## Quickstart

Prerequisites: same as the rest of the stack (NVIDIA driver + Container
Toolkit for Docker).

```bash
cd compose/monitoring
# optional: cp .env.example .env
docker compose up -d
```

If the GPU exporter fails with `nvml error: driver/library version mismatch`,
the host driver and userspace libraries are out of sync (common right after a
driver upgrade before reboot). Prometheus and Grafana still start; bring the
exporter up after a reboot, or temporarily:

```bash
docker compose up -d prometheus grafana
```

| UI | URL | Notes |
| --- | --- | --- |
| **Prometheus** | http://localhost:9090 | Status → Targets; Graph explorer |
| **Grafana** | http://localhost:3000 | default `admin` / `admin` (change on shared hosts) |
| **GPU exporter** | http://localhost:9835/metrics | raw Prometheus text |

Provisioned Grafana:

- Datasource **Prometheus** → `http://prometheus:9090`
- Dashboard **GPU overview** (folder `freki-llm`) — util, VRAM, temp, power

For a fuller multi-panel view you can also import Grafana dashboard
[14574](https://grafana.com/grafana/dashboards/14574) (official for this
exporter).

## Key metrics

| What | PromQL / series | Notes |
| --- | --- | --- |
| GPU util | `nvidia_smi_utilization_gpu_ratio` | 0–1 ratio; dashboard multiplies by 100 |
| VRAM used | `nvidia_smi_memory_used_bytes` | bytes (exporter converts MiB from `nvidia-smi`) |
| VRAM total | `nvidia_smi_memory_total_bytes` | |
| Temperature | `nvidia_smi_temperature_gpu` | °C |
| Power | `nvidia_smi_power_draw_watts` | W |
| Exporter health | `nvidia_smi_last_collect_success` | `1` = last `nvidia-smi` collection ok |

Quick checks:

```bash
# GPU series present?
curl -s 'http://localhost:9090/api/v1/query?query=nvidia_smi_utilization_gpu_ratio' | jq .

# Raw exporter
curl -s http://localhost:9835/metrics | grep -E 'nvidia_smi_(utilization_gpu|memory_used|temperature_gpu)'
```

## Scrape targets

Configured in [`prometheus/prometheus.yml`](prometheus/prometheus.yml):

| Job | Target | When UP |
| --- | --- | --- |
| `nvidia-gpu` | `nvidia-gpu-exporter:9835` | Always (this compose project) |
| `vllm` | `host.docker.internal:8000` `/metrics` | When [`compose/vllm`](../vllm) is running |

**Ollama** does **not** expose a native Prometheus `/metrics` endpoint.
Watch Ollama (and ComfyUI) GPU cost via the `nvidia-gpu` job while those
services run. A third-party Ollama exporter can be added later as another
static scrape on `host.docker.internal`.

Prometheus reaches host-published ports via `extra_hosts:
host.docker.internal:host-gateway` (Linux Docker). Optional targets show
**DOWN** in Status → Targets until the inference container is up — that is
expected, not an error in this stack.

## Configuration

Copy [`.env.example`](.env.example) to `.env`:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PROMETHEUS_IMAGE_TAG` | `v3.13.1` | Prometheus image (pinned) |
| `GRAFANA_IMAGE_TAG` | `13.1.1` | Grafana image (pinned) |
| `NVIDIA_GPU_EXPORTER_IMAGE_TAG` | `1.13.1` | GPU exporter image (pinned) |
| `PROMETHEUS_HOST_PORT` | `9090` | Host port for Prometheus UI/API |
| `GRAFANA_HOST_PORT` | `3000` | Host port for Grafana |
| `NVIDIA_GPU_EXPORTER_HOST_PORT` | `9835` | Host port for raw `/metrics` |
| `PROMETHEUS_RETENTION` | `15d` | TSDB retention |
| `GRAFANA_ADMIN_USER` / `_PASSWORD` | `admin` / `change-me` in `.env.example` (`admin` if unset) | Grafana login — set a real password |

## Caveats

- **Inference apps are separate.** This project only monitors; start
  Ollama, vLLM, or ComfyUI from their own compose directories when you need
  them. On a single consumer GPU, run **one** heavy inference service at a
  time.
- **GPU access for the exporter** uses the same NVIDIA device reservation
  as the inference stacks (`driver: nvidia`, `capabilities: [gpu]`). Without
  the Container Toolkit, the exporter process starts but
  `nvidia_smi_last_collect_success` stays `0`.
- **node_exporter is not included** — GPU is the main concern. Add it later
  if you want host CPU/RAM/disk.
- Grafana default password is for local use only; change it before exposing
  the port beyond localhost.
