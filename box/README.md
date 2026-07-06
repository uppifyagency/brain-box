# brain-box — il brain aziendale in una cartella

> Installazione passo-passo: **[GO-LIVE.md](GO-LIVE.md)**. Architettura e decisioni: [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md).

Copi questa cartella su un server (VM cloud o macchina del cliente), `./install.sh`,
e nasce un brain aziendale: i dipendenti droppano file in una cartella sul Desktop
e interrogano il brain dal loro Claude/Codex/Gemini, con risposte citate.

```
dipendente                          box (questa cartella, via Docker)
─ Desktop/Azienda Brain/ ─watcher─▶ gate :3134 ─▶ inbox/ ─▶ ingest (10 min):
─ Claude/Codex/Gemini ────MCP────▶ gbrain :3141 /mcp        convert → brain/ → sync → embed
                (tutto via Tailscale; claude.ai richiede Funnel)
```

| Pezzo | Cosa fa |
|---|---|
| `install.sh` | l'unico comando: segreti → up → health → smoke test |
| `config.yml` | l'unica cosa da toccare: azienda, reparti, expose, llm |
| `engine/` | immagine gbrain (commit pinnato F4, patch bge-m3 F3) |
| `gate/` | upload-gate: ingresso file col token del dipendente |
| `ingest/` | inbox → convert/transcribe → brain repo → sync → embed → extract |
| `brain/` | ⭐ i markdown per reparto (system of record, un repo git per reparto) |
| `inbox/` | dove atterrano i file da convertire (gate remoto o scp admin) |
| `client-kit/` | register-employee, installer cartella drop, ricette connettori |
| `ops/` | smoke-test, backup, restore |

Replica per un nuovo cliente = copia questa cartella (pulita, senza `brain/`/`.env`) e
`./install.sh` sulla sua macchina: i segreti nascono lì, mai condivisi. Migrazione =
`ops/backup.sh` di qua, `ops/restore.sh` di là.
