#!/usr/bin/env bash
# Genera el cert propio (self-signed) del sitio institucional recetalia.com.
# Lo usa nginx (40-recetalia-site.conf) para terminar TLS por IP (8443) y, en
# prod, para recetalia.com detrás de Cloudflare (modo Full acepta self-signed).
#
# Uso: ./scripts/gen-site-cert.sh [IP_DEL_SERVER]
set -euo pipefail

IP="${1:-159.203.26.217}"
DIR="$(cd "$(dirname "$0")/../nginx/certs" && pwd)"
mkdir -p "$DIR"

# SAN cubre el sitio (recetalia.com/www) + todos los dominios de prod de las apps
# y la API. Detrás de Cloudflare (Full) alcanza un self-signed en el origin.
SAN="DNS:recetalia.com,DNS:www.recetalia.com"
SAN="$SAN,DNS:farmacias.recetalia.com,DNS:medicos.recetalia.com"
SAN="$SAN,DNS:prestadores.recetalia.com,DNS:gestion.recetalia.com,DNS:api.recetalia.com"
SAN="$SAN,IP:${IP}"

openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
  -keyout "$DIR/site.key" \
  -out    "$DIR/site.crt" \
  -subj   "/O=Recetalia/CN=recetalia.com" \
  -addext "subjectAltName=${SAN}"

chmod 600 "$DIR/site.key"
echo "Cert generado en $DIR (site.crt / site.key) — SAN: recetalia.com + apps prod + api + IP ${IP}"
