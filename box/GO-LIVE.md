# GO-LIVE — runbook (a prova di agent)

## 0. Prerequisiti sul server
- **Ubuntu 24.04 LTS** (il target testato: M0 verde su Oracle A1 in 5m18s). ⚠️ Su Ubuntu
  26.04 il runtime bun è instabile (doctor in core dump, embedding flaky — verificato
  2026-07-02 su VM Lima): non usarlo finché bun/gbrain non lo supportano.
- Docker (Engine su Linux, Desktop su Mac). Tutto il resto arriva dai container.
- [Tailscale](https://tailscale.com/download) sull'host, loggato nel tailnet aziendale (`tailscale up`).
- Dimensione: primo import pesante → 4 vCPU / 8GB / 60GB consigliati; a regime regge meno.

## 1. Configura e installa
```bash
vi config.yml        # azienda, reparti, expose, llm — è l'unico file da toccare
./install.sh         # idempotente: rilanciarlo è sempre sicuro
```
Verde = lo smoke test ha già provato drop→ingest→ricerca. Rosso = leggi l'output,
poi `docker compose logs gbrain ingest`.

## 2. Esponi
```bash
tailscale serve --bg --set-path /mcp    http://127.0.0.1:3141/mcp
tailscale serve --bg --set-path /upload http://127.0.0.1:3134/upload
# SOLO se config.yml ha expose: public (serve a claude.ai — telefono/web):
tailscale funnel --bg --set-path /mcp   http://127.0.0.1:3141/mcp
```
🔴 MAI `tailscale funnel --bg 443`: pubblica l'INTERO sito, quindi anche `/upload`
(verificato 2026-07-02 dal percorso pubblico: il gate rispondeva 401 da internet).
Il funnel va acceso per-path SOLO su `/mcp`; `/upload` resta tailnet-only by design.
Verifica dal pubblico: `curl --resolve <box>.<tailnet>.ts.net:443:<IP-funnel> -X POST
https://<box>.<tailnet>.ts.net/upload` deve FALLIRE (404/timeout), non rispondere 401.
La dashboard admin di gbrain resta raggiungibile solo dal tailnet su `:3141`.
Postgres non è mai esposto.

## 3. Onboarda i dipendenti
```bash
./client-kit/register-employee.sh mario https://<box>.<tailnet>.ts.net
```
Invia a Mario (canale sicuro): la riga `claude mcp add`, e — se vuole la cartella drop —
la cartella `client-kit/drop-installer/` con le sue tre env. Altri agent: `client-kit/CONNETTORI.md`.

## 4. Metti in cron il backup
```bash
crontab -e    # → 0 3 * * * /percorso/brain-box/ops/backup.sh
```
Un backup non testato non è un backup: prova `ops/restore.sh` almeno una volta (M3).

## Trappole note (ereditate e già gestite, non riscoprirle)
1. Il pacchetto **npm `gbrain` è un altro progetto** — l'immagine installa da GitHub, commit pinnato (F4).
2. bge-m3 emette 1024 dim, la ricetta ollama ne dichiara 768 — patchato nel Dockerfile (F3).
3. gbrain ingerisce **solo `.md`** — tutto il resto passa dal converter (F2).
4. Reparto vuoto → saltato (un repo git senza commit rompe `sync --all`) (F5).
5. `gbrain search` da CLI **vuole `--source`** — il path reale dei dipendenti è l'MCP federato.
6. L'embed è **asincrono (~1 min)**: un file appena ingerito non è cercabile all'istante.
7. Il bearer di Claude Code è **full-access sui reparti federati** (F7): prima i backup, poi i token.
8. claude.ai **non raggiunge un endpoint solo-tailnet** (i connector partono dai server Anthropic):
   serve `expose: public` + Funnel.
9. **Bug upstream `op_checkpoints`** (op-checkpoint.ts:189 @ bb2e88c): checkpoint sync scritto
   JSONB doppio-encodato → viola il CHECK → ogni sync dopo il primo muore con
   `checkpoint_unavailable`. `install.sh` droppa il vincolo automaticamente (workaround
   innocuo); da segnalare a github.com/garrytan/gbrain.
10. **Il modello embedding deve esistere PRIMA del primo sync** (con ollama in container):
   altrimenti primo embed fallito → backfill in cooldown → box "sano" ma niente ricerca
   semantica per minuti. `install.sh` ora avvia ollama + pull PRIMA del resto.
11. `gbrain doctor --json` può crashare (core dump) e sotto churn compaiono warning
   "embedder failed to suspend thread": wart upstream, non bloccanti — la verità è lo
   smoke test E2E, non doctor.
12. **SSH e anti-brute-force**: se fai retry aggressivi sulla 22 di un box nuovo puoi
   auto-bloccarti (PerSourcePenalties/MaxStartups). Recovery senza SSH: console cloud →
   **Run Command** (Oracle) o equivalente. Con Tailscale a regime il problema sparisce.

## Comandi rapidi
```bash
docker compose ps                                   # stato
./ops/smoke-test.sh                                 # il brain è vivo?
docker compose exec ingest /ingest/ingest-run.sh    # ingest ORA (senza aspettare i 10 min)
docker compose exec gbrain gbrain doctor            # diagnosi
docker compose logs -f ingest                       # cosa sta ingerendo
```
