# Planes — deploy-recetalia

Planes de implementación para el despliegue de la plataforma. Seguir el skill `superpowers:writing-plans` (objetivos, criterios de éxito verificables, pasos, riesgos, checkpoints).

## Candidatos iniciales

- Definir stack de deploy (docker-compose local primero, k8s+Helm para dev/prod).
- Dockerfiles para las 3 APIs (hoy no existen).
- Runtime config de URLs backend para los frontends (hoy son build-time).
- Estrategia de secrets (extraer de `application.yml` a env vars / vault / sealed secrets).
- Migraciones de DB automatizadas (habilitar Flyway en las APIs).
- Segmentación de red para `transversal-recetalia-api` (hoy sin auth, no debe estar expuesto).
- Pipeline CI/CD.
