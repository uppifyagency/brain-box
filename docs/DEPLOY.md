# Deploy from zero — Oracle Cloud Free edition

> Field-verified procedure (production box installed green in 5m18s; models download is
> most of the wall time). Total time: **~1 hour** the first time. Cost: **€0/month**.
> Prerequisite reading: [ARCHITECTURE.md](ARCHITECTURE.md) (at least §1–§3).

## 0. What you need

- An **Oracle Cloud Free** account → <https://www.oracle.com/cloud/free/> (credit card
  for identity check, never charged on Always Free resources).
- A **Tailscale** account (free up to 100 devices) → <https://tailscale.com>
- This repo's `box/` folder.
- ~1 hour, half of which is model downloads.

## 1. Create the free VM (Oracle console, click-by-click)

**Is the free tier really enough?** Yes: the Always Free ARM shape is exactly the
production spec of the reference box (4 OCPU / 24 GB), and it never expires.

1. Sign up / log in → <https://cloud.oracle.com>
2. Menu ☰ → **Compute → Instances → Create instance**
3. Parameters that matter (leave the rest default):
   | Field | Value |
   |---|---|
   | Image | **Ubuntu 24.04 LTS** (🔴 exactly 24.04 — on 26.04 the bun runtime is unstable, verified) |
   | Shape | **Ampere `VM.Standard.A1.Flex`** → **4 OCPU / 24 GB RAM** (the full Always Free allotment) |
   | Boot volume | **100–200 GB** (free tier includes 200 GB total block storage) |
   | Networking | create VCN with the wizard → public subnet, assign public IP |
   | SSH keys | upload/paste your public key |
4. Create. If you get "Out of capacity" for A1 (common on free tier): retry at off-peak
   hours or switch Availability Domain — capacity rotates daily.
5. Note the public IP; first login: `ssh ubuntu@<public-ip>`.

## 2. Base setup: Docker + Tailscale, then CLOSE the door

```bash
curl -fsSL https://get.docker.com | sudo sh
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up          # login link → join your tailnet
tailscale ip -4            # note the 100.x.y.z address
```

🔴 **Close the public SSH port immediately** — internet scanners saturate sshd on cloud
IP ranges (this cost the reference deployment a full day of lockout debugging):

```bash
sudo iptables -I INPUT -i ens3 -p tcp --dport 22 -j DROP
sudo apt-get install -y netfilter-persistent iptables-persistent
sudo netfilter-persistent save
```

From now on you administer **only via the tailnet IP**: `ssh ubuntu@100.x.y.z`.
(Oracle side you can also remove the ingress rule for 22 in the VCN security list —
belt and suspenders.)

## 3. Anti-OOM guard-rails (do this BEFORE loading any model)

Large local models + no swap + no memory limit = the kernel kills your SSH session
mid-work. Permanent fixes, cost nothing:

```bash
sudo fallocate -l 8G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

The compose file in the template already ships `mem_limit: 19g` on the ollama service,
`OLLAMA_KEEP_ALIVE=-1` (models stay resident — no 300s cold loads) and
`OLLAMA_MAX_LOADED_MODELS=2`.

## 4. Install the box

```bash
# on the VM:
git clone https://github.com/uppifyagency/brain-box && cd brain-box/box
vi config.yml     # company name, departments, expose (tailnet), llm (byok for local)
./install.sh      # idempotent — green = smoke test passed (drop→ingest→search)
```

`install.sh` in order: generates `.env` (per-instance secrets) → starts ollama and
**pulls bge-m3 first** (ordering matters: an early failed embed puts the backfill in
cooldown) → `compose up` → init → smoke test.

## 5. The local LLM (chat + fact extraction)

Reference model: **`gemma4:26b-a4b-it-qat`** (15 GB, MoE — ~same tok/s as much smaller
dense models on CPU). It is a *reasoning* model: without the no-think patch it "thinks"
for minutes on every call. The patch (F14) is already in the engine Dockerfile; you only
set the env var.

```bash
sudo docker compose exec -T ollama ollama pull gemma4:26b-a4b-it-qat   # 15GB
sudo docker compose exec -T ollama ollama pull glm-ocr                 # 2.2GB (OCR lane, optional)

# .env — add, then `sudo docker compose up -d`:
#   LLM_BASE_URL=http://ollama:11434/v1
#   LLM_API_KEY=local-ollama
#   GBRAIN_CHAT_MODEL=openai:gemma4:26b-a4b-it-qat   ← without this, chat features silently don't exist
#   GBRAIN_CHAT_REASONING_EFFORT=none                ← 🔴 F14: without it every extraction thinks for minutes

sudo docker compose exec -T gbrain gbrain config set models.default openai:gemma4:26b-a4b-it-qat
sudo docker compose exec -T gbrain gbrain config set facts.extraction_model openai:gemma4:26b-a4b-it-qat
```

🔴 **The three-flip rule** (cost the reference team 2 hours of confusion): when changing
the chat model you always flip THREE things — env `GBRAIN_CHAT_MODEL` + DB key
`models.default` + DB key `facts.extraction_model` — then restart gbrain.

🔴 **On a fresh box, disable query expansion** (upstream default breaks full-sentence
questions in some languages — they return empty):

```bash
sudo docker compose exec -T gbrain gbrain config set models.expansion none:off
```

Verify: an MCP `extract_facts` call on a test text must return facts (not `[]`) in
~20–70s. Minutes instead = F14 env var not active in the container.

## 6. Expose (tailnet-only by default)

```bash
sudo tailscale serve --bg --set-path /mcp    http://127.0.0.1:3141/mcp
sudo tailscale serve --bg --set-path /upload http://127.0.0.1:3134/upload
```

🔴 Never `funnel 443` (it would publish the upload endpoint to the whole internet).
Public exposure of `/mcp` (needed only for claude.ai web/mobile) is a deliberate,
separate decision — see ARCHITECTURE §4.8.

## 7. Backup + guardian in cron

```bash
(crontab -l 2>/dev/null; \
 echo "0 3 * * * cd /home/ubuntu/brain-box/box && sudo ./ops/backup.sh >> /home/ubuntu/backup.log 2>&1"; \
 echo "*/15 * * * * cd /home/ubuntu/brain-box/box && GUARDIAN_MODE=observe ./ops/guardian.sh") | crontab -
```

After the first night: (a) verify the backup archive exists AND **drill a restore** on a
scratch database — before handing out tokens, not after; (b) read `~/guardian.log`: if
the night is clean, arm the guardian (`observe` → `act` in the crontab). Never arm it
without having watched it read one night of real state correctly.

## 8. First employee

```bash
# on the box:
sudo ./client-kit/register-employee.sh <name> https://<your-box-hostname>
```

Prints the bearer token + the `claude mcp add` line + drop-folder instructions. On the
employee's Mac (must be in your tailnet):

```bash
cd client-kit/drop-installer
BRAIN_URL="https://<your-box-hostname>" BRAIN_TOKEN="<bearer>" \
BRAIN_EMPLOYEE="<name>" BRAIN_DEPTS="<departments>" BRAIN_AZIENDA="<Company>" ./install-drop.sh
```

A "«Company» Brain" folder appears on their Desktop, with an event-driven watcher
(drop → upload in ~5s).

## 9. Final acceptance (the 5 asserts of a living system)

1. **Drop**: test file into the folder → lands in `Caricati/` within ~10s → page in the
   DB within ~2 min.
2. **Query**: MCP `search` with an employee token finds the test file's marker (by
   keyword ~immediately; semantic questions answer after the end-of-cycle embed).
3. **Security**: `curl` from a public IP on `/upload` must FAIL; `/mcp` without token → 401.
4. **LLM**: `extract_facts` on a text with dates/commitments → correct facts; `think` →
   answer with citations and `modelUsed` = your model.
5. **Restore drill**: `ops/backup.sh` → restore onto a scratch DB → spot-check queries.
   A backup you have never restored is a hope, not a backup.

## Bulk imports (e.g. a PDF library)

Defaults are tuned for daily drip. For thousands of chunks at once, read the bulk-import
section of [ARCHITECTURE.md](ARCHITECTURE.md) first — the short version: embedding
always via CLI with `--catch-up`, `GBRAIN_EMBED_CONCURRENCY=1` stays at 1 on CPU, and a
frozen counter for 60–90 min during a huge page is healthy, not stuck. Budget on the
free ARM shape: ~1,000–1,500 chunks/hour.
