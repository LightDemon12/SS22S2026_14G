-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/03_optimizacion/07_benchmark.sql
-- Objetivo  : Medir con las MISMAS 5 consultas el costo de procesamiento en
--             la tabla estándar y en la optimizada, demostrar la reducción
--             de bytes (rúbrica 1.3 y 2.5) y liberar almacenamiento al final.
-- Protocolo de ejecución y captura (importante para las evidencias):
--   a) Ejecutar los bloques EN ORDEN: B1_std, B1_opt, B2_std, B2_opt, ...
--   b) Antes de cada Run, dejar visible la línea "This query will process X".
--   c) Después de cada Run, abrir la pestaña "Job information" y capturar
--      bytes procesados y tiempo transcurrido junto con el SQL del editor.
--   d) Una captura por bloque: evidencia_07_B1_std.png ... evidencia_07_B5b.png
-- Costo total estimado del benchmark: aprox. 11-13 GB procesados
--   (la tabla estándar no puede podar: cada consulta lee las columnas
--    completas; la optimizada lee solo particiones y bloques pertinentes).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- B1: PODADO DE PARTICIONES. Filtro de rango temporal (1 mes).
-- Esperado: std lee las columnas completas de TODO el año; opt lee solo
-- la partición de marzo (~1/12 de las filas). Reducción esperada > 85%.
-- ----------------------------------------------------------------------------
-- B1_std
SELECT pickup_date, COUNT(*) AS viajes, ROUND(SUM(total_amount), 2) AS revenue
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`
WHERE pickup_date BETWEEN '2022-03-01' AND '2022-03-31'
GROUP BY pickup_date
ORDER BY pickup_date;

-- B1_opt  (misma consulta, única diferencia: la tabla)
SELECT pickup_date, COUNT(*) AS viajes, ROUND(SUM(total_amount), 2) AS revenue
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_opt`
WHERE pickup_date BETWEEN '2022-03-01' AND '2022-03-31'
GROUP BY pickup_date
ORDER BY pickup_date;


-- ----------------------------------------------------------------------------
-- B2: PODADO DE PARTICIONES + CLUSTERING. Rango de 3 meses y 10 zonas.
-- Esperado: opt primero poda a 3 particiones mensuales y dentro de ellas
-- solo lee los bloques que contienen esas 10 zonas de origen.
-- Esta es la consulta que demuestra el aporte ESPECÍFICO del clustering.
-- ----------------------------------------------------------------------------
-- B2_std
SELECT
  pickup_location_id,
  COUNT(*)                       AS viajes,
  ROUND(AVG(fare_amount), 2)     AS fare_promedio,
  ROUND(AVG(trip_distance), 2)   AS dist_promedio
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`
WHERE pickup_date BETWEEN '2022-06-01' AND '2022-08-31'
  AND pickup_location_id IN (132, 138, 237, 238, 239, 161, 142, 141, 170, 114)
GROUP BY pickup_location_id
ORDER BY viajes DESC;

-- B2_opt
SELECT
  pickup_location_id,
  COUNT(*)                       AS viajes,
  ROUND(AVG(fare_amount), 2)     AS fare_promedio,
  ROUND(AVG(trip_distance), 2)   AS dist_promedio
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_opt`
WHERE pickup_date BETWEEN '2022-06-01' AND '2022-08-31'
  AND pickup_location_id IN (132, 138, 237, 238, 239, 161, 142, 141, 170, 114)
GROUP BY pickup_location_id
ORDER BY viajes DESC;


-- ----------------------------------------------------------------------------
-- B3: FILTRO COMBINADO fecha + zona origen + agrupación por destino.
-- Caso de uso real del dashboard: "¿a dónde va quien sale del aeropuerto
-- en septiembre?". Esperado: la mayor reducción del benchmark (> 95%),
-- porque actúan partición y ambas columnas de clustering a la vez.
-- ----------------------------------------------------------------------------
-- B3_std
SELECT
  pickup_location_id,
  dropoff_location_id,
  COUNT(*)                     AS viajes,
  ROUND(SUM(fare_amount), 2)   AS revenue
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`
WHERE pickup_date BETWEEN '2022-09-01' AND '2022-09-30'
  AND pickup_location_id = 132
GROUP BY 1, 2
ORDER BY viajes DESC
LIMIT 25;

-- B3_opt
SELECT
  pickup_location_id,
  dropoff_location_id,
  COUNT(*)                     AS viajes,
  ROUND(SUM(fare_amount), 2)   AS revenue
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_opt`
WHERE pickup_date BETWEEN '2022-09-01' AND '2022-09-30'
  AND pickup_location_id = 132
GROUP BY 1, 2
ORDER BY viajes DESC
LIMIT 25;


-- ----------------------------------------------------------------------------
-- B4: AGREGACIÓN PESADA SOBRE 2 MESES (perfil hora x semana).
-- Esperado: opt lee 2 de 12 meses (~83% menos bytes). Demuestra que la
-- optimización también beneficia consultas analíticas amplias, no solo
-- filtros puntuales.
-- ----------------------------------------------------------------------------
-- B4_std
SELECT
  FORMAT_DATE('%Y-%u', pickup_date)          AS semana,
  EXTRACT(HOUR FROM pickup_datetime)         AS hora,
  COUNT(*)                                   AS viajes,
  ROUND(AVG(trip_duration_minutes), 2)       AS duracion_prom
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`
WHERE pickup_date BETWEEN '2022-01-01' AND '2022-02-28'
GROUP BY 1, 2
ORDER BY 1, 2;

-- B4_opt
SELECT
  FORMAT_DATE('%Y-%u', pickup_date)          AS semana,
  EXTRACT(HOUR FROM pickup_datetime)         AS hora,
  COUNT(*)                                   AS viajes,
  ROUND(AVG(trip_duration_minutes), 2)       AS duracion_prom
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_opt`
WHERE pickup_date BETWEEN '2022-01-01' AND '2022-02-28'
GROUP BY 1, 2
ORDER BY 1, 2;


-- ----------------------------------------------------------------------------
-- B5: COLUMN PRUNING (complemento de la optimización, rúbrica 2.5).
-- B5a lee 2 columnas de un solo día; B5b lee LAS 18 columnas del mismo día.
-- Misma tabla optimizada, mismo filtro: la diferencia de bytes demuestra
-- que en BigQuery el costo depende de las columnas referenciadas.
-- Lección para el README: nunca usar SELECT * en producción.
-- ----------------------------------------------------------------------------
-- B5a (consulta eficiente)
SELECT COUNT(*) AS viajes, ROUND(AVG(trip_distance), 2) AS dist_prom
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_opt`
WHERE pickup_date = '2022-07-15';

-- B5b (mala práctica, se ejecuta UNA sola vez para documentar el contraste)
SELECT *
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_opt`
WHERE pickup_date = '2022-07-15'
LIMIT 100;


-- ----------------------------------------------------------------------------
-- BLOQUE FINAL 1: EXTRACCIÓN AUDITABLE DE MÉTRICAS DESDE EL HISTORIAL DE JOBS.
-- Construye la tabla comparativa sin transcribir números a mano.
-- Requiere que los jobs del benchmark estén en las últimas 2 horas.
-- Capturar como evidencia_07_jobs.png.
-- ----------------------------------------------------------------------------
SELECT
  creation_time,
  ROUND(total_bytes_processed / POW(1024, 2), 1)   AS mb_procesados,
  total_bytes_processed                            AS bytes_procesados,
  TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) AS elapsed_ms,
  SUBSTR(REPLACE(query, '\n', ' '), 40, 95)        AS fragmento_query
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)
  AND state = 'DONE'
  AND statement_type = 'SELECT'
ORDER BY creation_time;

-- Plantilla para el README (llenar con los bytes de cada captura):
-- | Consulta | Bytes std | Bytes opt | Reducción % | Tiempo std | Tiempo opt |
-- | B1 mes   |           |           |             |            |            |
-- | B2 zonas |           |           |             |            |            |
-- | B3 ruta  |           |           |             |            |            |
-- | B4 agreg |           |           |             |            |            |
-- | B5a/B5b  |     (column pruning: comparar B5a vs B5b)        |            |

-- ----------------------------------------------------------------------------
-- BLOQUE FINAL 2: LIBERACIÓN DE ALMACENAMIENTO.
-- La tabla estándar ya cumplió su propósito: sus métricas quedan en las
-- capturas y en el historial de jobs (bloque anterior). Eliminarla libera
-- aprox. 3 GB para los modelos de BigQuery ML de la fase 4.
-- Capturar como evidencia_07_drop.png.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`;

-- ----------------------------------------------------------------------------
-- BLOQUE FINAL 3: ESTADO FINAL DE ALMACENAMIENTO DEL DATASET.
-- Verificar que el total quede holgado por debajo de 10 GB (sandbox).
-- Capturar como evidencia_07_storage_final.png.
-- ----------------------------------------------------------------------------
SELECT
  table_name,
  row_count                           AS filas,
  ROUND(size_bytes / POW(1024, 3), 2) AS gb_logicos
FROM `ss2-2026-pareja14.taxi_ss2_2026.INFORMATION_SCHEMA.TABLES`
ORDER BY size_bytes DESC;