#!/bin/sh
set -e
# `gbrain init --force` su Postgres è il pattern IDEMPOTENTE (verificato 08/09,
# docs/operations/headless-install.md Pattern 2): riesegue le migrazioni, NON tocca i dati.
# Il modello embedding è esplicito (F3); le dimensioni 1024 arrivano dalla ricetta patchata.
gbrain init --url "$DATABASE_URL" --non-interactive --force --embedding-model ollama:bge-m3

gbrain config set search.mode conservative || true

exec gbrain serve --http --port 3131 --bind 0.0.0.0 --public-url "$GBRAIN_PUBLIC_URL"
