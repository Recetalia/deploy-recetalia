# Registry self-hosted (Distribution v2)

Este directorio contiene los auxiliares del registry containerizado. Vive detrás de nginx con TLS de Let's Encrypt, expuesto en el subdominio `$REGISTRY_HOST` (definido en `.env`, default `registry.recetadigital.uy`).

## Estructura

```
registry/
├── README.md           # este archivo
└── auth/
    └── htpasswd        # NO se commitea — generar antes del primer deploy
```

El volumen persistente de blobs (`registry-data`) vive fuera del repo, manejado por Docker.

## Generar `htpasswd` (bootstrap, una sola vez)

Usuario + password tienen que coincidir con `REGISTRY_USER` / `REGISTRY_PASSWORD` en `.env`. El archivo se genera con bcrypt (la imagen de Distribution rechaza otros formatos).

### Opción A — vía contenedor de httpd (sin instalar nada)

```bash
cd deploy-recetalia
mkdir -p registry/auth
docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$REGISTRY_USER" "$REGISTRY_PASSWORD" \
  > registry/auth/htpasswd
```

### Opción B — con `htpasswd` local (apt install apache2-utils)

```bash
htpasswd -Bbc registry/auth/htpasswd "$REGISTRY_USER" "$REGISTRY_PASSWORD"
```

Verificar:

```bash
cat registry/auth/htpasswd
# debería ver: recetalia:$2y$05$...
```

## Importante

- **No commitear `htpasswd`.** Ya está excluido en `.gitignore` (pattern `registry/auth/htpasswd`).
- **Mismo usuario en ambos lados:** el dev que hace `docker push` y el server que hace `docker pull` usan las mismas credenciales (hay un solo `htpasswd`).
- **Rotación:** regenerar el archivo + reiniciar el contenedor del registry (`docker compose restart registry`). Los devs y el server vuelven a correr `docker login`.
- **Agregar más usuarios:** `htpasswd -B registry/auth/htpasswd otro_user` (sin `-c`, para no sobrescribir).

## Verificación del registry

Una vez arriba:

```bash
# Listar repos (requiere auth)
curl -u "$REGISTRY_USER:$REGISTRY_PASSWORD" https://$REGISTRY_HOST/v2/_catalog

# Listar tags de una imagen
curl -u "$REGISTRY_USER:$REGISTRY_PASSWORD" \
  https://$REGISTRY_HOST/v2/recetalia/recetalia-api-rest/tags/list
```

## Limpieza / Garbage Collection

Distribution marca blobs como deleted pero no libera disco hasta correr GC:

```bash
# En el server:
docker compose exec registry registry garbage-collect /etc/docker/registry/config.yml
```

Conviene correrlo después de borrar tags masivos.
