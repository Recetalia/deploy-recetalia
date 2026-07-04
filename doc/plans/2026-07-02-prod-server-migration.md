# Plan: Server nuevo (prod-candidate) — migrar el stack pre-prod de .98 → 159.203.26.217

Seguir el skill `superpowers:writing-plans`. Cada paso tiene criterio de éxito verificable.
Complementa a [single-server-deploy.md](single-server-deploy.md) (el deploy original a `.98`); acá sólo
se documentan las **diferencias** para el server nuevo.

## Objetivo

Levantar el stack Recetalia en un **segundo servidor** (`159.203.26.217`) que será el
**candidato a producción**. Durante la validación usa los **mismos dominios pre**
(`*pre.recetadigital.uy`) y la **misma DB** (cluster DO managed pre-prod) que `.98`.
Una vez validado end-to-end, se corta el DNS de los dominios pre `.98 → server nuevo` y
esa DB de pre pasa a ser la DB productiva.

En resumen: **es una mudanza del host de apps** de `.98` al server nuevo. `.98` queda
demotado a **registry-only**.

## Decisiones tomadas (confirmadas con Pablo, 2026-07-02)

| # | Tema | Decisión |
|---|---|---|
| 1 | Dominios | El server nuevo sirve los **mismos dominios pre** (`farmaciaspre/medicospre/prestadorespre/gestionpre/apipre.recetadigital.uy`). nginx del server nuevo = igual al de pre (menos el bloque del registry). |
| 2 | DB | **La misma de pre** — cluster DO managed `recetaliadbpreproduccion-…:25060` (`recetali_receta`, `recetali_dnma`, `securitydb`). Esa DB de pre será la prod tras validar. `.env` de DB idéntico al de pre. |
| 3 | Registry | **Se queda en `.98`** (`registrypre.recetadigital.uy`). El server nuevo NO corre registry: sólo hace `docker pull` desde `.98`. → rol `app` (sin servicio `registry` ni bloque nginx). |
| 4 | Imágenes | **Reusar las ya pusheadas** (tag `latest`) en registrypre del último deploy a pre. Sin rebuild. |
| 5 | Cutover DNS | **Validar por IP primero.** Stack arriba en el server nuevo con certs dummy/staging; validar vía hosts-file (mapear los 5 dominios pre → `159.203.26.217`); recién con OK mover A records y emitir certs LE reales. `.98` sigue vivo hasta el corte. |
| 6 | Frontends | Build `preprod` (igual que pre) — apuntan a `apipre.recetadigital.uy`. El `environment.ts` "production" está roto (apunta a `…-dev`, `production:false`); NO se usa. |

## Ambiente de destino

- **Server IP:** `159.203.26.217` (root + password, fuera de git).
- **Rol:** `app` (frontends + 3 APIs + nginx). Sin registry.
- **Registry (externo):** `registrypre.recetadigital.uy` en `.98` — el daemon del server nuevo
  hace `docker login` + `docker pull` contra él.
- **DB (externa):** cluster DO managed pre-prod, puerto `25060`.

## Cambios de infra para soportar el rol `app` (backward-compatible con `.98`)

El repo se parametrizó por **rol de deploy** sin cambiar el comportamiento por defecto de `.98`:

- `docker-compose.yml`: el servicio `registry` quedó detrás de `profiles: ["registry"]` y se sacó
  de `nginx.depends_on`. El bloque nginx del registry se movió a `nginx/conf.d/30-registry.conf`.
- `scripts/deploy.sh`: variable `DEPLOY_ROLE` (`full` | `app`, default **`full`** = comportamiento
  actual de `.98`).
  - `full`: `COMPOSE_PROFILES=registry`, incluye `30-registry.conf`. (= `.98`)
  - `app`: sin profile de registry, **excluye** `30-registry.conf` del rsync. (= server nuevo)
- ⚠️ **Efecto sobre `.98`:** en su **próximo** `deploy.sh` (rol `full`), al estar el bloque del
  registry ahora en archivo propio, jonasal/certbot emite **un cert LE extra** sólo para
  `registrypre` (hoy comparte SAN con `apipre`). Es 1 cert, dentro de rate limits, sin downtime.
  Mientras no se redeploye `.98`, sigue exactamente igual.

## Prerrequisitos del servidor nuevo (verificar antes de deployar)

- [ ] Docker Engine ≥ 24 + Compose v2.
- [ ] Inbound 80 + 443 abiertos (80 lo necesita el challenge HTTP-01 de LE en el cutover).
- [ ] **Outbound 25060** al cluster DO managed (DB).
- [ ] **Outbound 443** a `registrypre.recetadigital.uy` (.98) para el `docker pull`.
- [ ] Outbound a Twilio + SMTP (transversal emite WhatsApp/mail).
- [ ] ≥ 4 GB RAM, ≥ 20 GB disco.
- [ ] **⚠️ Trusted sources de la DB DO:** agregar `159.203.26.217` a la allowlist del cluster
      managed en el panel DO, o las APIs no conectan. (Sólo Pablo tiene acceso al panel.)

## Pasos

### Fase 0 — Cambios de infra en el repo (LOCAL, esta sesión) ✅

- [x] Paso 0.1 — Parametrizar `docker-compose.yml` (registry → profile, sacar de `nginx.depends_on`).
- [x] Paso 0.2 — Mover el bloque nginx del registry a `30-registry.conf`.
- [x] Paso 0.3 — `deploy.sh` con `DEPLOY_ROLE` (full|app). Validado: `compose config` OK en ambos roles.
- [x] Paso 0.4 — Actualizar `CLAUDE.md` con el rol `app` (`.env.example` sin cambios: DB/registry iguales).
- [ ] **Checkpoint 0** — Revisar diffs con Pablo antes de tocar el server. NO commitear sin OK.

### Fase 1 — Preparar el servidor nuevo ✅ (2026-07-02)

- [x] Paso 1.1 — SSH `root@159.203.26.217` OK. Ubuntu 24.04.4, x86_64, 7.8 GB RAM, 152 GB libre.
      Docker faltaba → instalado **29.6.1** + Compose **v5.3.0** (get.docker.com), daemon `active`.
- [x] Paso 1.2 — DB DO managed `:25060` **reachable** vía /dev/tcp desde el server nuevo (TCP OK →
      trusted-sources no bloquea a esta IP, o no hay restricción). Auth real la confirma el deploy.
- [x] Paso 1.3 — `registrypre.recetadigital.uy:443` **reachable** (resuelve a `138.197.150.98`).
- [x] Paso 1.4 — `/opt/recetalia/dnma_info` creado con permisos 777.
- Extra — inbound 80/443 libres en el server nuevo.

### Fase 2 — Deploy del stack (rol app, sin cutover) ✅ (2026-07-03)

- [x] Paso 2.1 — `DEPLOY_ROLE=app ./scripts/deploy.sh root@159.203.26.217`. Autoricé mi SSH key
      (`id_ed25519.pub`) en el server para que el script corra sin password. Pull de las 7 imágenes
      `latest` desde registrypre + `up -d`.
- [x] Paso 2.2 — `.env` creado en el server = copia del de pre (+ `USE_LOCAL_CA=1`, ver Fase 3).
- [x] Paso 2.3 — N/A en rol app (htpasswd sólo lo usa el registry; el server usa `docker login` con
      REGISTRY_USER/PASSWORD del `.env`).
- [x] Paso 2.4 — `docker compose ps`: 7 servicios `running`/`healthy`. NO existe `recetalia-registry`. ✅
- [x] Paso 2.5 — Logs: **las 3 APIs conectan a la DB DO** (api-rest + security Hikari OK; transversal
      R2DBC OK). Confirma que trusted-sources acepta `159.203.26.217` y el auth funciona.

### Fase 3 — Validación por IP (pre-cutover) ✅ (2026-07-03)

⚠️ **Hallazgo:** jonasal NO genera self-signed solo — al fallar el HTTP-01 de LE (DNS en `.98`)
**deshabilita** los server blocks 443 (`.conf.nokey`). Fix: `USE_LOCAL_CA=1` (parametrizado en el
compose, seteado en el `.env` del server) → jonasal firma certs self-signed con una CA local →
443 levanta. **Quitar `USE_LOCAL_CA` al hacer el cutover** (Fase 4).

- [x] Paso 3.1 — Validado con `curl --resolve <dominio>:443:159.203.26.217` (equiv. hosts-file).
- [x] Paso 3.2 — Los 4 frontends → **HTTP 200** por HTTPS (cert self-signed).
- [x] Paso 3.3 — `POST …/security-api-recetalia/api/auth/loginBack` (email+password+`info:"000"`) →
      **JWT válido** para `gestion@recetalia.com` (ROLE_MANAGEMENT) y `test@test.com` (ROLE_PHARMACY).
      (El endpoint es `loginBack`, no `login`; `info` es `@NotBlank` — ver [[api-validation-curls]].)
- [x] Paso 3.4 — `GET …/recetalia-api-rest/api/especialities` → **200** (15 KB).
- [x] Paso 3.5 — transversal por `apipre/transversal-recetalia-api/api` → **404** (no expuesto). ✅
- [x] Extra — `GET /dashboard/summary` autenticado (Bearer JWT) → **200** (10 KB): circuito completo
      login→JWT→nginx→api-rest→DB→DNMA OK.
- [ ] **Checkpoint 3** — Falta que Pablo valide en **browser** vía hosts-file (login + navegación).

### Fase 4 — Cutover DNS + certs reales (cuando Pablo dé OK)

- [ ] Paso 4.1 — Mover A records de los 5 dominios pre `.98 → 159.203.26.217`.
- [ ] Paso 4.2 — Confirmar propagación (`dig +short farmaciaspre.recetadigital.uy` = server nuevo).
- [ ] Paso 4.3 — En el server nuevo, `.env`: `LETSENCRYPT_STAGING=0`; `docker compose up -d nginx`
      → jonasal emite certs LE reales para los 5 dominios pre.
- [ ] Paso 4.4 — Validar certs reales en browser (sin hosts-file).
- [ ] Paso 4.5 — `registrypre.recetadigital.uy` SIGUE en `.98` (no se mueve). Confirmar que
      build-and-push desde local sigue pusheando a `.98` OK.
- [ ] Paso 4.6 — Apagar / demotar el stack de apps en `.98` (dejar sólo el registry corriendo).

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| DB DO rechaza al server nuevo (trusted sources) | Paso 1.2 antes de deployar; agregar IP en DO |
| Certs LE no emiten pre-cutover (DNS en `.98`) | Esperado — validar por IP/hosts-file con cert dummy (Fase 3) |
| Cert extra de registrypre en el próximo deploy de `.98` | 1 cert, dentro de rate limit; documentado; `.98` no se redeploya salvo necesidad |
| DB compartida pre↔prod durante validación | Aceptado por ahora; separar es plan posterior (Pablo: la DB de pre será la prod tras validar) |
| Doble emisión de notificaciones (2 stacks vivos con misma DB) | Durante Fase 3 el server nuevo NO debería procesar jobs de notificación en paralelo con `.98`; validar y, si hace falta, apagar el transversal de uno de los dos hasta el cutover |

## Actualización 2026-07-03 — pivot a `*pre.recetalia.com` detrás de Cloudflare ✅

Pablo cambió: el server nuevo sirve **`*pre.recetalia.com`** (no los `.uy`). Hecho:
- 4 frontends `environment.preprod.ts` → `apipre.recetalia.com`; **rebuild EN el server** (amd64, serial — en paralelo agota los 7.8 GB y tira SSH) + push a registrypre. Imágenes verificadas: contienen `.com`, cero `.uy`.
- nginx confs (`10-frontends`, `20-apis`) → `server_name`/cert-path/CORS-map a `.recetalia.com`. `30-registry.conf` sigue en `.uy` (excluido en rol app).
- Deploy rol `app` + `force-recreate nginx` → local CA firma self-signed para los `.com`.
- **Cloudflare adelante:** los `.com` resuelven a CF (proxy naranja) → origin `.217`. TLS público = edge de CF (candado válido, sin hosts-file). SSL mode = **Full** (acepta el self-signed del origin). NO usar LE en el `.217`.
- **Validado vía CF (URLs reales `.com`):** 4 frontends rutean a su app; especialities 200; **5 accesos** SUCCESS+rol; dashboard autenticado 200; CORS preflight 204 con ACAO `farmaciaspre.recetalia.com`.

Pendientes: (1) hardening TLS = Cloudflare Origin Cert en `.217` + Full-strict. (2) email links `.uy` en `recetalia-api-rest/application.yml` → requieren rebuild de api-rest. (3) cambios de repo (deploy-recetalia + 4 frontends) **sin commitear** (regla no-merge-sin-OK). Detalle en memoria [[newserver-com-cloudflare]].

## Checkpoints

- **Checkpoint 0** (fin Fase 0): diffs de infra revisados. NO commit sin OK de Pablo.
- **Checkpoint 3** (fin Fase 3): login end-to-end validado por IP contra el server nuevo.
- **Checkpoint 4** (2026-07-03): stack `.com` validado end-to-end vía Cloudflare. Listo para el tester.
