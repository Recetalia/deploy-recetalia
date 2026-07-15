-- Ambiente DEV (.98): schemas de Recetalia + usuario de aplicación.
-- Corre solo en el primer arranque del volumen mysql-data.

CREATE DATABASE IF NOT EXISTS recetali_receta CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS recetali_dnma   CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS securitydb      CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
