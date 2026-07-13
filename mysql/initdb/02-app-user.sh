#!/bin/bash
# Crea el usuario de aplicación con grants sobre los 3 schemas.
# Los .sh de docker-entrypoint-initdb.d sí ven el environment del contenedor
# (los .sql no), por eso el usuario va acá y no en 01-schemas.sql.
set -euo pipefail

mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE USER IF NOT EXISTS '${DEV_DB_USER}'@'%' IDENTIFIED BY '${DEV_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON recetali_receta.* TO '${DEV_DB_USER}'@'%';
GRANT ALL PRIVILEGES ON recetali_dnma.*   TO '${DEV_DB_USER}'@'%';
GRANT ALL PRIVILEGES ON securitydb.*      TO '${DEV_DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL
