# Brain Box — a self-hosted AI company brain that costs €0/month

**Brain Box turns a free Oracle Cloud VM into a private, drag-and-drop company knowledge base your team queries in plain language from Claude Code, Codex or Gemini CLI — and no byte of your data ever leaves your server.**

Employees drop files (PDF, Word, Excel, scans, photos of invoices, audio, video) into a folder on their Desktop. ~75 seconds later the content is converted, versioned in git, embedded and queryable via [MCP](https://modelcontextprotocol.io) with cited answers. A local LLM (Gemma, via Ollama) extracts facts and reasons over your documents — on your hardware.

This is not a demo. It is the production template of a real company brain: **~8,250 chunks, 54 business books, 10 file formats, nightly self-testing, self-healing, verified backup restore — running 24/7 on Oracle Cloud's Always Free tier.**

```
employee's Mac                        your VM (Ubuntu 24.04 + Docker + Tailscale)
─ Desktop/"Company Brain"/ ─watcher─▶ upload gate ─▶ ingest: convert → git → embed
─ Claude Code / Codex ───────MCP────▶ gbrain /mcp ◀──▶ Postgres + pgvector
                                      └─ Ollama: bge-m3 · gemma (chat) · glm-ocr
                     (all traffic inside your private Tailscale network)
```

## Why would I self-host a company brain?

**Because your contracts, financials and meeting notes should not train someone else's model — and because it can be free.** Brain Box runs entirely on one VM: retrieval, embeddings, OCR, transcription and the reasoning LLM are all local. The Oracle Cloud Always Free ARM shape (4 OCPU / 24 GB RAM) runs the whole stack at €0/month, forever.

| | SaaS knowledge base | Brain Box |
|---|---|---|
| Monthly cost | €20–50 per seat | **€0** (Oracle Free tier) |
| Your data | on their servers | **on your VM, in git** |
| LLM | theirs, cloud | **local Gemma via Ollama** |
| Access | web app | **your AI agent, via MCP** |
| Formats | usually text | **10 formats incl. scans, images, audio/video** |
| Exit strategy | export and pray | **`brain/` is plain markdown in git** |

## How does it work?

**One folder in, one connector out.** The system of record is `brain/<department>/` — plain markdown in git. Postgres+pgvector is a derived cache you can always rebuild.

1. **Drop** — a launchd watcher uploads new files to the gate (bearer token per employee, department folders enforce access). Measured: drop → queryable in ~75s.
2. **Ingest** — files convert to markdown (PyMuPDF, per-page OCR lane with glm-ocr for scans, faster-whisper for audio/video), get provenance frontmatter, git commit, embed with bge-m3.
3. **Query** — agents connect via MCP (`/mcp`, bearer auth). Hybrid search (vector + keyword), answers cite sources. Fact extraction with a local Gemma runs automatically after ingest (~23s/doc with the no-think patch).
4. **Self-defense** — nightly acceptance suite (6 end-to-end tests), a deterministic guardian (cron */15) that heals known failures, nightly backups with a **restore script that has actually been drilled**.

## Quickstart — what do I need?

**A free Oracle Cloud account, a free Tailscale account, and ~1 hour.** Full click-by-click guide (VM shape, network, every parameter): **[docs/DEPLOY.md](docs/DEPLOY.md)** · 🇮🇹 [Guida in italiano](docs/it/GUIDA-RAPIDA.md)

```bash
# on the VM (Ubuntu 24.04 LTS — 24.04 exactly, see docs):
git clone https://github.com/uppifyagency/brain-box && cd brain-box/box
vi config.yml     # company name, departments, exposure, llm
./install.sh      # idempotent: secrets → containers → models → smoke test
```

Then register employees (`client-kit/register-employee.sh`), install the drop folder on their Mac (`client-kit/drop-installer/`), and add the MCP connector to their agent:

```bash
claude mcp add brain -s user --transport http "https://<your-box>/mcp" \
  --header "Authorization: Bearer <employee-token>"
```

## What's in the box?

| Path | What it does |
|---|---|
| [`box/`](box/) | **the deployable template** (~25 KB): `install.sh`, compose, engine patches, gate, ingest pipeline, ops |
| [`box/ops/`](box/ops/) | backup + drilled restore, guardian (self-healing), nightly acceptance runner, offline-bundle builder |
| [`box/client-kit/`](box/client-kit/) | employee registration, Desktop drop-folder installer (macOS), connector recipes |
| [`docs/DEPLOY.md`](docs/DEPLOY.md) | deploy from zero on Oracle Cloud Free — every step, every parameter |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | topology, data flows with measured latencies, every tunable, hard-won troubleshooting table |
| [`landing/`](landing/) | the project's landing page (static, Vercel-ready) |

The engine is [gbrain](https://github.com/garrytan/gbrain) (MIT), pinned to a verified commit and patched in the Dockerfile for CPU-only operation (embedding batch caps, concurrency, optional no-think mode for reasoning models — each patch documented in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)). We have filed our findings upstream as issues #2552–#2557.

## Frequently asked questions

### Is it really free?
Yes — Oracle Cloud's Always Free tier includes an ARM VM (`VM.Standard.A1.Flex`, up to 4 OCPU / 24 GB / 200 GB disk) that never expires. Tailscale is free up to 100 devices. The models (bge-m3, Gemma, glm-ocr) are open weights running on your VM. Your only real cost is the hour it takes to deploy.

### Is my data safe?
Your data lives in markdown in git on your VM, reachable only inside your private Tailscale network (the public SSH port gets closed during setup; the upload gate and MCP endpoint are tailnet-only by default). The local LLM means documents are never sent to a cloud model. Every access goes through a per-employee bearer token with department-level permissions.

### What hardware does it need?
4 vCPU / 24 GB RAM / 60+ GB disk recommended — exactly the free Oracle ARM shape. It runs fine on CPU only: embeddings ~2.4s/chunk, OCR 6–9s/page warm, fact extraction ~23s/doc. Any Ubuntu 24.04 box (a Mac mini in the office, a Hetzner VM) works the same.

### Which AI agents can query it?
Anything that speaks MCP over HTTP with bearer auth: Claude Code, claude.ai (with public exposure enabled), Codex CLI, Gemini CLI. Recipes in `box/client-kit/CONNETTORI.md`.

### Italian comments in the code?
Yes — Brain Box was born inside [Delera](https://delera.it) (Italian company) and this repo *is* the production template, not a cleaned-up copy. Runbooks and inline comments are in Italian; the docs in `docs/` are English. Authenticity over polish.

## License

MIT — © [Uppify](https://github.com/uppifyagency). Engine: [gbrain](https://github.com/garrytan/gbrain) (MIT, by its authors).
