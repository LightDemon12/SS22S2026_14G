-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/03_optimizacion/07_benchmark.sql
-- Objetivo  : Medir con las MISMAS 5 consultas el costo de procesamiento en
--             la tabla estándar y en la optimizada y demostrar la reducción
--             de bytes (rúbrica 1.3 y 2.5) con UNA SOLA CAPTURA final.
-- ----------------------------------------------------------------------------
-- TÉCNICA DE MEDICIÓN: cada consulta de prueba lleva en su PRIMERA línea un
--   marcador de comentario "-- BMK:<prueba>:<variante>". Ese comentario queda
--   registrado textualmente en la columna query del historial de jobs, lo que
--   permite clasificar y comparar los jobs después, sin capturas intermedias.
-- PROTOCOLO DE EJECUCIÓN:
--   1) Ejecutar EN ORDEN las 10 consultas marcadas (B1 STD, B1 OPT, B2 STD,
--      B2 OPT, B3 STD, B3 OPT, B4 STD, B4 OPT, B5 OPT, B5 STD). Si ejecutas
--      por selección de texto, INCLUYE la línea del marcador en la selección.
--      Ninguna de estas ejecuciones requiere captura.
--   2) Ejecutar el BLOQUE FINAL 1: pivotea el historial y produce la tabla
--      comparativa completa (bytes, reducción %, tiempos). ESA es la captura
--      oficial del benchmark: evidencia_07_benchmark_completo.png.
--   3) Captura opcional del editor con un par visible (por ejemplo B1 STD y
--      B1 OPT) para probar que el SQL es idéntico salvo el nombre de tabla:
--      evidencia_07_par_identico.png.
-- Costo total estimado: aprox. 11-13 GB procesados (unos USD 0.08 on-demand).
-- Almacenamiento: con facturación activa ya no es obligatorio eliminar
--   fact_trips_std; el DROP queda comentado como opción al final.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- B1: PODADO DE PARTICIONES. Filtro de rango temporal (1 mes).
-- Esperado: std lee las columnas completas de TODO el año; opt lee solo las
-- particiones de marzo (~31 de 335). Reducción esperada > 85%.
-- ----------------------------------------------------------------------------
-- BMK:B1:STD
SELECT pickup_date, COUNT(*) AS viajes, ROUND(SUM(total_amount), 2) AS revenue
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_std`
WHERE pickup_date BETWEEN '2022-03-01' AND '2022-03-31'
GROUP BY pickup_date
ORDER BY pickup_date;

-- BMK:B1:OPT
SELECT pickup_date, COUNT(*) AS viajes, ROUND(SUM(total_amount), 2) AS revenue
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_opt`
WHERE pickup_date BETWEEN '2022-03-01' AND '2022-03-31'
GROUP BY pickup_date
ORDER BY pickup_date;


-- ----------------------------------------------------------------------------
-- B2: PODADO DE PARTICIONES + CLUSTERING. Rango de 3 meses y 10 zonas.
-- Esperado: opt poda primero a ~92 particiones diarias y dentro de ellas lee
-- solo los bloques que contienen esas 10 zonas de origen. Esta es la
-- consulta que demuestra el aporte ESPECÍFICO del clustering.
-- ----------------------------------------------------------------------------
-- BMK:B2:STD
SELECT
  pickup_location_id,
  COUNT(*)                       AS viajes,
  ROUND(AVG(fare_amount), 2)     AS fare_promedio,
  ROUND(AVG(trip_distance), 2)   AS dist_promedio
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_std`
WHERE pickup_date BETWEEN '2022-06-01' AND '2022-08-31'
  AND pickup_location_id IN (132, 138, 237, 238, 239, 161, 142, 141, 170, 114)
GROUP BY pickup_location_id
ORDER BY viajes DESC;

-- BMK:B2:OPT
SELECT
  pickup_location_id,
  COUNT(*)                       AS viajes,
  ROUND(AVG(fare_amount), 2)     AS fare_promedio,
  ROUND(AVG(trip_distance), 2)   AS dist_promedio
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_opt`
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
-- BMK:B3:STD
SELECT
  pickup_location_id,
  dropoff_location_id,
  COUNT(*)                     AS viajes,
  ROUND(SUM(fare_amount), 2)   AS revenue
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_std`
WHERE pickup_date BETWEEN '2022-09-01' AND '2022-09-30'
  AND pickup_location_id = 132
GROUP BY 1, 2
ORDER BY viajes DESC
LIMIT 25;

-- BMK:B3:OPT
SELECT
  pickup_location_id,
  dropoff_location_id,
  COUNT(*)                     AS viajes,
  ROUND(SUM(fare_amount), 2)   AS revenue
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_opt`
WHERE pickup_date BETWEEN '2022-09-01' AND '2022-09-30'
  AND pickup_location_id = 132
GROUP BY 1, 2
ORDER BY viajes DESC
LIMIT 25;


-- ----------------------------------------------------------------------------
-- B4: AGREGACIÓN PESADA SOBRE 2 MESES (perfil hora x semana).
-- Esperado: opt lee 59 de 335 particiones (~82% menos bytes). Demuestra que
-- la optimización también beneficia consultas analíticas amplias.
-- ----------------------------------------------------------------------------
-- BMK:B4:STD
SELECT
  FORMAT_DATE('%Y-%u', pickup_date)          AS semana,
  EXTRACT(HOUR FROM pickup_datetime)         AS hora,
  COUNT(*)                                   AS viajes,
  ROUND(AVG(trip_duration_minutes), 2)       AS duracion_prom
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_std`
WHERE pickup_date BETWEEN '2022-01-01' AND '2022-02-28'
GROUP BY 1, 2
ORDER BY 1, 2;

-- BMK:B4:OPT
SELECT
  FORMAT_DATE('%Y-%u', pickup_date)          AS semana,
  EXTRACT(HOUR FROM pickup_datetime)         AS hora,
  COUNT(*)                                   AS viajes,
  ROUND(AVG(trip_duration_minutes), 2)       AS duracion_prom
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_opt`
WHERE pickup_date BETWEEN '2022-01-01' AND '2022-02-28'
GROUP BY 1, 2
ORDER BY 1, 2;


-- ----------------------------------------------------------------------------
-- B5: COLUMN PRUNING sobre la MISMA tabla optimizada (complemento, rúbrica
-- 2.5). Aquí la variante STD es la mala práctica (SELECT * sobre las 17
-- columnas de un día) y la OPT lee solo 2 columnas del mismo día. Misma
-- tabla y mismo filtro: la diferencia de bytes es puro costo de columnas.
-- Lección para el README: nunca usar SELECT * en producción.
-- ----------------------------------------------------------------------------
-- BMK:B5:OPT
SELECT COUNT(*) AS viajes, ROUND(AVG(trip_distance), 2) AS dist_prom
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_opt`
WHERE pickup_date = '2022-07-15';

-- BMK:B5:STD
SELECT *
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_opt`
WHERE pickup_date = '2022-07-15'
LIMIT 100;


-- ----------------------------------------------------------------------------
-- BLOQUE FINAL 1: TABLA COMPARATIVA AUDITABLE (LA ÚNICA CAPTURA OBLIGATORIA).
-- Lee el historial de jobs del día, clasifica por marcador BMK y pivotea las
-- dos variantes de cada prueba en una sola fila con bytes, reducción
-- porcentual y tiempos de ejecución. El filtro por prefijo
-- (query LIKE '-- BMK:%') excluye a esta propia consulta del resultado.
-- EVIDENCIA: evidencia_07_benchmark_completo.png
-- ----------------------------------------------------------------------------
-- Tabla comparativa sin marcadores: clasifica los jobs ya ejecutados por el
-- contenido característico de cada prueba. Excluye a esta propia consulta
-- (contiene INFORMATION_SCHEMA) y a los chequeos de __TABLES__.
WITH jobs AS (
  SELECT
    CASE
      WHEN query LIKE '%2022-03-01%' THEN 'B1'
      WHEN query LIKE '%2022-06-01%' THEN 'B2'
      WHEN query LIKE '%pickup_location_id = 132%' THEN 'B3'
      WHEN query LIKE '%FORMAT_DATE%' THEN 'B4'
      WHEN query LIKE '%2022-07-15%' AND query LIKE '%AVG(trip_distance)%' THEN 'B5'
      WHEN query LIKE '%2022-07-15%' AND query LIKE '%LIMIT 100%' THEN 'B5'
    END AS prueba,
    CASE
      WHEN query LIKE '%2022-07-15%' AND query LIKE '%AVG(trip_distance)%' THEN 'OPT'
      WHEN query LIKE '%2022-07-15%' AND query LIKE '%LIMIT 100%' THEN 'STD'
      WHEN query LIKE '%fact_trips_std%' THEN 'STD'
      WHEN query LIKE '%fact_trips_opt%' THEN 'OPT'
    END AS variante,
    total_bytes_processed                             AS bytes,
    TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) AS elapsed_ms
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
    AND state = 'DONE'
    AND statement_type = 'SELECT'
    AND (query LIKE '%fact_trips_std%' OR query LIKE '%fact_trips_opt%')
    AND query NOT LIKE '%INFORMATION_SCHEMA%'
    AND query NOT LIKE '%__TABLES__%'
)
SELECT
  prueba,
  MAX(IF(variante = 'STD', bytes, NULL))                          AS bytes_std,
  MAX(IF(variante = 'OPT', bytes, NULL))                          AS bytes_opt,
  ROUND(MAX(IF(variante = 'STD', bytes, NULL)) / POW(1024, 2), 1) AS mb_std,
  ROUND(MAX(IF(variante = 'OPT', bytes, NULL)) / POW(1024, 2), 1) AS mb_opt,
  ROUND(100 * (1 - SAFE_DIVIDE(MAX(IF(variante = 'OPT', bytes, NULL)),
                               MAX(IF(variante = 'STD', bytes, NULL)))), 2) AS reduccion_pct,
  MAX(IF(variante = 'STD', elapsed_ms, NULL))                     AS ms_std,
  MAX(IF(variante = 'OPT', elapsed_ms, NULL))                     AS ms_opt
FROM jobs
WHERE prueba IS NOT NULL AND variante IS NOT NULL
GROUP BY prueba
ORDER BY prueba;


-- ----------------------------------------------------------------------------
-- BLOQUE FINAL 2 (OPCIONAL): LIBERACIÓN DE ALMACENAMIENTO.
-- Con facturación activa, mantener fact_trips_std cuesta aprox. USD 0.09 al
-- mes (4.23 GB a USD 0.02/GB/mes) y permite que el auxiliar repita la
-- comparación durante la calificación. Se recomienda NO ejecutarlo hasta
-- después de la revisión; descomentar solo si se desea liberar espacio:
-- ----------------------------------------------------------------------------
-- DROP TABLE IF EXISTS `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_std`;

-- ----------------------------------------------------------------------------
-- BLOQUE FINAL 3: ESTADO DE ALMACENAMIENTO DEL DATASET (captura opcional).
-- EVIDENCIA: evidencia_07_storage_final.png
-- ----------------------------------------------------------------------------
SELECT
  table_id,
  row_count                           AS filas,
  ROUND(size_bytes / POW(1024, 3), 2) AS gb_logicos
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.__TABLES__`
ORDER BY size_bytes DESC;