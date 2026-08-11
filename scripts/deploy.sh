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
    # solo en LOCAL (.98), ni 11-qf.conf: sus server_name son qfpre.* y resuelven
    # al .98, así que certbot pediría certs que no puede validar desde acá. En prod
    # la app QF se sirve por 51-prod-qf.conf (qf.recetalia.com, cert propio).
    RSYNC_ROLE_EXCLUDES=(
      --exclude 'nginx/conf.d/30-registry.conf'
      --exclude 'nginx/conf.d/15-dev.conf'
      --exclude 'nginx/conf.d/11-qf.conf'
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

# El server acumula estado que el repo no conoce, y `--delete` lo borra sin avisar.
# Medido con un dry-run contra el .98 el 2026-08-10: iba a borrar 14 archivos, TODOS
# valiosos — los 5 backups del .env (incluido el que es la red de seguridad si el deploy
# rompe el stack), los 4 dumps de MySQL, un backup viejo de conf.d, y los dos vhosts de
# doctorconsultas/doctorsuite, que sirven 13 hostnames de OTRO producto detrás del mismo
# nginx. Se mantiene `--delete` (si no, un .conf renombrado queda vivo y nginx lo sigue
# sirviendo), pero con estas exclusiones y con el aviso de más abajo.
RSYNC_KEEP_EXCLUDES=(
  --exclude '.git'
  --exclude '.env'            # + los .env.bak-*, por el patrón de abajo
  --exclude '.env.bak*'
  --exclude 'registry/auth/htpasswd'
  --exclude 'mysql/dump_*'    # dumps hechos en el server; `mysql/initdb/` sí se sincroniza
  --exclude '*.bak-*'         # nginx/conf.d.bak-YYYY-MM-DD y similares
  # Vhosts de otros productos que comparten este nginx. No viven en este repo.
  --exclude 'nginx/conf.d/40-doctorconsultas.conf'
  --exclude 'nginx/conf.d/40-doctorsuite.conf'
)

echo "==> Sincronizando deploy-recetalia (compose, nginx, scripts)"

# Preview de borrados. Cualquier cosa que aparezca acá y no se esperara es una señal de
# que el server tiene estado nuevo que el repo no conoce: frenar y mirarlo.
DELETIONS="$(rsync -az --delete --dry-run --itemize-changes \
  "${RSYNC_KEEP_EXCLUDES[@]}" "${RSYNC_ROLE_EXCLUDES[@]}" \
  "$DEPLOY_DIR/" "$HOST:$REMOTE_DEPLOY/" | grep '^\*deleting' || true)"

if [[ -n "$DELETIONS" ]]; then
  echo "⚠️  El rsync va a BORRAR estos archivos del server:"
  echo "$DELETIONS" | sed 's/^\*deleting  */    /'
  if [[ "${DEPLOY_ASSUME_YES:-0}" != "1" ]]; then
    read -r -p "    ¿Seguir? (escribir 'si') " answer
    [[ "$answer" == "si" ]] || { echo "Abortado."; exit 1; }
  fi
fi

rsync -az --delete \
  "${RSYNC_KEEP_EXCLUDES[@]}" \
  "${RSYNC_ROLE_EXCLUDES[@]}" \
  "$DEPLOY_DIR/" "$HOST:$REMOTE_DEPLOY/"

# rsync --exclude no borra el archivo si quedó de un deploy previo → borrarlo explícito
if [[ "$DEPLOY_ROLE" == "app" ]]; then
  ssh "$HOST" "rm -f '$REMOTE_DEPLOY/nginx/conf.d/30-registry.conf' '$REMOTE_DEPLOY/nginx/conf.d/15-dev.conf' '$REMOTE_DEPLOY/nginx/conf.d/11-qf.conf' '$REMOTE_DEPLOY/docker-compose.dev98.yml'"
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
