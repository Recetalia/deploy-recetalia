#!/usr/bin/env bash
# Recetalia — build local + push al registry self-hosted
#
# Build de las 7 imágenes (3 APIs + 4 frontends) desde los repos hermanos
# del workspace y push al registry definido en .env ($REGISTRY_HOST).
#
# Prerrequisito: el registry ya tiene que estar corriendo y alcanzable por
# HTTPS. En el bootstrap del server hay que arrancar sólo los servicios de
# infra primero (ver doc/plans/single-server-deploy.md §Fase 3).
#
# Uso:
#   ./scripts/build-and-push.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$DEPLOY_DIR"

if [[ ! -f .env ]]; then
  echo "ERROR: falta .env en $DEPLOY_DIR"
  echo "       cp .env.example .env && edit .env"
  exit 1
fi

# Cargar .env al entorno para que docker compose vea las vars
set -a
# shellcheck source=/dev/null
. .env
set +a

: "${REGISTRY_HOST:?REGISTRY_HOST no definido en .env}"
: "${REGISTRY_USER:?REGISTRY_USER no definido en .env}"
: "${REGISTRY_PASSWORD:?REGISTRY_PASSWORD no definido en .env}"
: "${IMAGE_TAG:=latest}"

echo "==> docker login $REGISTRY_HOST"
echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_HOST" -u "$REGISTRY_USER" --password-stdin

echo "==> docker compose build (7 imágenes)"
docker compose build \
  recetalia-api-rest \
  security-api-recetalia \
  transversal-recetalia-api \
  farmacias-recetalia-app \
  medics-recetalia-app \
  medical-provider-app \
  gestion-recetadigital-app

echo "==> docker compose push"
docker compose push \
  recetalia-api-rest \
  security-api-recetalia \
  transversal-recetalia-api \
  farmacias-recetalia-app \
  medics-recetalia-app \
  medical-provider-app \
  gestion-recetadigital-app

echo
echo "OK — imágenes publicadas con tag '$IMAGE_TAG' en $REGISTRY_HOST."
echo "    Para desplegarlas en el server: ./scripts/deploy.sh user@server"
