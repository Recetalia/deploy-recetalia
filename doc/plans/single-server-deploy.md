# Plan: Deploy single-server (docker-compose remoto) — pre-prod

Seguir el skill `superpowers:writing-plans`. Este plan se ejecuta en ciclos: cada paso tiene criterio de éxito verificable.

## Objetivo

Desplegar los 7 servicios de la plataforma Recetalia en **un único servidor remoto pre-productivo** (`138.197.150.98`) con Docker + docker-compose v2. Exposición HTTPS pública para los 4 frontends + 2 APIs (`recetalia-api-rest`, `security-api-recetalia`) + el registry self-hosted. La tercera API (`transversal-recetalia-api`) queda únicamente en la red interna del stack.

## Criterios de éxito

- [ ] `docker compose up -d` arranca los 8 servicios (registry + 3 APIs + 4 frontends + nginx) sin error.
- [ ] Los 4 frontends responden HTTP 200 sobre HTTPS en sus subdominios `*pre.recetadigital.uy`.
- [ ] `POST /api/auth/login` contra `security-api-recetalia` devuelve un JWT válido.
- [ ] `GET /api/especialities` contra `recetalia-api-rest` funciona con ese JWT.
- [ ] `transversal-recetalia-api` **no** es accesible desde internet (no tiene entrada en nginx ni mapping de puerto).
- [ ] Registry responde en `https://registrypre.recetadigital.uy/v2/_catalog` con basic-auth.
- [ ] `docker pull registrypre.recetadigital.uy/recetalia/<proyecto>:latest` funciona desde el server autenticado.
- [ ] Let's Encrypt emitió certs válidos para los 6 subdominios públicos.
- [ ] Las 3 APIs conectan a sus DBs externas (configuradas en sus `application.yml`) y responden health checks.
- [ ] El archivo `.env` del servidor NO está en git; el repo sólo tiene `.env.example`.
- [ ] `registry/auth/htpasswd` NO está en git.

## Fuera de alcance (post-deploy)

- Kubernetes / Helm.
- CI/CD pipeline (GitHub Actions, Jenkins).
- Observabilidad (Prometheus, Loki, Grafana).
- Backups automáticos de la DB.
- Rotación de secrets (JWT, DB, Twilio, SMTP) — plan separado.
- Migración de passwords plain-text a hashes.
- Containerizar MySQL (si se decide más adelante, agregar servicio + env vars `SPRING_DATASOURCE_*` / `SPRING_R2DBC_*`).

## Ambiente de destino

- **Server IP:** `138.197.150.98` (pre-prod, DigitalOcean).
- **Acceso SSH:** usuario `root` con password (credenciales fuera de git).
- **Subdominios** (los 6 ya tienen `A record` apuntando al server):

| Servicio | Subdominio |
|---|---|
| `farmacias-recetalia-app` | `farmaciaspre.recetadigital.uy` |
| `medics-recetalia-app` | `medicospre.recetadigital.uy` |
| `medical-provider-app` | `prestadorespre.recetadigital.uy` |
| `gestion-recetadigital-app` | `gestionpre.recetadigital.uy` |
| APIs públicas (vía paths) | `apipre.recetadigital.uy` |
| Registry Docker self-hosted | `registrypre.recetadigital.uy` |

## DBs externas (no containerizadas)

Los tres servicios apuntan al **mismo cluster DO managed pre-prod** (`recetaliadbpreproduccion-…ondigitalocean.com:25060`). `security-api` y `transversal` lo resuelven desde su `application.yml` (el compose no les inyecta env vars de DB). `recetalia-api-rest` también tiene su `application.yml` apuntando ahí (branch `register_medic`), y **además** el compose le inyecta `SPRING_DATASOURCE_*` / `SPRING_DNMA_DATASOURCE_*` desde `.env` hacia el mismo host (override redundante; ver Decisión #8).

| API | Host | Puerto | User | DBs | Config |
|---|---|---|---|---|---|
| `recetalia-api-rest` | `recetaliadbpreproduccion-…ondigitalocean.com` (DO managed) | 25060 | `doadmin` | `recetali_receta`, `recetali_dnma` | `application.yml` + override `SPRING_DATASOURCE_*` del compose (`.env`) |
| `security-api-recetalia` | `recetaliadbpreproduccion-do-user-2735981-0.i.db.ondigitalocean.com` | 25060 | `doadmin` | `securitydb` | `application.yml` (sin env vars) |
| `transversal-recetalia-api` | ídem DO managed | 25060 | `doadmin` | `recetali_receta`, `recetali_dnma` | `application.yml` (sin env vars) |

⚠️ **Observaciones:**
- Los tres comparten el cluster DO managed — no hay segundo host `143.110.212.167` (ese string no aparece en el código). El riesgo previo de "`recetali_receta` en 2 hosts distintos" queda invalidado.
- El server pre-prod (`138.197.150.98`) tiene que tener conectividad salida al host DO managed por el puerto `25060`.

## Prerrequisitos del servidor

- OS Ubuntu/Debian 22+ (o RHEL-like).
- Docker Engine ≥ 24 + Docker Compose v2.
- Puertos 80 y 443 abiertos entrantes.
- Puerto 25060 (salida hacia el cluster DO managed pre-prod) accesible.
- Al menos 4 GB RAM y 20 GB disco libre.

> **Detalle por API de qué DB lee y cómo se resuelve la config**: ver [doc/specs/databases.md](../specs/databases.md). Incluye la verificación pre-deploy del cluster DO managed.

## Decisiones tomadas

| # | Tema | Decisión |
|---|---|---|
| 1 | Hostnames | Subdominios `*pre.recetadigital.uy` (6 en total). |
| 2 | TLS | nginx + LE automático vía imagen `jonasal/nginx-certbot`. |
| 3 | MySQL | **Externa / "modo host"** — se usan las DBs configuradas en cada `application.yml`, sin containerizar. |
| 4 | Esquema de DB | N/A — se usan las DBs existentes con sus datos. |
| 5 | Build | Registry self-hosted (`registry:2.8`) en `registrypre.recetadigital.uy` con basic-auth htpasswd. Build local → push → server hace pull. |
| 6 | Secrets | Reutilizar los actuales (commiteados en `application.yml`). Rotación en plan separado. |
| 7 | Frontend env por build | Configuración Angular `preprod` con `fileReplacements` → `environment.preprod.ts`. Controlado por `FRONTEND_CONFIGURATION` (farmacias/medics/gestion) y `MEDICAL_PROVIDER_ENVIRONMENT` (medical-provider usa nombres `prod`/`preprod`/`local`) en `deploy-recetalia/.env`. Descartada la opción runtime-config (`assets/config.json` + `APP_INITIALIZER`) mientras solo haya 2 ambientes. |
| 8 | Branch de `recetalia-api-rest` a deployar | `register_medic` (no `feature/workspace-bootstrap`). Es la única rama con `PharmacyController` completo y `MedicController.getByEmail` (`/api/medics/email/{email}`), endpoints que consumen los authGuards de farmacias/medics apps. El branch declara `server.port: 8094` en application.yml; el compose fuerza `SERVER_PORT: 8092` vía env var (relaxed binding) para mantener compat con el nginx existente sin tocar fuente. |

## Pasos

### Fase 1 — Preparación local

- [x] Paso 1.1 — Crear branch `feature/workspace-bootstrap` en los 8 repos.
- [x] Paso 1.2 — Esqueleto `deploy-recetalia/` + inventario de servicios.
- [x] Paso 1.3 — Dockerfiles para las 3 APIs (multi-stage JDK 21 → JRE 21, non-root).
- [x] Paso 1.4 — `docker-compose.yml` del stack (registry + TLS auto + DBs externas).
- [x] Paso 1.5 — `.env.example` + nginx reverse proxy + scripts `deploy.sh` / `build-and-push.sh`.
- [x] Paso 1.6 — Subdominios `*pre.recetadigital.uy` aplicados en nginx config.
- [x] **Checkpoint 1** — Stack revisado y decisiones confirmadas con el usuario.

### Fase 2 — Preparar el servidor

- [ ] Paso 2.1 — SSH al server `root@138.197.150.98`, validar Docker + Compose v2 instalados.
- [ ] Paso 2.2 — Validar conectividad desde el server a la DB externa (`...ondigitalocean.com:25060`, cluster DO managed pre-prod).
- [ ] Paso 2.3 — Verificar DNS: los 6 subdominios `*pre.recetadigital.uy` resuelven al server.
- [ ] Paso 2.4 — Crear `/opt/recetalia/deploy-recetalia/` y copiar `deploy-recetalia/` con `./scripts/deploy.sh` (primera vez, sin imágenes aún).
- [ ] Paso 2.5 — Crear `.env` en el server a partir de `.env.example` (con credenciales del registry).
- [ ] Paso 2.6 — Generar `registry/auth/htpasswd` (ver `registry/README.md`).
- [ ] Paso 2.7 — Setear `LETSENCRYPT_STAGING=1` en `.env` para la primera corrida.

### Fase 3 — Bootstrap del registry

- [ ] Paso 3.1 — En el server: `docker compose up -d registry nginx`. `jonasal/nginx-certbot` obtiene certs LE staging para los 6 subdominios.
- [ ] Paso 3.2 — Validar: `curl -u $REGISTRY_USER:$REGISTRY_PASSWORD https://registrypre.recetadigital.uy/v2/_catalog -k` → `{"repositories":[]}`.
- [ ] Paso 3.3 — Cambiar `LETSENCRYPT_STAGING=0` en `.env` y `docker compose up -d nginx` → certs reales.
- [ ] Paso 3.4 — Validar certs reales con un browser.

### Fase 4 — Build + push + deploy de apps

- [ ] Paso 4.1 — Desde local: `./scripts/build-and-push.sh` (build 7 imágenes + push).
- [ ] Paso 4.2 — Desde local: `./scripts/deploy.sh root@138.197.150.98 /opt/recetalia`.
- [ ] Paso 4.3 — `docker compose ps` — los 8 servicios en estado `running`.
- [ ] Paso 4.4 — Revisar logs de cada API y confirmar conexión OK a sus DBs externas.

### Fase 5 — Smoke tests y validación

- [x] Paso 5.1 — Los 4 frontends responden 200 sobre HTTPS en sus subdominios.
- [x] Paso 5.2 — `POST https://apipre.recetadigital.uy/security-api-recetalia/api/auth/login` devuelve JWT (verificado en browser desde las 4 apps con usuarios reales, 2026-04-22).
- [x] Paso 5.3 — `GET https://apipre.recetadigital.uy/recetalia-api-rest/api/especialities` → 200 (endpoint público, 15 KB de payload) verificado 2026-04-22.
- [x] Paso 5.4 — `transversal-recetalia-api/{,/api,/actuator/health}` → 404 todos. No expuesto públicamente. Verificado 2026-04-22.
- [x] Paso 5.5 — Registry accesible públicamente y con auth (funcionando, usado para los pushes).
- [x] **Checkpoint 2** — Login end-to-end validado desde browser por el usuario.

### Fase 6 — Frontend-config fix (descubierto durante Fase 5, 2026-04-22)

Los builds iniciales tenían `environment.ts` hardcodeado a `api.recetadigital.uy` (PROD), por lo que el login fallaba en pre-prod.

- [x] Paso 6.1 — Crear `src/environments/environment.preprod.ts` en los 4 frontends con URLs `apipre.recetadigital.uy/{recetalia-api-rest,security-api-recetalia}/api`.
- [x] Paso 6.2 — Añadir configuración `preprod` en `angular.json` de los 4 frontends, con `fileReplacements` + budgets/outputHashing iguales a `production`.
- [x] Paso 6.3 — Añadir `ARG CONFIGURATION=production` en Dockerfiles de farmacias/medics/gestion (medical-provider ya tenía `ARG ENVIRONMENT=local`).
- [x] Paso 6.4 — En `deploy-recetalia/docker-compose.yml`, pasar `args.CONFIGURATION: ${FRONTEND_CONFIGURATION:-production}` a los 3 primeros; medical-provider sigue con `ENVIRONMENT: ${MEDICAL_PROVIDER_ENVIRONMENT:-prod}`.
- [x] Paso 6.5 — En `.env`: `FRONTEND_CONFIGURATION=preprod` y `MEDICAL_PROVIDER_ENVIRONMENT=preprod`.
- [x] Paso 6.6 — Rebuild + push + deploy. Login funcionando end-to-end.

### Fase 7 — Fix branch recetalia-api-rest (descubierto post-login, 2026-04-22)

Tras el fix de Fase 6 el login devolvía JWT correctamente, pero farmacias y medics apps rebotaban al login inmediatamente después. Causa: sus `authGuard` llaman endpoints del backend (`GET /api/pharmacies/email/{email}` y `GET /api/medics/email/{email}`) que NO existen en el JAR deployado (branch `feature/workspace-bootstrap`). Gestion y medical-provider no se veían afectados porque sus guards sólo validan el JWT en memoria.

- [x] Paso 7.1 — Confirmado que el branch `register_medic` incluye `PharmacyController` entero y `MedicController.getByEmail` (`grep` sobre el working tree).
- [x] Paso 7.2 — Stash de los cambios locales de `feature/workspace-bootstrap` (env-var overrides en application.yml + DnmaDatabaseService). Descartado después — `register_medic` ya tiene `DnmaDatabaseServiceImpl` con `@Value` y application.yml apunta directo a la DB pre-prod en DO.
- [x] Paso 7.3 — `git checkout register_medic` (movido `bin/` local a `/tmp` para destrabar el checkout).
- [x] Paso 7.4 — Añadido `SERVER_PORT: 8092` al service `recetalia-api-rest` en `docker-compose.yml` (branch declara 8094 en application.yml; override vía relaxed binding para no tocar fuente ni nginx).
- [x] Paso 7.5 — `docker compose build/push recetalia-api-rest` + `./scripts/deploy.sh root@138.197.150.98`.
- [x] Paso 7.6 — Verificación: `GET /api/pharmacies/email/hello@recetalia.com` → 200; `GET /api/medics/email/jhomotta@gmail.com` → 200. Apps farmacias y medics permiten login end-to-end.

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| El server pre-prod no tiene salida al puerto 25060 del cluster DO managed (firewall / trusted sources de la DB) | Validar con `nc -z recetaliadbpreproduccion-do-user-2735981-0.i.db.ondigitalocean.com 25060` en Fase 2.2 antes de deployar apps; agregar el server a las trusted sources de la DB en DO si hace falta |
| Secretos commiteados en `application.yml` — si el repo se filtra, credenciales reales expuestas | Fuera de alcance (plan de rotación separado); mitigación parcial: repos privados |
| `authGuard` permite usuarios `INACTIVE` (bug pre-existente) | No se resuelve acá; plan separado |
| `POST /api/medics` público en `recetalia-api-rest` | No se resuelve acá; plan separado |
| Let's Encrypt rate-limits (50 certs/semana por dominio) al provisionar 6 certs | Usar `LETSENCRYPT_STAGING=1` durante debugging; pasar a prod sólo cuando todo funciona |
| Build de `transversal-recetalia-api` falla por módulos vacíos (`rest-consumer`/`metrics`) | Dockerfile usa `:app-service:bootJar` que sólo compila lo necesario |

## Checkpoints de revisión

- **Checkpoint 1** (fin Fase 1): stack y decisiones confirmadas. ✅
- **Checkpoint 2** (fin Fase 5): reporte con URLs funcionando, logs de health, y smoke tests verdes.

## Post-deploy (planes subsiguientes)

- Plan de rotación de secrets + saneamiento de `application.yml`.
- Plan para agregar Spring Security a `transversal-recetalia-api`.
- Plan de runtime config para frontends (URLs inyectables post-build).
- Plan de migración a hash de passwords en DB.
- Plan de CI/CD.
- (Si se decide) Plan de containerización de MySQL y migración de datos.
