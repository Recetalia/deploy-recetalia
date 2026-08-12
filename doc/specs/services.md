# Inventario de servicios a desplegar

Datos técnicos extraídos del análisis de cada proyecto. Referencia para definir el stack de deploy.

## Frontends (Angular 18.x SSR + NgModule, TS strict)

Todos tienen `Dockerfile` en el root del proyecto. Todos corren SSR vía Node Express (`server.ts`) en puerto **4000** por default, y típicamente se sirven con nginx en puerto **80**.

| Servicio | Angular | Dockerfile | Nginx conf | Configs Angular | URL backends (env) |
|---|---|---|---|---|---|
| [farmacias-recetalia-app](../../../farmacias-recetalia-app/) | 18.2 | `Dockerfile` | `default.conf` | `production`, `development` | `apiUrl` + `securityApiRecetaliaUrl` |
| [medics-recetalia-app](../../../medics-recetalia-app/) | 18.2 | `Dockerfile` | `default.conf` | `production`, `development` | Idem |
| [medical-provider-app](../../../medical-provider-app/) | 18.1 | `Dockerfile` | `default.conf` | `local`, `prod` (no estándar) | Idem |
| [gestion-recetadigital-app](../../../gestion-recetadigital-app/) | 18.2 | `Dockerfile` | — | `production`, `development` | Idem |
| [qf-recetalia-app](../../../qf-recetalia-app/) | 18.2 | `Dockerfile` | `default.conf` | `production`, `preprod`, `development`, `dev` | Idem |

### Observaciones frontend

- Las URLs de backend están **hardcodeadas en `environment.ts`** al momento del build. Para overrides en runtime (por entorno) hay que rehacer la estrategia (p.ej. servir `env.js` dinámico o inyectar al arrancar nginx).
- `medical-provider-app` usa nombres de configuración no estándar (`local` / `prod` en vez de `development` / `production`) — afecta al `npm run build`.
- Todos tienen mezcla de `provideClientHydration()` comentado + SSR activo — comportamiento de hidratación a verificar en el contenedor.

## APIs (Spring Boot 3.x / Java 21)

| Servicio | Spring Boot | Puerto | Persistencia | Dependencias externas |
|---|---|---|---|---|
| [recetalia-api-rest](../../../recetalia-api-rest/) | 3.3.0 | **8094** (`application.yml`); el compose lo fuerza a **8092** vía `SERVER_PORT` | MySQL JPA (`ddl-auto=none`, sin Flyway) | DB MySQL |
| [security-api-recetalia](../../../security-api-recetalia/) | 3.3.4 | **8091** | MySQL JPA (Flyway presente pero `enabled: false`) | DB MySQL, transversal-recetalia-api (para emails de reset) |
| [transversal-recetalia-api](../../../transversal-recetalia-api/) | 3.4.1 | **8093** | MySQL R2DBC × 2 (`recetali_receta`, `recetali_dnma`) | 2 DBs MySQL, Twilio WhatsApp, SMTP |

### Build

Todos usan Gradle Wrapper. Comandos estándar:
- `./gradlew bootJar` — genera JAR ejecutable
- `./gradlew bootBuildImage` — genera imagen OCI (Spring Boot buildpacks) — NO hay Dockerfile en las APIs, habrá que agregar uno o usar buildpacks

### Observaciones APIs

- **Sin Dockerfile** en ninguna API — hay que definirlo en este proyecto (o usar buildpacks + `bootBuildImage`).
- **Secrets en `application.yml`:** hoy commiteados en repo. El deploy necesita inyectar via `SPRING_*` env vars o Spring Cloud Config.
- **Migraciones de DB:** nadie las aplica automáticamente. Schema drift silencioso.
- **`transversal-recetalia-api`** es el caso más complejo: WebFlux, dos DBs, dos integraciones externas (Twilio + SMTP).

## Entornos

Por definir. Candidatos:

| Entorno | Uso | Posible stack |
|---|---|---|
| `local` | Dev en máquina del programador | docker-compose |
| `dev` | Shared dev en cloud | docker-compose o k8s |
| `staging` | Pre-prod | k8s + Helm |
| `prod` | Producción | k8s + Helm, o VMs con Ansible |

## Topología de red (a confirmar)

- Los 4 frontends exponen puerto 80 al público (HTTPS via ingress/reverse proxy).
- Los 4 frontends hablan con las APIs vía HTTPS (no se observó uso de un gateway/BFF).
- `security-api-recetalia` (8091) y `recetalia-api-rest` son accesibles desde los frontends (red pública con JWT).
- `transversal-recetalia-api` (8093) **solo debería ser accesible intra-red** — los frontends no la conocen. Hoy no hay Spring Security en esta API, así que si se expone públicamente hay endpoints críticos abiertos (`/api/dnmaxml/read`, `/api/email/send`).

## Observaciones transversales

Ver [../../../doc/architecture-overview.md](../../../doc/architecture-overview.md) §6 para el tech debt cross-proyecto relevante al deploy (rotación de secrets, CORS `*`, `authGuard INACTIVE` comentado, passwords en plain text, etc.).
