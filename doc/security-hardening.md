# Seguridad del servidor — auditoría y hardening (pasaje a prod)

> Server nuevo (candidato a prod): **`159.203.26.217`** (Ubuntu 24.04.4 LTS), detrás de Cloudflare, sirviendo `*pre.recetalia.com`. Auditoría inicial: **2026-07-03**. Este doc se usa como checklist para el pasaje a producción — actualizar a medida que se cierran ítems.

## Alcance

Seguridad **de infraestructura/servidor**. La deuda a nivel aplicación/datos (DB, passwords, secrets) se lista en "Pendientes" porque bloquea el pasaje a prod, pero su detalle vive también en el plan y en las memorias del workspace.

---

## Hardening YA APLICADO (2026-07-03)

| # | Ítem | Detalle |
|---|---|---|
| A1 | **Origin cerrado a Cloudflare** | El `.217` acepta 80/443 **solo desde las IPs de CF** (directo por IP → bloqueado). Hecho con la cadena `DOCKER-USER` de iptables (ufw NO sirve para puertos publicados por Docker). Persistente: `cf-origin-lock.service` (systemd, reaplica al boot) + `/usr/local/sbin/cf-origin-lock.sh` + fallback `/etc/cloudflare-ips-v4`. **Fix 2026-07-07:** el DROP lleva `-i <iface externa>` (eth0) — sin eso también bloqueaba el **egress** de los contenedores a 80/443 (builds sin npm/fonts, hairpin al security-api vía apipre con timeout → rompía el registro de médicos/farmacias, Twilio). El candado aplica SOLO al tráfico entrante desde internet. |
| A2 | **SSH sin password** | `PasswordAuthentication no` (drop-in `/etc/ssh/sshd_config.d/00-hardening.conf`; el `50-cloud-init.conf` lo ponía en `yes` — se gana por orden). Mata el vector de brute-force (había **7676** intentos fallidos en auth.log). |
| A3 | **SSH root key-only** | `PermitRootLogin prohibit-password`. Solo la key de Pablo (`pbl.mendez@gmail.com`) autorizada. |
| A4 | **fail2ban** | Instalado + activo, jail `sshd` (ya baneó IPs de brute-force). |
| A5 | **SSH extra** | `X11Forwarding no`, `KbdInteractiveAuthentication no`, `MaxAuthTries 3`, `LoginGraceTime 20`. |
| A6 | **ufw** | Activo, default deny incoming (protege puertos host; 22 abierto). |
| A7 | **Auto-updates** | `unattended-upgrades` instalado y activo (`APT::Periodic::Unattended-Upgrade "1"`). |
| A8 | **Docker daemon** | NO expuesto por TCP (2375/2376 cerrados). |

---

## Hallazgos PENDIENTES (por severidad)

### 🔴 Crítico / Alto — bloquean prod

| # | Hallazgo | Riesgo | Remediación |
|---|---|---|---|
| P1 | **DB compartida pre↔prod** (mismo cluster+datos que pre) | Pruebas de pre escriben sobre datos productivos; notificaciones dobles | Separar la DB de prod antes del go-live (schema/cluster propio). Es el bloqueante #1. |
| P2 | **Passwords en texto plano en la DB** | Si la DB se filtra, se exponen todas las claves de usuarios | Migrar a hash (bcrypt/argon2) en security-api. |
| P3 | **Secrets en el código** (DB, JWT, Twilio, SMTP en `application.yml` / `.env`) | Filtración del repo = credenciales productivas expuestas | Rotar + mover a secret manager / vars de entorno fuera del repo. |
| P4 | **Kernel/updates pendientes + reboot required** | Vulnerabilidades de kernel sin parchear | `apt-get upgrade` + **reboot programado** (el stack vuelve solo: `restart: unless-stopped` + `cf-origin-lock.service` + ufw persistentes). Coordinar ventana (downtime breve). |

### 🟠 Medio

| # | Hallazgo | Riesgo | Remediación |
|---|---|---|---|
| P5 | **SSH (22) abierto a todo internet** | Sigue siendo blanco de brute-force (mitigado por key-only + fail2ban) | Restringir 22 a IPs conocidas (Pablo/oficina) o Cloudflare Tunnel. Aplicar solo con IP fija confirmada (riesgo de lockout). |
| P6 | **Sin usuario no-root de deploy** | Todo corre/administra como root | Crear usuario sudo dedicado, mover deploy ahí, `PermitRootLogin no`. |
| P7 | **Sin monitoreo/alertas/observabilidad** | Caídas o abusos pasan desapercibidos | Uptime (CF/externo) + logs + métricas + alertas mínimas. |
| P8 | **Un solo server, sin HA** | Falla del `.217` = caída total | Plan de recuperación documentado o redundancia. Snapshots del droplet. |
| P9 | **Cloudflare en Full (no strict)** | Tramo CF↔origin cifrado pero sin validar cert de origin (MITM teórico) | Opcional: Origin Cert de CF + Full (strict). Requiere acceso CF de Pablo. |

### 🟡 Bajo / Deuda

| # | Hallazgo | Remediación |
|---|---|---|
| P10 | Imágenes en tag `latest` (sin versionado/rollback) | Pinnear versiones/semver + registro de despliegues. |
| P11 | Sin CI/CD (deploys manuales, build en el server) | Pipeline de build/push/deploy. |
| P12 | Endpoints públicos de auto-registro (`POST /api/medics`, etc.) y `authGuard` que deja pasar `INACTIVE` | Revisar autorizaciones (deuda pre-existente del código). |
| P13 | `transversal-recetalia-api` sin Spring Security | Mitigado (solo red interna, no expuesto). Añadir auth si alguna vez se expone. |
| P14 | Esquema DB sin migraciones (Flyway off, `ddl-auto=none`, ALTER a mano) | Estrategia de migraciones para evitar drift. |
| P15 | Stress test (k6) no corrido contra este server | Correr la suite `recetalia-security-testing` antes del go-live. |

---

## Checklist mínimo para declarar "producción"

- [ ] P1 — DB de prod separada de pre
- [ ] P2 — Passwords hasheados
- [ ] P3 — Secrets fuera del código + rotados
- [ ] P4 — Server actualizado + reboot aplicado
- [ ] P7 — Monitoreo + alertas básicas
- [ ] P8 — Snapshots/backups del server + plan de recuperación
- [ ] P5/P6 — SSH restringido + usuario no-root (recomendado)
- [ ] P15 — Stress test OK

## Notas operativas

- **Dependencia dura Cloudflare:** los dominios DEBEN quedar proxied (naranja) → `159.203.26.217`, SSL mode **Full**. Si se sacan del proxy o cambia la IP del origin, el sitio cae (origin cerrado a IPs de CF). Ver checklist para el admin de CF en el chat/plan.
- **Reboot seguro:** al reiniciar, el stack vuelve solo (contenedores `unless-stopped`, `cf-origin-lock.service`, ufw). Verificar tras el reboot: `docker compose ps`, acceso vía CF, y `iptables -L DOCKER-USER | grep cf-lock`.
