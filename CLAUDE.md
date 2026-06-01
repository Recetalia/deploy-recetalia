# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Proyecto de deploy (infra/DevOps) para la plataforma Recetalia. Orquesta el despliegue de 7 servicios (4 Angular SSR + 3 Spring Boot APIs) que viven en repos hermanos del workspace [../](..).

Estado: esqueleto. El stack de deploy aún no está definido — ver [README.md](README.md).

## Commands

Aún no hay comandos definidos. Se agregarán al elegir el stack (docker-compose / k8s+Helm / Terraform / etc.).

## Architecture

### Servicios a desplegar

Listado completo en [doc/specs/services.md](doc/specs/services.md). Resumen:

| Servicio | Tipo | Puerto interno | Notas |
|---|---|---|---|
| farmacias-recetalia-app | Frontend SSR | 4000 (SSR) / 80 (nginx) | Node Express + nginx |
| medics-recetalia-app | Frontend SSR | 4000 / 80 | Idem |
| medical-provider-app | Frontend SSR | 4000 / 80 | Idem |
| gestion-recetadigital-app | Frontend SSR | 4000 / 80 | Idem |
| recetalia-api-rest | Spring Boot | (por definir) | MySQL JPA |
| security-api-recetalia | Spring Boot | 8091 | MySQL JPA |
| transversal-recetalia-api | Spring Boot WebFlux | 8093 | MySQL R2DBC × 2 + Twilio + SMTP |

### Cross-cutting

- **Secrets management:** todavía por definir. Hoy los secrets (JWT, DB, Twilio, SMTP) están commiteados en los `application.yml` de las APIs — ver `doc/architecture-overview.md §6` del workspace.
- **Service mesh / routing:** por definir.
- **Observabilidad:** por definir.

## Conventions

- **No secrets en el repo.** `.gitignore` ya excluye `.env`, `*.pem`, `secrets/`. Las plantillas van como `.env.example`.
- **Referencias a repos hermanos:** usar rutas relativas (`../<proyecto>/`) — están todos en el mismo workspace.
- **Branch de trabajo:** `feature/workspace-bootstrap` (mismo nombre en los 8 repos del workspace).
