# Guida rapida in italiano — il cervello aziendale a €0/mese

> Brain Box trasforma una VM gratuita di Oracle Cloud in un **cervello aziendale
> privato**: i dipendenti trascinano file in una cartella sul Desktop e interrogano la
> conoscenza in italiano da Claude Code — e nessun dato esce mai dal vostro server.
> Questa è la versione breve: la guida completa passo-passo (in inglese, con ogni
> parametro) è **[docs/DEPLOY.md](../DEPLOY.md)**.

## Cosa serve
- Account **Oracle Cloud Free** (<https://www.oracle.com/cloud/free/>) — la fascia
  Always Free include una VM ARM 4 OCPU / 24 GB che non scade mai. Costo: zero.
- Account **Tailscale** gratuito (<https://tailscale.com>) — la rete privata.
- ~1 ora, metà della quale è download di modelli.

## I 7 passi

1. **Crea la VM**: console Oracle → Compute → Create instance → immagine
   **Ubuntu 24.04 LTS** (proprio 24.04: su 26.04 il runtime è instabile), shape
   **VM.Standard.A1.Flex 4 OCPU / 24 GB**, boot volume 100-200 GB, subnet pubblica.
   Se dice "out of capacity": riprova in orari morti o cambia Availability Domain.

2. **Docker + Tailscale** sulla VM, poi **chiudi subito la porta 22 pubblica**
   (gli scanner sui range cloud sono spietati) — comandi esatti in DEPLOY.md §2.
   Da lì amministri solo via IP tailnet.

3. **Guard-rail anti-crash**: swapfile 8G (il compose ha già mem_limit e keep-alive
   giusti) — DEPLOY.md §3.

4. **Installa il box**:
   ```bash
   git clone https://github.com/uppifyagency/brain-box && cd brain-box/box
   vi config.yml     # nome azienda, reparti, esposizione, llm
   ./install.sh      # verde = smoke test passato
   ```

5. **Modello locale** (chat + estrazione fatti): pull di `gemma4:26b-a4b-it-qat`
   + le 2 variabili in `.env` (`GBRAIN_CHAT_MODEL`, `GBRAIN_CHAT_REASONING_EFFORT=none`)
   + le 2 chiavi DB. 🔴 In italiano è FONDAMENTALE anche spegnere l'espansione query
   (`gbrain config set models.expansion none:off`): senza, le domande intere in
   italiano tornano vuote. Tutto in DEPLOY.md §5.

6. **Backup + guardian in cron**, e dopo la prima notte: **prova un restore** su un
   DB di scarto prima di distribuire i token. DEPLOY.md §7.

7. **Primo dipendente**: `register-employee.sh` sul box stampa token e istruzioni;
   sul suo Mac l'installer crea la cartella "«Azienda» Brain" sul Desktop. Il
   connettore per Claude Code è una riga di `claude mcp add`. DEPLOY.md §8.

## Cosa ottieni

- **Cartella drop sul Desktop** per ogni dipendente, per reparto, con permessi per
  token: PDF (anche scansionati), Word, Excel, foto di fatture, audio e video
  (trascritti). Drop → interrogabile in ~75 secondi.
- **Risposte citate in italiano** da Claude Code / Codex / Gemini via MCP.
- **Fatti estratti automaticamente** dai documenti operativi (LLM locale, ~23s/doc).
- **Sistema che si sorveglia da solo**: suite di test notturna, guardian che cura i
  guasti noti, backup con restore collaudato.
- **Zero lock-in**: la conoscenza è markdown in git (`brain/`), il database si
  ricostruisce sempre.

Domande, problemi, storie di deploy → apri una issue sul repo.
