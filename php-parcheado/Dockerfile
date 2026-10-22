# Base de recetalia-site: php:7.4-apache recompilado con el arreglo de PHP2Shell
# (CVE-2026-109618 y CVE-2026-109619).
#
# Adaptación de ~/iwtg/sites-manager/php-parcheado (pensada para php-fpm) a mod_php:
# recompila PHP encima de la imagen oficial con sus mismas opciones
# (`php-config --configure-options`, que incluyen --with-apxs2) y sus mismas CFLAGS,
# así las extensiones que instala después recetalia-site (mysqli) siguen siendo compatibles.
# 7.4 no tiene versión oficial corregida: se aplica el backport de php.net (rama
# PHP-7.4-CVE-2026-109618-109619, sha256 d059c1b4…). `php -v` sigue diciendo 7.4.33;
# la marca de que está parcheado es /usr/local/etc/php-parcheado.txt.
#
# Uso: ver build.sh.
ARG BASE=php:7.4-apache
FROM ${BASE}
# Repetido: un ARG declarado antes del FROM no se ve después.
ARG BASE
ARG PARCHE=7.4-CVE-2026-109618-109619.patch
COPY parches/ /tmp/parches/

RUN set -eux; \
    # buster y bullseye salieron de deb.debian.org / security.debian.org: viven en
    # archive.debian.org (medido 21/10/2026 en sites-manager para bullseye).
    sed -i -e 's|deb.debian.org|archive.debian.org|g' \
           -e 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' \
           -e 's|security.debian.org|archive.debian.org/debian-security|g' /etc/apt/sources.list; \
    sed -i '/-updates/d' /etc/apt/sources.list; \
    apt-get -o Acquire::Check-Valid-Until=false update; \
    # apache2-dev: --with-apxs2 necesita apxs para compilar e instalar libphp7.so.
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $PHPIZE_DEPS patch \
        apache2-dev libargon2-dev libcurl4-openssl-dev libonig-dev libreadline-dev libsodium-dev \
        libsqlite3-dev libssl-dev libxml2-dev zlib1g-dev; \
    rm -rf /var/lib/apt/lists/*; \
    opciones="$(php-config --configure-options)"; \
    docker-php-source extract; \
    cd /usr/src/php; \
    patch -p1 < "/tmp/parches/$PARCHE"; \
    export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS"; \
    eval "./configure $opciones"; \
    make -j"$(nproc)"; \
    make install; \
    { echo "base=$BASE"; echo "parche=$PARCHE"; sha256sum "/tmp/parches/$PARCHE"; } > /usr/local/etc/php-parcheado.txt; \
    cd /; docker-php-source delete; rm -rf /tmp/parches; \
    php -v; apache2ctl -t; apache2ctl -M 2>/dev/null | grep -i php
