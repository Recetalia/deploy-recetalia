#!/usr/bin/env bash
# Recetalia — deploy remoto vía registry self-hosted
#
# Flujo:
#   1. Sincroniza SÓLO deploy-recetalia/ al server (no los 7 repos de apps;
#      las imágenes llegan vía docker pull desde el registry).
#   2. SSH al server, valida que .env y registry/auth/htpasswd existan.
#   3. docker compose pull + up -d + ps
#
# Prerrequisito: las imágenes ya tienen que estar publicadas en el registry.
# Para publicarlas desde local correr primero `./scripts/build-and-push.sh`.
#
# Uso:
#   ./scripts/deploy.sh user@server [REMOTE_DIR]
#   o: DEPLOY_HOST=user@server ./scripts/deploy.sh

set -euo pipefail

HOST="${1:-${DEPLOY_HOST:-}}"
REMOTE_DIR="${2:-/opt/recetalia}"

if [[ -z "$HOST" ]]; then
  echo "ERROR: indicar host como arg1 o vía DEPLOY_HOST"
  echo "  ./scripts/deploy.sh user@server [/remote/dir]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REMOTE_DEPLOY="$REMOTE_DIR/deploy-recetalia"

echo "==> Preparando $REMOTE_DEPLOY en $HOST"
ssh "$HOST" "mkdir -p '$REMOTE_DEPLOY'"

echo "==> Sincronizando deploy-recetalia (compose, nginx, scripts)"
rsync -az --delete \
  --exclude '.git' \
  --exclude '.env' \
  --exclude 'registry/auth/htpasswd' \
  "$DEPLOY_DIR/" "$HOST:$REMOTE_DEPLOY/"

echo "==> Verificando .env en el server"
ssh "$HOST" "test -f '$REMOTE_DEPLOY/.env'" || {
  echo "ERROR: $REMOTE_DEPLOY/.env no existe."
  echo "       Copiar .env.example y completar antes de reintentar:"
  echo "       ssh $HOST 'cp $REMOTE_DEPLOY/.env.example $REMOTE_DEPLOY/.env && \$EDITOR $REMOTE_DEPLOY/.env'"
  exit 1
}

echo "==> Verificando registry/auth/htpasswd en el server"
ssh "$HOST" "test -f '$REMOTE_DEPLOY/registry/auth/htpasswd'" || {
  echo "ERROR: $REMOTE_DEPLOY/registry/auth/htpasswd no existe."
  echo "       Generar con las instrucciones de registry/README.md."
  exit 1
}

echo "==> docker login al registry self-hosted (desde el server)"
# shellcheck disable=SC2029
ssh "$HOST" "cd '$REMOTE_DEPLOY' && \
  set -a; . ./.env; set +a; \
  echo \"\$REGISTRY_PASSWORD\" | docker login \"\$REGISTRY_HOST\" -u \"\$REGISTRY_USER\" --password-stdin"

echo "==> docker compose pull"
ssh "$HOST" "cd '$REMOTE_DEPLOY' && docker compose pull"

echo "==> docker compose up -d"
ssh "$HOST" "cd '$REMOTE_DEPLOY' && docker compose up -d"

echo "==> Estado"
ssh "$HOST" "cd '$REMOTE_DEPLOY' && docker compose ps"

echo
echo "OK — deploy terminado."
