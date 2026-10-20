-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/04_ml/08_features.sql
-- Objetivo  : Construir la capa de características para BigQuery ML como
--             VISTAS (sin costo de almacenamiento) y documentar la
--             estrategia anti data leakage (rúbrica 1.6 y 2.3).
-- Costo     : Bloques 1-3 = 0 bytes (CREATE VIEW no procesa datos).
--             Bloques 4-6 = aprox. 0.6 GB en total (leen columnas puntuales
--             de fact_trips_opt a través de las vistas).
-- Evidencias: evidencia_08_split_balance.png (bloque 4),
--             evidencia_08_sin_solapamiento.png (bloque 5),
--             evidencia_08_balance_clases.png (bloque 6),
--             evidencia_08_inventario_variables.png (bloque 7).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ESTRATEGIA ANTI DATA LEAKAGE (documentar en README, sección 5.3):
--
-- 1) SPLIT TEMPORAL CUSTOM, no aleatorio. Los viajes de taxi son una serie
--    temporal con estacionalidad semanal y mensual. Un split RANDOM con
--    data_split_eval_fraction=0.2 colocaría días de diciembre en TRAIN y
--    días de marzo en EVAL: el modelo "vería el futuro" y su métrica quedaría
--    inflada. Con split temporal se reproduce el escenario real de
--    producción: entrenar con historia, predecir futuro.
-- 2) Proporciones: TRAIN 78% / EVAL 13% / TEST 9%. Equivale a un
--    data_split_eval_fraction efectivo de ~0.14 sobre TRAIN+EVAL, comparable
--    al 0.2 por defecto, pero sin romper el orden cronológico.
-- 3) Corte a mitad de mes (16-SEP): evita que TRAIN y EVAL compartan un día
--    completo, lo que filtraría el patrón diario exacto entre conjuntos.
-- 4) VARIABLES EXCLUIDAS POR FUGA (no entran a ningún modelo):
--    - total_amount  : suma determinista que incluye la etiqueta fare_amount.
--    - tip_amount    : componente de total_amount y origen de la etiqueta
--                      high_tip; conocerla equivale a conocer la respuesta.
--    - tip_ratio     : división tip_amount/fare_amount; misma razón.
--    - pickup_date y pickup_datetime crudas: el modelo memorizaría fechas;
--      se usan solo sus componentes (hora, día, mes) y la columna split_set
--      que define el particionamiento nunca es feature.
--    - mta_tax e improvement_surcharge: ya eliminadas en la fase 2 por
--      varianza cero (constantes 0.5 y 0.3 USD).
-- 5) SIN ESCALADO MANUAL: BigQuery ML estandariza features numéricas usando
--    únicamente el split TRAIN. Normalizar a mano con estadísticos de toda
--    la tabla sería fuga; por eso no se hace.
-- 6) FILTRO DE ETIQUETA DEGENERADA: high_tip solo es observable cuando hay
--    propina capturada, es decir payment_type = 1 (tarjeta). En efectivo el
--    sistema TLC registra tip_amount = 0 siempre; incluir esos viajes haría
--    que payment_type fuera un predictor trivial de la etiqueta.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- BLOQUE 1: VISTA MAESTRA DE CARACTERÍSTICAS.
-- Cada feature es información disponible ANTES o AL INICIO del viaje
-- (justificación exigida por rúbrica 2.3):
--   pickup_hour/dow/month, banderas horarias : momento del servicio.
--   trip_distance, duration, speed           : magnitud física del servicio.
--   boroughs, aeropuertos, zona caliente     : contexto geográfico.
--   extra, tolls, congestion                 : recargos vigentes al abordar.
--   distance_bucket                          : categorización no lineal de la
--                                              distancia para ayudar a los
--                                              modelos lineales.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_features` AS
SELECT
  -- Columna de split (NUNCA se usa como feature)
  CASE
    WHEN f.pickup_date < DATE '2022-09-16' THEN 'TRAIN'
    WHEN f.pickup_date < DATE '2022-11-01' THEN 'EVAL'
    ELSE 'TEST'
  END                                              AS split_set,
  -- Features temporales
  EXTRACT(HOUR FROM f.pickup_datetime)             AS pickup_hour,
  EXTRACT(DAYOFWEEK FROM f.pickup_datetime)        AS pickup_dow,
  EXTRACT(MONTH FROM f.pickup_datetime)            AS pickup_month,
  IF(EXTRACT(DAYOFWEEK FROM f.pickup_datetime) IN (1, 7), 1, 0) AS is_weekend,
  IF(EXTRACT(HOUR FROM f.pickup_datetime) BETWEEN 6 AND 9, 1, 0)  AS is_rush_am,
  IF(EXTRACT(HOUR FROM f.pickup_datetime) BETWEEN 16 AND 19, 1, 0) AS is_rush_pm,
  IF(EXTRACT(HOUR FROM f.pickup_datetime) >= 22
     OR EXTRACT(HOUR FROM f.pickup_datetime) < 5, 1, 0)           AS is_night,
  IF(f.pickup_date IN (DATE '2022-01-01', DATE '2022-01-17', DATE '2022-02-21',
                       DATE '2022-05-30', DATE '2022-06-20', DATE '2022-07-04',
                       DATE '2022-09-05', DATE '2022-10-10', DATE '2022-11-11',
                       DATE '2022-11-24', DATE '2022-12-25', DATE '2022-12-26'),
     1, 0)                                         AS is_holiday,
  -- Features físicas
  f.trip_distance,
  f.trip_duration_minutes,
  ROUND(SAFE_DIVIDE(f.trip_distance, NULLIF(f.trip_duration_minutes / 60, 0)), 2) AS avg_speed_mph,
  f.passenger_count,
  -- Features geográficas
  zp.borough                                       AS pickup_borough,
  zd.borough                                       AS dropoff_borough,
  IF(f.pickup_location_id IN (132, 138), 1, 0)     AS is_airport_pickup,
  IF(f.dropoff_location_id IN (132, 138), 1, 0)    AS is_airport_dropoff,
  IF(f.pickup_location_id IN (132, 138, 237, 238, 239, 161, 142, 141,
                              170, 114, 48, 186, 90, 79), 1, 0) AS is_hot_zone,
  -- Features contextuales conocidas al abordar
  f.extra,
  f.tolls_amount,
  f.congestion_surcharge,
  CAST(f.vendor_id AS STRING)                      AS vendor_id_str,
  CASE
    WHEN f.trip_distance <  1 THEN '0-1 mi'
    WHEN f.trip_distance <  3 THEN '1-3 mi'
    WHEN f.trip_distance <  6 THEN '3-6 mi'
    WHEN f.trip_distance < 12 THEN '6-12 mi'
    ELSE '12+ mi'
  END                                              AS distance_bucket,
  -- Columnas de control (solo para filtrar; NO son features)
  f.rate_code,
  f.payment_type,
  -- Etiquetas
  f.fare_amount                                    AS fare_amount,
  IF(f.tip_ratio >= 0.20, 1, 0)                    AS high_tip,
  -- Referencia temporal para auditoría (no es feature)
  f.pickup_date,
  f.pickup_datetime
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_opt` f
LEFT JOIN `ss2-2026-pareja14.taxi_ss2_2026.dim_zones` zp
       ON zp.location_id = f.pickup_location_id
LEFT JOIN `ss2-2026-pareja14.taxi_ss2_2026.dim_zones` zd
       ON zd.location_id = f.dropoff_location_id;

-- ----------------------------------------------------------------------------
-- BLOQUE 2: VISTA DE ENTRADA PARA MODELOS DE REGRESIÓN DE TARIFA.
-- Solo rate_code = 1 (tarifa por taxímetro): en tarifas planas (códigos 2-5)
-- el precio no depende de la distancia y contaminaría la relación aprendida.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_fare` AS
SELECT * EXCEPT (rate_code, payment_type, high_tip, tip_ratio_excluida)
FROM (
  SELECT v.* EXCEPT (rate_code, payment_type, high_tip),
         v.rate_code AS rate_code_filtro,
         v.payment_type AS payment_filtro
  FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_features` v
)
WHERE rate_code_filtro = 1;

-- ----------------------------------------------------------------------------
-- BLOQUE 3: VISTA DE ENTRADA PARA MODELOS DE CLASIFICACIÓN DE PROPINA.
-- Solo payment_type = 1 (tarjeta) y tarifa >= 3 USD: en efectivo la propina
-- no se captura (tip_amount = 0 por diseño del sistema TLC) y la etiqueta
-- high_tip sería degenerada (ver estrategia anti leakage, punto 6).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_tip` AS
SELECT *
FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_features`
WHERE payment_type = 1
  AND fare_amount >= 3.0;

-- ----------------------------------------------------------------------------
-- BLOQUE 4: BALANCE DEL SPLIT. Prueba de que los tres conjuntos son
-- representativos (medias y desviaciones similares = sin drift severo).
-- Capturar como evidencia_08_split_balance.png.
-- ----------------------------------------------------------------------------
SELECT
  split_set,
  COUNT(*)                                              AS n_registros,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)      AS pct,
  MIN(pickup_date)                                      AS desde,
  MAX(pickup_date)                                      AS hasta,
  ROUND(AVG(fare_amount), 3)                            AS fare_medio,
  ROUND(STDDEV(fare_amount), 3)                         AS fare_stddev,
  ROUND(AVG(high_tip), 4)                               AS tasa_high_tip
FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_features`
GROUP BY split_set
ORDER BY desde;

-- ----------------------------------------------------------------------------
-- BLOQUE 5: PRUEBA FORMAL DE AUSENCIA DE SOLAPAMIENTO TEMPORAL.
-- Resultado esperado: conjunto vacío (0 filas). Si un mismo timestamp
-- apareciera en dos splits, habría fuga de futuro.
-- Capturar como evidencia_08_sin_solapamiento.png.
-- ----------------------------------------------------------------------------
SELECT
  a.split_set AS split_a,
  b.split_set AS split_b,
  COUNT(*)    AS filas_solapadas
FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_features` a
JOIN `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_features` b
  ON a.pickup_datetime = b.pickup_datetime
WHERE a.split_set <> b.split_set
GROUP BY 1, 2;

-- ----------------------------------------------------------------------------
-- BLOQUE 6: BALANCE DE CLASES DE high_tip EN TRAIN.
-- Justifica el uso de auto_class_weights=TRUE en los clasificadores.
-- Capturar como evidencia_08_balance_clases.png.
-- ----------------------------------------------------------------------------
SELECT
  high_tip,
  COUNT(*)                                         AS n_viajes,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_tip`
WHERE split_set = 'TRAIN'
GROUP BY high_tip
ORDER BY high_tip;

-- ----------------------------------------------------------------------------
-- BLOQUE 7: INVENTARIO DE VARIABLES DE LA VISTA DE REGRESIÓN.
-- Documenta de forma auditable qué entra al modelo (rúbrica 2.4):
-- todas las columnas salvo fare_amount (objetivo) y split_set (split)
-- son variables de entrada; fare_amount es la variable objetivo.
-- 0 bytes. Capturar como evidencia_08_inventario_variables.png.
-- ----------------------------------------------------------------------------
SELECT
  column_name,
  data_type,
  CASE
    WHEN column_name = 'fare_amount' THEN 'OBJETIVO (label)'
    WHEN column_name = 'split_set'   THEN 'SPLIT (no feature)'
    WHEN column_name IN ('pickup_date', 'pickup_datetime') THEN 'REFERENCIA (no feature)'
    ELSE 'ENTRADA (feature)'
  END AS rol
FROM `ss2-2026-pareja14.taxi_ss2_2026.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'vw_ml_fare'
ORDER BY ordinal_position;