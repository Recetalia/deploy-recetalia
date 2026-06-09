# deploy-recetalia

Proyecto de deploy de la plataforma Recetalia. Define y automatiza el despliegue (local, dev, prod) de los 7 servicios del workspace:

- **Frontends (Angular SSR):** `farmacias-recetalia-app`, `medics-recetalia-app`, `medical-provider-app`, `gestion-recetadigital-app`
- **APIs (Spring Boot / Java 21):** `recetalia-api-rest`, `security-api-recetalia`, `transversal-recetalia-api`

Para el mapa de integración entre apps y APIs, ver [../doc/architecture-overview.md](../doc/architecture-overview.md).

Para el inventario técnico de cada servicio (puertos, dependencias, variables de entorno), ver [doc/specs/services.md](doc/specs/services.md).

Para qué base de datos lee cada API en pre-prod, cómo se resuelve la config y los riesgos abiertos, ver [doc/specs/databases.md](doc/specs/databases.md).

## Estado

Stack definido y validado en pre-prod: **docker-compose v2** sobre un único servidor (`138.197.150.98`, DigitalOcean) con registry self-hosted (`registry:2.8`) y nginx + Let's Encrypt automático como reverse proxy. Un deploy a pre-prod ya fue ejecutado y validado (login end-to-end desde browser, 2026-04-22). Ver [doc/plans/single-server-deploy.md](doc/plans/single-server-deploy.md).

## Uso

Flujo build local → push al registry → pull + up en el server:

```bash
# Local: build + push de las 7 imágenes al registry self-hosted
./scripts/build-and-push.sh

# Deploy al server (sync de deploy-recetalia/ + pull + up -d)
./scripts/deploy.sh user@server [/remote/dir]
```

Requiere un `.env` completado (plantilla en `.env.example`, gitignored) y `registry/auth/htpasswd` en el server (ver `registry/README.md`).
