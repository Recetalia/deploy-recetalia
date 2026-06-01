# deploy-recetalia

Proyecto de deploy de la plataforma Recetalia. Define y automatiza el despliegue (local, dev, prod) de los 7 servicios del workspace:

- **Frontends (Angular SSR):** `farmacias-recetalia-app`, `medics-recetalia-app`, `medical-provider-app`, `gestion-recetadigital-app`
- **APIs (Spring Boot / Java 21):** `recetalia-api-rest`, `security-api-recetalia`, `transversal-recetalia-api`

Para el mapa de integración entre apps y APIs, ver [../doc/architecture-overview.md](../doc/architecture-overview.md).

Para el inventario técnico de cada servicio (puertos, dependencias, variables de entorno), ver [doc/specs/services.md](doc/specs/services.md).

Para qué base de datos lee cada API en pre-prod, cómo se resuelve la config y los riesgos abiertos, ver [doc/specs/databases.md](doc/specs/databases.md).

## Estado

Esqueleto del proyecto. El stack de despliegue (docker-compose / Kubernetes+Helm / Terraform / Ansible / scripts) todavía no está definido — se completará en el próximo hito.

## Trabajo en curso

Todo el trabajo ocurre en el branch `feature/workspace-bootstrap` (mismo nombre en los 8 repos del workspace). No se pushea nada todavía.
