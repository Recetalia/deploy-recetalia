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
#
# Rol de deploy (DEPLOY_ROLE, default `full`):
#   full → host que además hostea el registry (.98). Levanta el servicio
#          `registry` (COMPOSE_PROFILES=registry) e incluye 30-registry.conf.
#   app  → host sólo de apps (server nuevo 159.203.26.217). NO corre registry:
#          excluye 30-registry.conf y no activa el profile. Pullea desde
#          registrypre.recetadigital.uy (.98).
#   DEPLOY_ROLE=app ./scripts/deploy.sh root@159.203.26.217

set -euo pipefail

HOST="${1:-${DEPLOY_HOST:-}}"
REMOTE_DIR="${2:-/opt/recetalia}"
DEPLOY_ROLE="${DEPLOY_ROLE:-full}"

if [[ -z "$HOST" ]]; then
  echo "ERROR: indicar host como arg1 o vía DEPLOY_HOST"
  echo "  ./scripts/deploy.sh user@server [/remote/dir]"
  exit 1
fi

case "$DEPLOY_ROLE" in
  full)
    COMPOSE_PROFILES_VAL="registry"
    RSYNC_ROLE_EXCLUDES=()
    ;;
  app)
    COMPOSE_PROFILES_VAL=""
    # El server de apps no sirve el registry → no mandes su conf (evita que
    # certbot intente un cert para registrypre, que sigue apuntando a .98).
    # Tampoco el ambiente dev (15-dev.conf + compose dev98 + mysql/), que vive
    # solo en LOCAL (.98).
    RSYNC_ROLE_EXCLUDES=(
      --exclude 'nginx/conf.d/30-registry.conf'
      --exclude 'nginx/conf.d/15-dev.conf'
      --exclude 'docker-compose.dev98.yml'
      --exclude 'mysql/'
    )
    ;;
  *)
    echo "ERROR: DEPLOY_ROLE inválido: '$DEPLOY_ROLE' (usar 'full' o 'app')"
    exit 1
    ;;
esac
echo "==> Rol de deploy: $DEPLOY_ROLE (COMPOSE_PROFILES='$COMPOSE_PROFILES_VAL')"

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
  "${RSYNC_ROLE_EXCLUDES[@]}" \
  "$DEPLOY_DIR/" "$HOST:$REMOTE_DEPLOY/"

# rsync --exclude no borra el archivo si quedó de un deploy previo → borrarlo explícito
if [[ "$DEPLOY_ROLE" == "app" ]]; then
  ssh "$HOST" "rm -f '$REMOTE_DEPLOY/nginx/conf.d/30-registry.conf' '$REMOTE_DEPLOY/nginx/conf.d/15-dev.conf' '$REMOTE_DEPLOY/docker-compose.dev98.yml'"
fi

echo "==> Verificando .env en el server"
ssh "$HOST" "test -f '$REMOTE_DEPLOY/.env'" || {
  echo "ERROR: $REMOTE_DEPLOY/.env no existe."
  echo "       Copiar .env.example y completar antes de reintentar:"
  echo "       ssh $HOST 'cp $REMOTE_DEPLOY/.env.example $REMOTE_DEPLOY/.env && \$EDITOR $REMOTE_DEPLOY/.env'"
  exit 1
}

# htpasswd sólo lo necesita el servicio registry (rol full). El server de apps
# usa REGISTRY_USER/PASSWORD del .env para `docker login`, no el htpasswd.
if [[ "$DEPLOY_ROLE" == "full" ]]; then
  echo "==> Verificando registry/auth/htpasswd en el server"
  ssh "$HOST" "test -f '$REMOTE_DEPLOY/registry/auth/htpasswd'" || {
    echo "ERROR: $REMOTE_DEPLOY/registry/auth/htpasswd no existe."
    echo "       Generar con las instrucciones de registry/README.md."
    exit 1
  }
fi

echo "==> docker login al registry self-hosted (desde el server)"
# shellcheck disable=SC2029
ssh "$HOST" "cd '$REMOTE_DEPLOY' && \
  set -a; . ./.env; set +a; \
  echo \"\$REGISTRY_PASSWORD\" | docker login \"\$REGISTRY_HOST\" -u \"\$REGISTRY_USER\" --password-stdin"

echo "==> docker compose pull"
ssh "$HOST" "cd '$REMOTE_DEPLOY' && COMPOSE_PROFILES='$COMPOSE_PROFILES_VAL' docker compose pull"

echo "==> docker compose up -d"
ssh "$HOST" "cd '$REMOTE_DEPLOY' && COMPOSE_PROFILES='$COMPOSE_PROFILES_VAL' docker compose up -d"

echo "==> Estado"
ssh "$HOST" "cd '$REMOTE_DEPLOY' && COMPOSE_PROFILES='$COMPOSE_PROFILES_VAL' docker compose ps"

echo
echo "OK — deploy terminado."
