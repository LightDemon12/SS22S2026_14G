-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/04_ml/12_predicciones.sql
-- Objetivo  : Aplicar los modelos seleccionados sobre (a) el holdout TEST
--             temporal nunca visto en entrenamiento ni evaluación, y
--             (b) registros nuevos sintéticos, y persistir tablas de
--             resultados con predicciones (entregable "Scripts BigQuery ML").
-- Costo     : aprox. 2-3 GB en total.
-- Evidencias: evidencia_12_pred_test.png, evidencia_12_pred_nuevos.png,
--             evidencia_12_explain.png, evidencia_12_tablas_pred.png.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BLOQUE 1: PREDICCIÓN DE TARIFA SOBRE EL HOLDOUT TEST (modelo ganador M2).
-- Las columnas extra (incluida fare_amount real) pasan al resultado y
-- permiten calcular el error por registro.
-- Si la consola rechazara columnas extra, seleccionar únicamente las
-- features listadas en el CREATE MODEL de M2.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.pred_fare_test` AS
SELECT
  pickup_date,
  pickup_borough,
  dropoff_borough,
  trip_distance,
  trip_duration_minutes,
  fare_amount                          AS fare_real,
  predicted_fare_amount                AS fare_predicho,
  ROUND(predicted_fare_amount - fare_amount, 4) AS error_usd,
  ROUND(SAFE_DIVIDE(predicted_fare_amount - fare_amount, fare_amount), 4) AS error_pct
FROM ML.PREDICT(
  MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_btree`,
  (SELECT * FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_fare`
   WHERE split_set = 'TEST'));

-- Resumen de error del holdout (complementa ML.EVALUATE con el split TEST).
SELECT
  COUNT(*)                                    AS n_viajes_test,
  ROUND(SQRT(AVG(POW(error_usd, 2))), 4)      AS rmse_test_usd,
  ROUND(AVG(ABS(error_usd)), 4)               AS mae_test_usd,
  ROUND(100 * AVG(ABS(error_pct)), 2)         AS mape_test_pct
FROM `ss2-2026-pareja14.taxi_ss2_2026.pred_fare_test`;

-- ----------------------------------------------------------------------------
-- BLOQUE 2: PREDICCIÓN SOBRE REGISTROS NUEVOS (casos hipotéticos).
-- Demuestra que el modelo se aplica a datos que aún no existen: tres
-- servicios típicos (urbano corto en hora pico, aeropuerto un sábado,
-- nocturno Brooklyn-Manhattan). Capturar como evidencia_12_pred_nuevos.png.
-- ----------------------------------------------------------------------------
SELECT
  predicted_fare_amount AS tarifa_predicha_usd,
  trip_distance, pickup_hour, pickup_borough, dropoff_borough
FROM ML.PREDICT(
  MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_btree`,
  (
    SELECT 1.2 AS trip_distance, 8 AS trip_duration_minutes, 9.0 AS avg_speed_mph,
           1 AS passenger_count, 8 AS pickup_hour, 2 AS pickup_dow, 6 AS pickup_month,
           0 AS is_weekend, 1 AS is_rush_am, 0 AS is_rush_pm, 0 AS is_night,
           0 AS is_holiday, 0 AS is_airport_pickup, 0 AS is_airport_dropoff,
           1 AS is_hot_zone, 1.0 AS extra, 0.0 AS tolls_amount,
           2.5 AS congestion_surcharge,
           'Manhattan' AS pickup_borough, 'Manhattan' AS dropoff_borough,
           '2' AS vendor_id_str, '1-3 mi' AS distance_bucket
    UNION ALL
    SELECT 14.5, 38, 22.9, 2, 14, 6, 7, 1, 0, 0, 0, 0,
           1, 0, 1, 1.0, 6.5, 2.5,
           'Manhattan', 'Queens', '1', '12+ mi'
    UNION ALL
    SELECT 3.1, 22, 8.5, 4, 23, 5, 11, 0, 0, 0, 1, 0,
           0, 0, 0, 0.5, 0.0, 2.5,
           'Brooklyn', 'Manhattan', '2', '3-6 mi'
  ));

-- ----------------------------------------------------------------------------
-- BLOQUE 3: PREDICCIÓN DE PROPINA ALTA SOBRE TEST (modelo ganador M4)
-- CON EXPLICACIÓN POR REGISTRO (ML.EXPLAIN_PREDICT): muestra qué features
-- empujaron cada predicción. Capturar como evidencia_12_explain.png.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.pred_tip_test` AS
SELECT
  pickup_date,
  pickup_borough,
  fare_amount,
  trip_distance,
  high_tip                    AS real_high_tip,
  predicted_high_tip,
  (SELECT p.prob FROM UNNEST(predicted_high_tip_probs) p WHERE p.label = 1) AS prob_high_tip
FROM ML.PREDICT(
  MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_rf`,
  (SELECT * FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_tip`
   WHERE split_set = 'TEST'));

SELECT *
FROM ML.EXPLAIN_PREDICT(
  MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_rf`,
  (SELECT * FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_tip`
   WHERE split_set = 'TEST' LIMIT 10),
  top_k_features => 4);

-- ----------------------------------------------------------------------------
-- BLOQUE 4: CAPAS AGREGADAS DE PREDICCIONES PARA EL DASHBOARD.
-- Tablas pequeñas que alimentan las páginas de modelos en Looker Studio.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.dash_pred_fare_daily` AS
SELECT
  pickup_date,
  COUNT(*)                               AS n_viajes,
  ROUND(AVG(fare_real), 3)               AS fare_real_prom,
  ROUND(AVG(fare_predicho), 3)           AS fare_pred_prom,
  ROUND(SQRT(AVG(POW(error_usd, 2))), 3) AS rmse_dia,
  ROUND(100 * AVG(ABS(error_pct)), 2)    AS mape_dia_pct
FROM `ss2-2026-pareja14.taxi_ss2_2026.pred_fare_test`
GROUP BY pickup_date
ORDER BY pickup_date;

CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.dash_tip_calibration` AS
SELECT
  ROUND(FLOOR(prob_high_tip * 10) / 10, 1) AS bucket_probabilidad,
  COUNT(*)                                 AS n_viajes,
  ROUND(AVG(real_high_tip), 4)             AS tasa_real_high_tip,
  ROUND(AVG(prob_high_tip), 4)             AS probabilidad_promedio
FROM `ss2-2026-pareja14.taxi_ss2_2026.pred_tip_test`
WHERE prob_high_tip IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- ----------------------------------------------------------------------------
-- BLOQUE 5: VERIFICACIÓN FINAL DE TABLAS DE PREDICCIONES (0 bytes).
-- ----------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.pred_fare_test`)       AS filas_pred_fare,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.pred_tip_test`)        AS filas_pred_tip,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.dash_pred_fare_daily`) AS filas_dash_fare,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.dash_tip_calibration`) AS filas_dash_calib;