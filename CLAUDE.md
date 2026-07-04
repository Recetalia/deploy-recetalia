# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Proyecto de deploy (infra/DevOps) para la plataforma Recetalia. Orquesta el despliegue de 7 servicios (4 Angular SSR + 3 Spring Boot APIs) que viven en repos hermanos del workspace [../](..).

Stack: **docker-compose v2** sobre un único servidor pre-prod (`138.197.150.98`, DigitalOcean), con un registry self-hosted (`registry:2.8`) y nginx + Let's Encrypt automático (`jonasal/nginx-certbot`) como reverse proxy público. El flujo es **build local → push al registry → pull + up en el server**. Un deploy a pre-prod ya fue ejecutado y validado (login end-to-end desde browser, 2026-04-22). Detalle en [doc/plans/single-server-deploy.md](doc/plans/single-server-deploy.md).

## Commands

| Tarea | Comando |
| --- | --- |
| Build + push de las 7 imágenes al registry | `./scripts/build-and-push.sh` (lee `.env`, hace `docker login` + `docker compose build/push`) |
| Deploy al server (sync + pull + up) | `./scripts/deploy.sh user@server [/remote/dir]` (default remote dir `/opt/recetalia`) |
| Levantar el stack manualmente (rol full / .98) | `COMPOSE_PROFILES=registry docker compose up -d` |
| Levantar el stack manualmente (rol app / server nuevo) | `docker compose up -d` (sin registry) |
| Estado de los servicios | `docker compose ps` |

`docker-compose.yml` define el stack completo: registry + 3 APIs + 4 frontends + nginx. `transversal-recetalia-api` no expone puertos (sólo red interna `recetalia-net`). El `.env` (gitignored) parametriza registry, TLS, configuración de frontends y el override de DB de `recetalia-api-rest`; plantilla en `.env.example`.

### Rol de deploy (`DEPLOY_ROLE`)

Hay dos hosts. El servicio `registry` está detrás de `profiles: ["registry"]` y su bloque nginx vive en `nginx/conf.d/30-registry.conf`:

- **`full`** (default) — host que además hostea el registry (`138.197.150.98`). `deploy.sh` activa `COMPOSE_PROFILES=registry` e incluye `30-registry.conf`. Es el comportamiento histórico.
- **`app`** — host sólo de apps (server nuevo `159.203.26.217`, candidato a prod). `DEPLOY_ROLE=app ./scripts/deploy.sh root@159.203.26.217`: NO corre registry, excluye `30-registry.conf`, y pullea las imágenes desde `registrypre.recetadigital.uy` (.98).

Detalle de la mudanza `.98 → server nuevo` en [doc/plans/2026-07-02-prod-server-migration.md](doc/plans/2026-07-02-prod-server-migration.md).

## Architecture

### Servicios a desplegar

Listado completo en [doc/specs/services.md](doc/specs/services.md). Resumen:

| Servicio | Tipo | Puerto interno | Notas |
|---|---|---|---|
| farmacias-recetalia-app | Frontend SSR | 4000 (SSR) / 80 (nginx) | Node Express + nginx |
| medics-recetalia-app | Frontend SSR | 4000 / 80 | Idem |
| medical-provider-app | Frontend SSR | 4000 / 80 | Idem |
| gestion-recetadigital-app | Frontend SSR | 4000 / 80 | Idem |
| recetalia-api-rest | Spring Boot | 8094 (yml); compose lo fuerza a 8092 vía `SERVER_PORT` | MySQL JPA |
| security-api-recetalia | Spring Boot | 8091 | MySQL JPA |
| transversal-recetalia-api | Spring Boot WebFlux | 8093 | MySQL R2DBC × 2 + Twilio + SMTP |

### Cross-cutting

- **Secrets management:** los secrets de las APIs (JWT, DB, Twilio, SMTP) siguen commiteados en sus `application.yml` (Decisión #6: reutilizar los actuales; rotación en plan separado). El `.env` del deploy aporta credenciales de registry y el override de DB de `recetalia-api-rest`, y NO se commitea. Ver `doc/architecture-overview.md §6` del workspace.
- **Routing / TLS:** nginx (`jonasal/nginx-certbot`) como reverse proxy público con Let's Encrypt automático; un cert por subdominio `*pre.recetadigital.uy`. APIs públicas vía paths bajo `apipre.recetadigital.uy`; `transversal-recetalia-api` sólo en la red interna del stack.
- **Observabilidad:** fuera de alcance del deploy actual (Prometheus/Loki/Grafana en plan posterior).

## Conventions

- **No secrets en el repo.** `.gitignore` ya excluye `.env`, `*.pem`, `secrets/`. Las plantillas van como `.env.example`.
- **Referencias a repos hermanos:** usar rutas relativas (`../<proyecto>/`) — están todos en el mismo workspace.
- **Branch de trabajo:** `feature/workspace-bootstrap` (mismo nombre en los 8 repos del workspace).
