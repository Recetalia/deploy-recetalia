# Bases de datos por servicio — verificación pre-deploy

Verificación realizada antes del deploy a pre-prod del 2026-05-28. Documenta **qué base de datos lee cada API en el deploy pre-prod**, cómo se resuelve la config, y los riesgos abiertos.

## Resumen

| API | Cluster / host | Puerto | DBs | Usuario | Source de la config |
|---|---|---|---|---|---|
| `recetalia-api-rest` | `143.110.212.167` | 3306 | `recetali_receta`, `recetali_dnma` | `recetali_receuser` | Override por env vars en `docker-compose.yml` (`SPRING_DATASOURCE_*`, `SPRING_DNMA_DATASOURCE_*`) desde `.env` del server |
| `security-api-recetalia` | `recetaliadbpreproduccion-do-user-2735981-0.i.db.ondigitalocean.com` (DO managed) | 25060 | `securitydb` | `doadmin` | `application.yml` baked en el JAR (no hay env vars override en el bloque del compose) |
| `transversal-recetalia-api` | ídem DO managed `recetaliadbpreproduccion-…` | 25060 | `recetali_receta`, `recetali_dnma` | `doadmin` | `application.yml` baked en el JAR (no hay env vars override en el bloque del compose) |

## Cómo se resuelve la config por servicio

### `transversal-recetalia-api`

- Source único: [`applications/app-service/src/main/resources/application.yml`](../../../transversal-recetalia-api/applications/app-service/src/main/resources/application.yml).
- Claves leídas en runtime:
  - `spring.r2dbc.url|username|password` → R2DBC pool de `recetali_receta`.
  - `dnma.datasource.url|username|password` → R2DBC pool de `recetali_dnma` (catálogo DNMA UY).
- El bloque `transversal-recetalia-api:` del `docker-compose.yml` **no define `environment:`** → ningún override de env vars. El JAR usa los valores del yml tal cual.
- Por lo tanto: lo que diga `application.yml` es lo que se conecta en pre-prod.
- Estado actual: ambos pools apuntan al cluster DO managed con `preproduccion` en el hostname.

### `security-api-recetalia`

- Mismo patrón: `application.yml` baked, sin env vars de DB en el compose.
- Conecta al mismo cluster DO managed que transversal, DB `securitydb`.

### `recetalia-api-rest`

- Único de los tres que **sí recibe overrides** por env vars desde `docker-compose.yml`:
  - `SPRING_DATASOURCE_URL` ← `${RECETALIA_DB_URL}` (de `.env`)
  - `SPRING_DATASOURCE_USERNAME` ← `${RECETALIA_DB_USER}`
  - `SPRING_DATASOURCE_PASSWORD` ← `${RECETALIA_DB_PASSWORD}`
  - `SPRING_DNMA_DATASOURCE_*` ← análogos para la DB DNMA.
- Estado actual en `.env` del server: los `RECETALIA_DB_URL`/`RECETALIA_DNMA_DB_URL` apuntan al cluster DO managed (mismo que transversal), pero el `application.yml` interno apunta a `143.110.212.167:3306`. **Verificar cuál gana** corriendo `docker exec recetalia-api-rest env | grep -i datasource` después del deploy — Spring Boot da precedencia a env vars sobre `application.yml`, así que debería ganar la del `.env`.

## Evidencia de que el cluster DO es pre-prod (no prod)

| Señal | Detalle |
|---|---|
| Hostname | `recetaliadbpreproduccion-do-user-2735981-0.i.db.ondigitalocean.com` — literalmente contiene `preproduccion` |
| Credenciales | `doadmin` / `REDACTED_SET_IN_DEPLOY` commiteadas en plain text en los repos (un secreto productivo nunca debería viajar así) |
| Catalogación del plan | [single-server-deploy.md](../plans/single-server-deploy.md#dbs-externas-no-containerizadas) la lista como "DO managed pre-prod" |

**Sigue pendiente** una verificación de datos para descartar que sea un mirror de prod con datos reales replicados. Queries de sanity recomendadas (ejecutar puntualmente, no automatizar):

```sql
-- Volumen y rango temporal — comparar contra prod conocida
SELECT COUNT(*) AS prescriptions, MIN(created_at), MAX(created_at) FROM prescription;
SELECT COUNT(*) AS dispensations, MAX(created_at) FROM dispensation;

-- ¿Hay actividad reciente de farmacias reales o solo testers conocidos?
SELECT pharmacy_id, COUNT(*) FROM dispensation
 WHERE created_at > CURDATE() - INTERVAL 7 DAY
 GROUP BY 1 ORDER BY 2 DESC LIMIT 10;
```

## Riesgos abiertos

1. **`recetali_receta` está en 2 hosts distintos** — `143.110.212.167` (usado por `recetalia-api-rest`) y el cluster DO (usado por `transversal-recetalia-api`). Si los datos difieren o el schema drifta, los dos servicios pueden ver estados inconsistentes. Mitigación pendiente: unificar en una iteración futura (ver [single-server-deploy.md](../plans/single-server-deploy.md)).
2. **Credenciales en plain text** en los `application.yml` de cada API y en el `.env` del server. Rotación + secret manager pendiente (plan separado, fuera de alcance del deploy actual).
3. **`spring.jpa.datasource.read-only: true`** en el `application.yml` de transversal es no-op (transversal usa R2DBC, no JPA). Si en algún momento se quiere garantizar read-only para evitar escrituras accidentales en pre-prod, hay que aplicarlo a nivel del usuario MySQL.
4. **DNMA datasource con `ssl: false`** en transversal — DO managed normalmente fuerza TLS. Si la conexión falla por TLS, el flag tendría que cambiar a `true` o configurarse `sslMode`. Verificar logs después del deploy.

## Verificación post-deploy

Después de cada `./scripts/deploy.sh`, validar que las APIs efectivamente conectan a las DBs esperadas:

```bash
ssh root@138.197.150.98 '
  # transversal — debería ver el hostname DO en los logs de R2DBC al arrancar
  docker logs transversal-recetalia-api 2>&1 | grep -iE "r2dbc|connection|database" | head -10

  # recetalia-api-rest — debe haber ganado el override del .env
  docker exec recetalia-api-rest env | grep -iE "datasource_url|dnma_url"

  # security — mismo cluster que transversal
  docker logs security-api-recetalia 2>&1 | grep -iE "hikari|datasource|jdbc" | head -10
'
```
