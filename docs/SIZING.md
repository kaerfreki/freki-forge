# Sizing guide

How to pick models, context windows, and runtimes on a single consumer GPU —
driven by the numbers measured in this repository, not by vendor marketing.

All figures below come from the published harnesses on one host. Your card
will differ; treat these as calibrated baselines, not universal constants.

## Hardware baseline

Published measurements were taken on:

| Component | Spec |
| --- | --- |
| GPU | NVIDIA GeForce **RTX 4080**, **16376 MiB** (driver 595.71.05) |
| CPU | AMD Ryzen 5 7600X 6-Core |
| RAM | ~30–31 GB |
| OS | Ubuntu 26.04 LTS |
| Runtimes | Ollama **0.31.1**, vLLM image **`v0.25.0`**, ComfyUI **0.27.0** |

Dates: Ollama matrix **2026-07-05**; context sweep and vLLM matrix
**2026-07-12**; image matrix **2026-07-07**. Raw CSVs live under
[`benchmarks/raw/`](../benchmarks/raw/).

VRAM peaks include a **small desktop baseline** (often ~2 GB already in use).
When you size for a headless box, you may reclaim that margin; when you size
for a daily-driver workstation, leave it.

---

## Pick a text model for this card

Short-prompt generation on Ollama (256 tokens out). Medians; full tables in
[`benchmarks/RESULTS.md`](../benchmarks/RESULTS.md).

| Model | VRAM peak | Generation | When to use |
| --- | ---: | ---: | --- |
| `qwen3.5:4b` | 6955 MiB | **137.9 tok/s** | **Speed default.** Snappy chat, classification, light coding. Leaves the most headroom for desktop + KV growth. |
| `mistral:7b` | 7971 MiB | **112.3 tok/s** | Strong general 7B; slightly slower cold load than the Qwen 4B. |
| `llama3.1:8b` | 8198 MiB | **103.4 tok/s** | Ecosystem familiarity; solid mid-pack throughput. |
| `ornith:9b` | 8244 MiB | **86.1 tok/s** | **OpenCode / agentic coding.** Ornith is a Qwen3.5-family fine-tune for agent workflows — use this (with a raised `num_ctx`) as the agent default, not stock `qwen3.5:9b`. |
| `qwen3.5:9b` | 9565 MiB | **85.6 tok/s** | General 9B quality step up from 4B when you do not need the agent fine-tune. |
| `gemma3:12b` | 12410 MiB | **70.9 tok/s** | Fits fully on GPU; less room for long context or a second process. |
| `qwen3.5:9b-q8_0` | 13144 MiB | **56.5 tok/s** | **Quality ceiling on this card** for the Qwen 9B line (Q8 vs Q4_K_M). ~3 GB of free VRAM at peak — tight for large KV; see caveats below. |
| `qwen3.6:35b` | 15878 MiB | **57.2 tok/s** | **Avoid for interactive agents on 16 GB.** Ollama places it **51% GPU / 49% CPU**. Generation rate looks almost competitive with Q8 9B, but prefill collapses (~1062 tok/s vs ~4–7k on full-GPU models), cold load is **32.9 s**, and TTFT on long prompts jumps to **1.4 s**. |

**Practical picks on an RTX 4080 16 GB**

1. **OpenCode / coding agents** → `ornith:9b` with `num_ctx` 32768 (see
   [Context window sizing](#context-window-sizing-ornith--opencode)).
2. **Fast interactive use** → `qwen3.5:4b`.
3. **Best weights that still sit fully on GPU with a little margin** →
   `qwen3.5:9b-q8_0`, knowing generation is ~56 tok/s and VRAM is near the
   ceiling; do not also raise context aggressively or co-run ComfyUI.
4. **Do not default agents to `qwen3.6:35b` on this card** — the CPU offload
   tax shows up as slow prefill and multi-second cold starts, not as a
   free “bigger model.”

Quality is intentionally **not scored** here. Side-by-side unedited samples
for every Ollama model live in [`benchmarks/outputs/`](../benchmarks/outputs/).

---

## Context window sizing (ornith / OpenCode)

`ornith:9b` reports a native context length of **262144**, but Ollama only
**reserves** KV for `options.num_ctx` (or a Modelfile `PARAMETER num_ctx`).
The server default is far smaller than the GGUF allows — long OpenCode
sessions hit the wall even though the weights could go further.

Sweep on the same RTX 4080 host
([`benchmarks/RESULTS-ctx.md`](../benchmarks/RESULTS-ctx.md)):

### Short generation (KV reserved, short prompt)

| num_ctx | VRAM peak | Generation |
| ---: | ---: | ---: |
| 2048 | 7564 MiB | 95.0 tok/s |
| 16384 | 8135 MiB | 94.5 tok/s |
| **32768** | **8701 MiB** | **94.5 tok/s** |
| 65536 | 9573 MiB | 95.8 tok/s |
| 131072 | 11750 MiB | 94.7 tok/s |

Generation throughput barely moves with `num_ctx` when the prompt is short.
What grows is **reserved VRAM** and, more importantly, **prefill cost** when
you actually fill the window.

### Prefill (~0.75 × num_ctx tokens in, 32 out)

| num_ctx | Prompt tokens | TTFT | Prompt processing | Generation | VRAM peak |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 16384 | ~10k | 2.2 s | 5862 tok/s | 92.5 tok/s | 8134 MiB |
| **32768** | **~21k** | **4.2 s** | **5727 tok/s** | **89.2 tok/s** | **8709 MiB** |
| 65536 | ~41k | 8.6 s | 5366 tok/s | 81.5 tok/s | 9627 MiB |
| 131072 | ~83k | **20.0 s** | 4476 tok/s | 69.3 tok/s | 11792 MiB |

### Recommendations

| Setting | Recommendation |
| --- | --- |
| **Default for OpenCode** | **`num_ctx` 32768** — ~8.7 GB VRAM, generation still ~90–95 tok/s, prefill of a three-quarter-full window ~4 s. Comfortable headroom on 16 GB. |
| **64k** | Use when sessions routinely exceed ~24k tokens of working context. +~0.9 GB VRAM vs 32k; prefill ~8.5 s at 75% fill. Still full-GPU. |
| **128k** | Only when you need it. ~11.8 GB peak; ~20 s to first token on a large prefill; generation under load drops toward ~70 tok/s. Leave **no** room for image gen or a second LLM stack. |
| **Beyond 128k** | Not measured here. You would be betting remaining VRAM against desktop + KV; prefer another host or a larger card. |

Persist 32k for every client (including OpenCode):

```bash
cat > /tmp/Modelfile.ornith-32k <<'EOF'
FROM ornith:9b
PARAMETER num_ctx 32768
EOF
ollama create ornith-32k -f /tmp/Modelfile.ornith-32k
# point OpenCode at model ornith-32k
```

Or pass `"options": { "num_ctx": 32768 }` per request.

---

## Ollama vs vLLM on this hardware

README rule of thumb still holds: **Ollama** for local dev, model hopping,
and single-user work; **vLLM** when you want a stable OpenAI-compatible
endpoint and continuous batching under concurrent clients. On this
particular card, single-stream numbers add nuance.

Pairing is by **model family and bit-width class** (GGUF Q4_K_M ↔ AWQ ~4-bit),
not identical bytes — see
[`benchmarks/MODEL-MAP-vllm.md`](../benchmarks/MODEL-MAP-vllm.md).

### Single-stream generation (short prompt, 256 out)

| Family | Ollama (tok/s) | vLLM (tok/s) | Ollama VRAM | vLLM VRAM |
| --- | ---: | ---: | ---: | ---: |
| Qwen3.5 4B | **137.9** | 53.3 | 6955 MiB | 14361 MiB |
| Mistral 7B | 112.3 | **126.8** | 7971 MiB | 15087 MiB |
| Llama 3.1 8B | 103.4 | **115.0** | 8198 MiB | 15539 MiB |
| Ornith 9B | **86.1** | 55.6 | 8244 MiB | 14089 MiB |
| Qwen3.5 9B | **85.6** | 53.2 | 9565 MiB | 14096 MiB |

Sources: [`RESULTS.md`](../benchmarks/RESULTS.md),
[`RESULTS-vllm.md`](../benchmarks/RESULTS-vllm.md).

### How to read that table honestly

- **Classic dense instruct models (Mistral, Llama)** — vLLM wins slightly on
  single-stream generation and often on TTFT. Under concurrent load (not
  measured as multi-client in the current harness), continuous batching is
  the reason to prefer vLLM.
- **Qwen3.5 / Ornith AWQ on this compose profile** — Ollama is **clearly
  faster** for single-stream use. The vLLM service runs with
  `--enforce-eager` (no CUDA graphs) so multimodal Qwen3.5 AWQ fits a 16 GB
  card next to a desktop session; that is a real single-stream cost, not a
  measurement artifact. Cold load is also much heavier on vLLM (tens of
  seconds to `/health` vs a few seconds on first Ollama request).
- **VRAM accounting differs.** Ollama grows with demand. vLLM pre-allocates
  a KV pool up to `gpu-memory-utilization` (0.80 here), so peaks sit near
  the card limit even for small models. That is expected.
- **Rows that do not fit vLLM on this host:** `qwen3.5:9b-q8_0` FP8
  multimodal OOM; Gemma 12B is tight and omitted from the default matrix;
  35B is not served (Ollama already CPU-offloads ~half).

**When each wins on an RTX 4080 16 GB**

| Choose | If you need |
| --- | --- |
| **Ollama** | OpenCode + `ornith:9b`, multi-model experimentation, Qwen3.5 family at best single-stream speed, CPU offload as a last resort, simple ops. |
| **vLLM** | One pinned model, OpenAI clients, concurrent users, Mistral/Llama-class AWQ where single-stream already matches or beats Ollama. |

Do not co-run both stacks on the same 16 GB card — see
[One GPU rule](#one-gpu-rule).

---

## Image generation (ComfyUI)

1024×1024, each checkpoint at its own usual steps/CFG
([`benchmarks/RESULTS-images.md`](../benchmarks/RESULTS-images.md)):

| Checkpoint | Steps | Time / image | VRAM peak | Role |
| --- | ---: | ---: | ---: | --- |
| SDXL Base 1.0 | 25 | **5.4 s** | **10352 MiB** | Reliable default; most headroom left on the card. |
| FLUX.1-schnell (fp8) | 4 | **4.1 s** | **15439 MiB** | Fastest wall-clock here; near-full VRAM. |
| FLUX.1-dev (fp8) | 50 | **46.1 s** | **15458 MiB** | Quality ceiling comparison; ~11× slower than schnell. |

Host RAM peaks were ~25–26 GB during these runs — plan system memory, not
only VRAM.

**Licensing:** SDXL Base 1.0 (CreativeML Open RAIL++-M) and FLUX.1-schnell
(Apache 2.0) are commercially permissive. **FLUX.1-dev weights are
non-commercial** without a paid license from Black Forest Labs; output
images are separately allowed for commercial use. Treat dev as a quality
reference on this stack unless you have that license.

As with text models, image quality is not scored; unedited galleries are in
[`benchmarks/outputs/images.md`](../benchmarks/outputs/images.md).

---

## One GPU rule

Ollama, vLLM, and ComfyUI are **independent** compose/Kustomize projects.
Each can claim the full GPU. On a **16 GB** card:

- Do **not** co-schedule Ollama + vLLM + ComfyUI (or even two of them under
  load). FLUX alone peaks above **15 GB**; vLLM pre-allocates most of the
  card; a 9B Ollama model plus a large `num_ctx` already sits in the 8–12 GB
  band.
- The benchmark harnesses stop sibling freki services before measuring so
  peaks stay honest — do the same in production: **one heavy GPU tenant at
  a time**.
- On multi-GPU or multi-node setups, pin each service to its own device
  (Kubernetes GPU requests already encode this intent).

---

## Headroom

| Budget item | Guidance on this host |
| --- | --- |
| Desktop / display stack | Plan ~**2 GB** already used when measuring on a workstation. |
| Ollama KV growth | `num_ctx` reserves cache up front; 32k → 64k → 128k on ornith adds roughly **0.9 / 2.2 / +… GB** over a small window (see ctx table). |
| vLLM | `gpu-memory-utilization=0.80` intentionally leaves ~20% for the desktop and fragmentation; raising it is how you OOM next to a GUI session. |
| Q8 / large models | `qwen3.5:9b-q8_0` at **13144 MiB** leaves little margin — avoid stacking image gen or a second runtime. |
| Agents | Prefer full-GPU models (`ornith:9b`, ≤9B Q4) so tool-loop prefill stays in the multi-k tok/s range, not the ~1k tok/s of CPU-offloaded 35B. |

If a model only fits by offloading half the weights to CPU, treat that as a
**last resort for batch jobs**, not as your interactive or agent default.

---

## Raw results and method

| Document | What it measures |
| --- | --- |
| [`benchmarks/RESULTS.md`](../benchmarks/RESULTS.md) | Ollama model matrix — VRAM, TTFT, gen/prefill tok/s |
| [`benchmarks/RESULTS-ctx.md`](../benchmarks/RESULTS-ctx.md) | `ornith:9b` `num_ctx` sweep |
| [`benchmarks/RESULTS-vllm.md`](../benchmarks/RESULTS-vllm.md) | vLLM counterparts, same prompts |
| [`benchmarks/MODEL-MAP-vllm.md`](../benchmarks/MODEL-MAP-vllm.md) | Ollama tag ↔ Hugging Face id |
| [`benchmarks/RESULTS-images.md`](../benchmarks/RESULTS-images.md) | ComfyUI SDXL / FLUX timing and VRAM |
| [`benchmarks/outputs/`](../benchmarks/outputs/) | Unedited text and image samples (no quality scores) |

Harnesses report **medians** of three measured runs after one warm-up;
token rates and TTFT are client-side on the same host. Re-run with
`scripts/bench.sh`, `bench-ctx.sh`, `bench-vllm.sh`, and `bench-images.sh`
if your driver, image tags, or GPU differ.
