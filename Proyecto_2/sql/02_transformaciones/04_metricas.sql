-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/02_transformaciones/04_metricas.sql
-- Objetivo  : (1) Materializar la tabla de hechos limpia y tipada en nuestro
--             proyecto, (2) validar que las transformaciones no corrompieron
--             datos, (3) calcular métricas descriptivas globales y
--             (4) construir las capas agregadas pequeñas que usará el
--             dashboard (Looker Studio consulta agregados, no 36 M de filas).
-- Costo     : Bloque 1 = aprox. 6.97 GB (único escaneo completo de la tabla
--             pública en todo el proyecto). Bloques 2 y 6 = 0 bytes.
--             Bloque 3 = aprox. 0.5 GB. Bloques 4 y 5 = leen fact_trips_std
--             (aprox. 3 GB en total entre todos).
-- Almacenamiento sandbox (límite 10 GB): fact_trips_std ocupará aprox. 3 GB.
--             Verificar tamaño en el tab Details tras el bloque 1.
-- Evidencias: evidencia_04_creacion_std.png (bloque 1),
--             evidencia_04_retencion.png y evidencia_04_casts.png (bloque 2),
--             evidencia_04_metricas_globales.png (bloque 3),
--             evidencia_04_agregados.png (bloque 6).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- BLOQUE 1: TABLA DE HECHOS LIMPIA Y TIPADA (baseline sin optimizar).
--
-- Reglas de limpieza aplicadas (justificación en README, sección 2):
--   L1 duracion 1-240 min y dropoff > pickup : errores de captura del reloj.
--   L2 distancia 0.1-100 mi                  : viajes sin GPS o implausibles.
--   L3 pasajeros 1-9                         : 0 o NULL es registro inválido.
--   L4 tarifa [2.5, 500] y total [2.5, 1000] : mínimo legal NYC es 2.5 USD.
--   L5 total >= tarifa                       : el total nunca puede ser
--                                              menor que la tarifa de medidor.
--   L6 zonas 1-265 y códigos legibles        : IDs fuera del catálogo TLC.
--
-- Transformaciones de tipo (crítico, ver evidencia_01_schema):
--   rate_code / payment_type / vendor_id son STRING con formato '1.0',
--   por lo que se aplica doble cast SAFE_CAST(STRING -> FLOAT64 -> INT64).
--   Los montos NUMERIC se convierten a FLOAT64 para BigQuery ML y Looker.
--
-- Columnas eliminadas y por qué (ahorro de almacenamiento en sandbox):
--   store_and_fwd_flag      : solo útil para auditoría; ya medida en 03_calidad.
--   mta_tax                 : constante 0.5 USD, varianza cero, no informa.
--   improvement_surcharge   : constante 0.3 USD, varianza cero, no informa.
--   airport_fee             : reconstruible con la bandera is_airport_pickup.
--
-- Se conservan TODOS los rate_code y payment_type válidos: los filtros por
-- modelo (rate_code = 1, payment_type = 1) se aplican después, no aquí.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`
OPTIONS(description='Tabla de hechos limpia, tipada y SIN optimizar. Baseline del benchmark de la fase 3.')
AS
SELECT
  SAFE_CAST(SAFE_CAST(vendor_id AS FLOAT64) AS INT64)           AS vendor_id,
  pickup_datetime,
  dropoff_datetime,
  DATE(pickup_datetime)                                         AS pickup_date,
  passenger_count,
  CAST(trip_distance AS FLOAT64)                                AS trip_distance,
  SAFE_CAST(SAFE_CAST(rate_code AS FLOAT64) AS INT64)           AS rate_code,
  SAFE_CAST(SAFE_CAST(payment_type AS FLOAT64) AS INT64)        AS payment_type,
  CAST(fare_amount AS FLOAT64)                                  AS fare_amount,
  CAST(extra AS FLOAT64)                                        AS extra,
  CAST(tip_amount AS FLOAT64)                                   AS tip_amount,
  CAST(tolls_amount AS FLOAT64)                                 AS tolls_amount,
  CAST(congestion_surcharge AS FLOAT64)                         AS congestion_surcharge,
  CAST(total_amount AS FLOAT64)                                AS total_amount,
  SAFE_CAST(SAFE_CAST(pickup_location_id AS FLOAT64) AS INT64)  AS pickup_location_id,
  SAFE_CAST(SAFE_CAST(dropoff_location_id AS FLOAT64) AS INT64) AS dropoff_location_id,
  TIMESTAMP_DIFF(dropoff_datetime, pickup_datetime, MINUTE)     AS trip_duration_minutes,
  SAFE_DIVIDE(CAST(tip_amount AS FLOAT64),
              NULLIF(CAST(fare_amount AS FLOAT64), 0))          AS tip_ratio
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`
WHERE pickup_datetime IS NOT NULL
  AND dropoff_datetime IS NOT NULL
  AND dropoff_datetime > pickup_datetime
  AND TIMESTAMP_DIFF(dropoff_datetime, pickup_datetime, MINUTE) BETWEEN 1 AND 240
  AND trip_distance BETWEEN 0.1 AND 100
  AND passenger_count BETWEEN 1 AND 9
  AND fare_amount  BETWEEN 2.5 AND 500
  AND total_amount BETWEEN 2.5 AND 1000
  AND total_amount >= fare_amount
  AND SAFE_CAST(SAFE_CAST(pickup_location_id AS FLOAT64) AS INT64)  BETWEEN 1 AND 265
  AND SAFE_CAST(SAFE_CAST(dropoff_location_id AS FLOAT64) AS INT64) BETWEEN 1 AND 265
  AND SAFE_CAST(SAFE_CAST(rate_code AS FLOAT64) AS INT64)    IS NOT NULL
  AND SAFE_CAST(SAFE_CAST(payment_type AS FLOAT64) AS INT64) BETWEEN 1 AND 6;


-- ----------------------------------------------------------------------------
-- BLOQUE 2a: Tasa de retención. Cuántos registros sobreviven la limpieza.
-- 0 bytes: COUNT sobre tabla propia usa metadatos.
-- Capturar como evidencia_04_retencion.png y anotar pct en el README.
-- ----------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`) AS filas_limpias,
  36256539                                                               AS filas_publicas,
  36256539 - (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`) AS filas_descartadas,
  ROUND(100 * (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`) / 36256539, 2) AS pct_conservado;

-- ----------------------------------------------------------------------------
-- BLOQUE 2b: Integridad de casts y cobertura tras la transformación.
-- Resultado esperado: todos los conteos de nulos en 0 (prueba de que el
-- doble cast funcionó y no destruimos códigos en el camino).
-- Capturar como evidencia_04_casts.png.
-- ----------------------------------------------------------------------------
SELECT
  COUNTIF(vendor_id IS NULL)         AS vendor_nulos,
  COUNTIF(rate_code IS NULL)         AS rate_code_nulos,
  COUNTIF(payment_type IS NULL)      AS payment_type_nulos,
  COUNTIF(pickup_location_id IS NULL) AS zona_origen_nulas,
  COUNTIF(dropoff_location_id IS NULL) AS zona_destino_nulas,
  COUNT(DISTINCT rate_code)          AS rate_codes_distintos,
  COUNT(DISTINCT payment_type)       AS payment_types_distintos,
  MIN(pickup_date)                   AS desde,
  MAX(pickup_date)                   AS hasta
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`;


-- ----------------------------------------------------------------------------
-- BLOQUE 3: MÉTRICAS DESCRIPTIVAS GLOBALES sobre la tabla limpia.
-- Usa APPROX_QUANTILES (percentiles aproximados): con 30 M de filas el
-- cálculo exacto de percentiles es costoso e innecesario para exploración.
-- Capturar como evidencia_04_metricas_globales.png.
-- ----------------------------------------------------------------------------
SELECT
  COUNT(*)                          AS n_viajes,
  ROUND(AVG(fare_amount), 2)        AS fare_promedio,
  ROUND(STDDEV(fare_amount), 2)     AS fare_desviacion,
  ROUND(AVG(trip_distance), 2)      AS distancia_promedio_mi,
  ROUND(AVG(trip_duration_minutes), 2) AS duracion_promedio_min,
  ROUND(AVG(SAFE_DIVIDE(trip_distance, NULLIF(trip_duration_minutes / 60, 0))), 2) AS velocidad_promedio_mph,
  ROUND(AVG(tip_ratio), 4)          AS tip_ratio_promedio,
  ROUND(AVG(passenger_count), 2)    AS pasajeros_promedio,
  ROUND(AVG(total_amount), 2)       AS total_promedio,
  APPROX_QUANTILES(fare_amount, 100)[OFFSET(50)]  AS fare_p50,
  APPROX_QUANTILES(fare_amount, 100)[OFFSET(90)]  AS fare_p90,
  APPROX_QUANTILES(fare_amount, 100)[OFFSET(99)]  AS fare_p99,
  APPROX_QUANTILES(trip_distance, 100)[OFFSET(50)] AS distancia_p50,
  APPROX_QUANTILES(trip_distance, 100)[OFFSET(95)] AS distancia_p95,
  APPROX_QUANTILES(trip_duration_minutes, 100)[OFFSET(95)] AS duracion_p95
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`;


-- ----------------------------------------------------------------------------
-- BLOQUE 4: DIMENSIÓN DE ZONAS (tabla pequeña, ~265 filas).
-- Convierte IDs numéricos en nombres de zona y borough para análisis
-- geográfico y para el dashboard.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.dim_zones`
OPTIONS(description='Dimensión de zonas de taxi TLC: id, nombre y borough')
AS
SELECT
  zone_id   AS location_id,
  zone_name AS zone,
  borough
FROM `bigquery-public-data.new_york_taxi_trips.taxi_zone_geom`;


-- ----------------------------------------------------------------------------
-- BLOQUE 5a: AGREGADO DIARIO. Serie temporal base del dashboard y del
-- modelo de forecast. Tabla pequeña (~365 filas).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.agg_daily` AS
SELECT
  pickup_date,
  EXTRACT(DAYOFWEEK FROM pickup_datetime) AS dow,
  IF(EXTRACT(DAYOFWEEK FROM pickup_datetime) IN (1, 7), 1, 0) AS is_weekend,
  COUNT(*)                                   AS trip_count,
  ROUND(SUM(fare_amount), 2)                 AS revenue_fare,
  ROUND(SUM(total_amount), 2)                AS revenue_total,
  ROUND(SUM(tip_amount), 2)                  AS revenue_tips,
  ROUND(AVG(trip_distance), 2)               AS distancia_promedio,
  ROUND(AVG(trip_duration_minutes), 2)       AS duracion_promedio,
  COUNT(DISTINCT pickup_location_id)         AS zonas_activas
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`
GROUP BY 1, 2, 3;

-- ----------------------------------------------------------------------------
-- BLOQUE 5b: PERFIL HORARIO x DÍA DE SEMANA. Detecta picos de demanda y
-- congestión (matriz 7 x 24 = 168 filas). Base del heatmap del dashboard.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.agg_hourly_profile` AS
SELECT
  EXTRACT(DAYOFWEEK FROM pickup_datetime) AS pickup_dow,
  FORMAT_DATE('%a', DATE(pickup_datetime)) AS nombre_dia,
  EXTRACT(HOUR FROM pickup_datetime)       AS pickup_hour,
  COUNT(*)                                 AS n_viajes,
  ROUND(AVG(fare_amount), 2)               AS fare_promedio,
  ROUND(AVG(trip_distance), 2)             AS distancia_promedio,
  ROUND(AVG(trip_duration_minutes), 2)     AS duracion_promedio,
  ROUND(AVG(SAFE_DIVIDE(trip_distance, NULLIF(trip_duration_minutes / 60, 0))), 2) AS velocidad_mph,
  ROUND(AVG(tip_ratio), 4)                 AS tip_ratio_promedio
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`
GROUP BY 1, 2, 3;

-- ----------------------------------------------------------------------------
-- BLOQUE 5c: AGREGADO POR ZONA con ranking mediante función de ventana.
-- Demuestra WINDOW FUNCTIONS sobre agregados (criterio 1.2).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.agg_zones` AS
WITH origen AS (
  SELECT
    pickup_location_id        AS location_id,
    COUNT(*)                  AS viajes_origen,
    AVG(fare_amount)          AS fare_promedio_origen,
    AVG(trip_distance)        AS distancia_promedio_origen,
    AVG(tip_ratio)            AS tip_ratio_origen
  FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`
  GROUP BY 1
),
destino AS (
  SELECT dropoff_location_id AS location_id, COUNT(*) AS viajes_destino
  FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`
  GROUP BY 1
)
SELECT
  z.location_id,
  z.zone,
  z.borough,
  o.viajes_origen,
  d.viajes_destino,
  ROUND(o.fare_promedio_origen, 2)         AS fare_promedio,
  ROUND(o.distancia_promedio_origen, 2)    AS distancia_promedio,
  ROUND(o.tip_ratio_origen, 4)             AS tip_ratio_promedio,
  RANK() OVER (ORDER BY o.viajes_origen DESC) AS rank_origen
FROM origen o
LEFT JOIN destino d USING (location_id)
LEFT JOIN `ss2-2026-pareja14.taxi_ss2_2026.dim_zones` z USING (location_id);

-- ----------------------------------------------------------------------------
-- BLOQUE 5d: COMPARACIÓN POR MÉTODO DE PAGO. Consolida el hallazgo de que
-- el efectivo registra propina cero (justificación del filtro del modelo
-- de clasificación). Tabla de ~6 filas.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.agg_payment` AS
SELECT
  CASE payment_type
    WHEN 1 THEN 'Tarjeta de credito'
    WHEN 2 THEN 'Efectivo'
    WHEN 3 THEN 'Sin cargo'
    WHEN 4 THEN 'Disputa'
    WHEN 5 THEN 'Desconocido'
    WHEN 6 THEN 'Viaje anulado'
    ELSE 'Otro'
  END                                              AS metodo_pago,
  COUNT(*)                                         AS n_viajes,
  ROUND(AVG(fare_amount), 2)                       AS fare_promedio,
  ROUND(AVG(tip_amount), 3)                        AS propina_promedio,
  ROUND(AVG(tip_ratio), 4)                         AS tip_ratio_promedio,
  ROUND(100 * COUNTIF(tip_amount > 0) / COUNT(*), 2) AS pct_con_propina
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`
GROUP BY 1;

-- ----------------------------------------------------------------------------
-- BLOQUE 5e: TOP 25 RUTAS ORIGEN-DESTINO. Doble JOIN con la dimensión de
-- zonas para nombres legibles. Tabla pequeña para el dashboard.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.agg_routes` AS
SELECT
  zp.zone                          AS zona_origen,
  zd.zone                          AS zona_destino,
  zp.borough                       AS borough_origen,
  zd.borough                       AS borough_destino,
  COUNT(*)                         AS n_viajes,
  ROUND(AVG(trip_distance), 2)     AS distancia_promedio,
  ROUND(AVG(fare_amount), 2)       AS fare_promedio,
  ROUND(AVG(trip_duration_minutes), 2) AS duracion_promedio
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std` t
LEFT JOIN `ss2-2026-pareja14.taxi_ss2_2026.dim_zones` zp ON zp.location_id = t.pickup_location_id
LEFT JOIN `ss2-2026-pareja14.taxi_ss2_2026.dim_zones` zd ON zd.location_id = t.dropoff_location_id
GROUP BY 1, 2, 3, 4
ORDER BY n_viajes DESC
LIMIT 25;


-- ----------------------------------------------------------------------------
-- BLOQUE 6: VERIFICACIÓN FINAL DE LAS CAPAS AGREGADAS.
-- 0 bytes. Los conteos esperados: agg_daily ~365, agg_hourly_profile <=168,
-- agg_zones ~265, agg_payment <=6, agg_routes 25, dim_zones ~265.
-- Capturar como evidencia_04_agregados.png.
-- ----------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.dim_zones`)         AS filas_dim_zones,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.agg_daily`)         AS filas_agg_daily,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.agg_hourly_profile`) AS filas_agg_hourly,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.agg_zones`)         AS filas_agg_zones,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.agg_payment`)       AS filas_agg_payment,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.agg_routes`)        AS filas_agg_routes;


-- ----------------------------------------------------------------------------
-- NOTAS DE INTERPRETACIÓN PARA EL README (llenar con los números reales):
-- H-temporal  : la demanda concentra picos en las horas __ y __; la velocidad
--               promedio cae de __ mph a __ mph en esos bloques (congestión).
-- H-geográfico: las zonas __ y __ (borough __) concentran el __% de los
--               orígenes (ver rank_origen en agg_zones).
-- H-económico : el método __ registra pct_con_propina = 0.00, confirmando
--               que la propina en efectivo no se captura en el sistema TLC.
-- H-categórico: el __% de los viajes usa rate_code 1 (tarifa de medidor).
-- H-calidad   : se conservó el __% de los registros públicos (bloque 2a).
-- SIGUIENTE PASO: sql/03_optimizacion/05_tabla_opt.sql
-- ----------------------------------------------------------------------------