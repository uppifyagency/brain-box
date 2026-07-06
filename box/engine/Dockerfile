# Due target da un Dockerfile:
#   engine = bun + gbrain (commit PINNATO, F4) + patch bge-m3 (F3) → serve i container gbrain e gate
#   ingest = engine + python (converter/trascrizione) → il worker
FROM oven/bun:1 AS engine

# git reale: gbrain shella su `git` per i source (senza → "No commits in repo" fuorviante, muro 08)
RUN apt-get update && apt-get install -y --no-install-recommends git curl \
    && rm -rf /var/lib/apt/lists/*

# F4: il pacchetto npm `gbrain` è un ALTRO progetto. Solo github, commit pinnato
# (bb2e88c = commit documentato nel codewiki 2026-07-01, linea v0.42.x validata in 09/10).
# Upgrade = decisione deliberata: cambia l'ARG e rilancia lo smoke test.
ARG GBRAIN_REF=garrytan/gbrain#bb2e88c42a4969e16df7a43a9eb118aa031e89a4
RUN bun install -g "github:${GBRAIN_REF}"

# F3: la ricetta ollama dichiara default_dims 768 FISSO; bge-m3 emette 1024 reali.
# Passare --embedding-dimensions non aggira (whitelist provider): si corregge il default
# della ricetta, così `gbrain init` lo eredita. Il grep fa fallire la build se la patch
# non ha preso (upstream cambiato → rivedere).
RUN sed -i 's/default_dims: 768,.*/default_dims: 1024, \/\/ patch bge-m3 reale (brain-box F3)/' \
      /root/.bun/install/global/node_modules/gbrain/src/core/ai/recipes/ollama.ts \
    && grep -q 'default_dims: 1024' /root/.bun/install/global/node_modules/gbrain/src/core/ai/recipes/ollama.ts

# F11: `no_batch_cap: true` manda TUTTI i chunk di una pagina in UNA richiesta; su CPU-only
# supera il timeout fisso (~300s) del fetch di Bun → il client abbandona, ollama resta a
# macinare batch-zombie, l'embedding non committa MAI su corpus grossi.
# Cap a 8k: la stima del batcher è in CARATTERI (~4/token); i chunk di CODICE hanno ~2
# caratteri/token → un "24k token" stimato = ~50k reali = ancora oltre il timeout (wedge
# ricorso il 2026-07-03 notte sulle 15 pagine code-dense). A 8k anche il batch peggiore
# resta <60s. GBRAIN_AI_EMBED_TIMEOUT_MS NON esiste upstream: no-op.
RUN sed -i 's/no_batch_cap: true,/max_batch_tokens: 8000, \/\/ patch CPU-only (brain-box F11)/' \
      /root/.bun/install/global/node_modules/gbrain/src/core/ai/recipes/ollama.ts \
    && grep -q 'max_batch_tokens: 8000' /root/.bun/install/global/node_modules/gbrain/src/core/ai/recipes/ollama.ts

# F14: i gemma4 thinking (26B-A4B) pensano di default su OGNI endpoint OpenAI-compat di
# ollama e il pensiero su CPU moltiplica i token → estrazioni C2 oltre il timeout
# (misurato 04-07: 59s vs 13s warm sullo stesso prompt via /v1/responses). L'AI SDK v6
# di gbrain parla /v1/responses (verificato nei log GIN): la leva è reasoning.effort
# annidato; si inietta ANCHE reasoning_effort flat per l'eventuale ritorno a
# /v1/chat/completions (i campi ignoti ollama li ignora). Fetch-wrapper env-gated sui
# DUE call-site createOpenAI (chat + expansion): attivo SOLO se
# GBRAIN_CHAT_REASONING_EFFORT è settata, altrimenti upstream puro. Guard: 2 hit esatti.
RUN sed -i 's|return createOpenAI({ apiKey }).languageModel(modelId);|return createOpenAI({ apiKey, ...(process.env.GBRAIN_CHAT_REASONING_EFFORT ? { fetch: (async (u, i) => { try { const b = JSON.parse(i.body); b.reasoning = { effort: process.env.GBRAIN_CHAT_REASONING_EFFORT }; b.reasoning_effort = process.env.GBRAIN_CHAT_REASONING_EFFORT; i = { ...i, body: JSON.stringify(b) }; } catch (e) {} return fetch(u, i); }) } : {}) }).languageModel(modelId); // patch F14 no-think opzionale (brain-box)|g' \
      /root/.bun/install/global/node_modules/gbrain/src/core/ai/gateway.ts \
    && [ "$(grep -c 'patch F14' /root/.bun/install/global/node_modules/gbrain/src/core/ai/gateway.ts)" = "2" ]

ENV HOME=/root
ENV GBRAIN_HOME=/data/gbrain
EXPOSE 3131
COPY engine/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]


FROM engine AS ingest
# Converter (PDF/DOCX/XLSX/PPTX/HTML/RTF) + trascrizione A/V.
# NIENTE ffmpeg di sistema: faster-whisper decodifica via PyAV (librerie incluse) — verificato 09.
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip inotify-tools \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install --no-cache-dir --break-system-packages \
      pymupdf python-docx openpyxl python-pptx striprtf faster-whisper

# git dentro il container sui bind-mount dell'host: senza safe.directory scatta
# "dubious ownership" e il commit per-reparto (F5) fallisce.
RUN git config --global --add safe.directory '*' \
    && git config --global user.email brain@box.local \
    && git config --global user.name brain-box

# gli script /ingest arrivano via bind-mount (iterazione senza rebuild)
ENTRYPOINT ["/ingest/ingest-loop.sh"]
