#!/bin/bash
# Genera il BUNDLE OFFLINE del brain-box: tutto ciò che serve per installare su un server
# SENZA internet (aria-gapped o rete lenta). Da lanciare su un box già installato e verde.
#
# uso:  ./ops/make-offline-bundle.sh [dest-dir]        (default: ./offline-bundle)
# poi:  copia la cartella su una chiavetta/scp → sul server nuovo: ./install-offline.sh
#
# Contenuto: template pulito (25KB) + immagini docker salvate + modelli ollama esportati.
# Dimensioni attese: ~15GB (gemma4:e4b 9.6 + glm-ocr 2.2 + bge-m3 1.2 + immagini ~2).
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${1:-./offline-bundle}"
mkdir -p "$DEST"/{images,ollama-models}

echo "── 1/3 template pulito (senza segreti/dati) ──"
rsync -a --exclude '.env' --exclude 'brain/' --exclude 'inbox/' --exclude 'backups/' \
      --exclude 'offline-bundle/' ./ "$DEST/brain-box/"

echo "── 2/3 immagini docker (postgres, engine, ingest, ollama) ──"
docker save pgvector/pgvector:pg16        -o "$DEST/images/postgres.tar"
docker save brain-box-engine              -o "$DEST/images/engine.tar"
docker save brain-box-ingest              -o "$DEST/images/ingest.tar"
docker save ollama/ollama:latest          -o "$DEST/images/ollama.tar"

echo "── 3/3 modelli ollama (blob + manifest dal volume) ──"
# i modelli vivono nel volume ollama-models: si copiano i file, non serve l'API
OLLAMA_VOL=$(docker volume inspect brain-box_ollama-models -f '{{.Mountpoint}}')
sudo rsync -a "$OLLAMA_VOL/models/" "$DEST/ollama-models/"
sudo chown -R "$(id -u):$(id -g)" "$DEST/ollama-models"

cat > "$DEST/install-offline.sh" <<'EOF'
#!/bin/bash
# Installa il brain-box SENZA internet, dal bundle. Prerequisiti sul server:
# Ubuntu 24.04 + Docker + (Tailscale, se si vuole l'esposizione — richiede rete).
set -euo pipefail
cd "$(dirname "$0")"
echo "── carico le immagini docker ──"
for t in images/*.tar; do docker load -i "$t"; done
echo "── preparo il box ──"
cp -r brain-box "$HOME/brain-box"
cd "$HOME/brain-box"
echo "── pre-carico i modelli ollama nel volume ──"
docker volume create brain-box_ollama-models >/dev/null
VOL=$(docker volume inspect brain-box_ollama-models -f '{{.Mountpoint}}')
sudo mkdir -p "$VOL/models" && sudo rsync -a "$OLDPWD/ollama-models/" "$VOL/models/"
echo "── install (userà immagini e modelli locali, niente download) ──"
./install.sh
EOF
chmod +x "$DEST/install-offline.sh"

echo
echo "✅ Bundle offline in: $DEST  ($(du -sh "$DEST" | cut -f1))"
echo "   Sul server nuovo: copia la cartella e lancia ./install-offline.sh"
# ponytail: niente checksum/firma — se serve integrità sul trasporto, tar+sha256sum a mano.
