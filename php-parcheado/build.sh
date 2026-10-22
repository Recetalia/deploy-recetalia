#!/bin/sh
# Construye y publica las bases parcheadas de recetalia-site (PHP2Shell) en el registry.
#   bullseye (php:7.4-apache)        → PROD (.217)
#   buster   (php:7.4-apache-buster) → .98 (CentOS 7, kernel 3.10: ver recetalia-site/Dockerfile)
# Uso, desde deploy-recetalia/: ./php-parcheado/build.sh   (lee REGISTRY_HOST del .env)
set -eu
cd "$(dirname "$0")"
REGISTRY_HOST=$(sed -n 's/^REGISTRY_HOST=//p' ../.env)
R=$REGISTRY_HOST/recetalia/php-base
docker build --platform linux/amd64 --build-arg BASE=php:7.4-apache -t $R:7.4-apache-php2shell .
docker build --platform linux/amd64 --build-arg BASE=php:7.4-apache-buster -t $R:7.4-apache-buster-php2shell .
docker push $R:7.4-apache-php2shell
docker push $R:7.4-apache-buster-php2shell
