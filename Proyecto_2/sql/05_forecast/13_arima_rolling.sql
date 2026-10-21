-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/05_forecast/13_arima_rolling.sql
-- Objetivo  : Pronósticos de serie temporal con ARIMA_PLUS y Rolling Forecast.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BLOQUE 1a: MODELO R1 (entrena ENE-AGO, pronostica SEP)
-- ️SIN CAPTURA: Solo verifica que diga "Query completed"
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_r1`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'trip_date',
  time_series_data_col = 'trip_count',
  auto_arima = TRUE,
  holiday_region = 'US',
  decompose_time_series = TRUE,
  clean_spikes_and_dips = TRUE,
  adjust_step_changes = TRUE
) AS
SELECT pickup_date AS trip_date, trip_count
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily`
WHERE pickup_date <= DATE '2022-08-31';


-- ----------------------------------------------------------------------------
-- BLOQUE 1b: MODELO R2 (entrena ENE-SEP, pronostica OCT)
-- ️SIN CAPTURA: Solo verifica que diga "Query completed"
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_r2`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'trip_date',
  time_series_data_col = 'trip_count',
  auto_arima = TRUE,
  holiday_region = 'US',
  decompose_time_series = TRUE,
  clean_spikes_and_dips = TRUE,
  adjust_step_changes = TRUE
) AS
SELECT pickup_date AS trip_date, trip_count
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily`
WHERE pickup_date <= DATE '2022-09-30';


-- ----------------------------------------------------------------------------
-- BLOQUE 1c: MODELO R3 (entrena ENE-OCT, pronostica NOV)
-- SIN CAPTURA: Solo verifica que diga "Query completed"
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_r3`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'trip_date',
  time_series_data_col = 'trip_count',
  auto_arima = TRUE,
  holiday_region = 'US',
  decompose_time_series = TRUE,
  clean_spikes_and_dips = TRUE,
  adjust_step_changes = TRUE
) AS
SELECT pickup_date AS trip_date, trip_count
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily`
WHERE pickup_date <= DATE '2022-10-31';


-- ----------------------------------------------------------------------------
-- BLOQUE 1d: MODELO R4 (entrena ENE-NOV, pronostica DIC)
-- CAPTURA: evidencia_13_modelos_creados.png
-- (Verifica que diga "Query completed" - este es el último de los 4)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_r4`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'trip_date',
  time_series_data_col = 'trip_count',
  auto_arima = TRUE,
  holiday_region = 'US',
  decompose_time_series = TRUE,
  clean_spikes_and_dips = TRUE,
  adjust_step_changes = TRUE
) AS
SELECT pickup_date AS trip_date, trip_count
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily`
WHERE pickup_date <= DATE '2022-11-30';


-- ----------------------------------------------------------------------------
-- BLOQUE 2: TABLA CONSOLIDADA DEL ROLLING FORECAST
-- CAPTURA: evidencia_13_rolling_tabla.png
-- (Deja visible el SQL y la tabla con las 4 ventanas y sus predicciones)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.forecast_rolling` AS
WITH p AS (
  SELECT 'R1_pron_sep' AS ventana, forecast_timestamp, forecast_value,
         prediction_interval_lower_bound AS li, prediction_interval_upper_bound AS ls
  FROM ML.FORECAST(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_r1`,
                   STRUCT(30 AS horizon, 0.95 AS confidence_level))
  UNION ALL
  SELECT 'R2_pron_oct', forecast_timestamp, forecast_value,
         prediction_interval_lower_bound, prediction_interval_upper_bound
  FROM ML.FORECAST(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_r2`,
                   STRUCT(31 AS horizon, 0.95 AS confidence_level))
  UNION ALL
  SELECT 'R3_pron_nov', forecast_timestamp, forecast_value,
         prediction_interval_lower_bound, prediction_interval_upper_bound
  FROM ML.FORECAST(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_r3`,
                   STRUCT(30 AS horizon, 0.95 AS confidence_level))
  UNION ALL
  SELECT 'R4_pron_dic', forecast_timestamp, forecast_value,
         prediction_interval_lower_bound, prediction_interval_upper_bound
  FROM ML.FORECAST(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_r4`,
                   STRUCT(31 AS horizon, 0.95 AS confidence_level))
)
SELECT
  p.ventana,
  DATE(p.forecast_timestamp)                    AS fecha,
  ROUND(p.forecast_value, 1)                    AS viajes_predichos,
  ROUND(p.li, 1)                                AS limite_inferior,
  ROUND(p.ls, 1)                                AS limite_superior,
  a.trip_count                                  AS viajes_reales,
  ROUND(p.forecast_value - a.trip_count, 1)     AS error,
  ROUND(SAFE_DIVIDE(p.forecast_value - a.trip_count, a.trip_count), 4) AS error_pct
FROM p
LEFT JOIN `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily` a
       ON a.pickup_date = DATE(p.forecast_timestamp);


-- ----------------------------------------------------------------------------
-- BLOQUE 3: MÉTRICAS DEL ROLLING FORECAST POR VENTANA
-- CAPTURA: evidencia_13_rolling_metricas.png
-- (Deja visible el SQL y la tabla con 4 filas: rmse, mae, mape, cobertura)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.forecast_rolling_metrics` AS
SELECT
  ventana,
  COUNTIF(viajes_reales IS NOT NULL)                          AS dias_evaluados,
  ROUND(SQRT(AVG(POW(viajes_predichos - viajes_reales, 2))), 1) AS rmse_viajes,
  ROUND(AVG(ABS(viajes_predichos - viajes_reales)), 1)          AS mae_viajes,
  ROUND(100 * AVG(ABS(error_pct)), 2)                           AS mape_pct,
  ROUND(100 * COUNTIF(viajes_reales BETWEEN limite_inferior AND limite_superior)
        / COUNTIF(viajes_reales IS NOT NULL), 2)                AS cobertura_ic_pct
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.forecast_rolling`
WHERE viajes_reales IS NOT NULL
GROUP BY ventana
ORDER BY ventana;


-- ----------------------------------------------------------------------------
-- BLOQUE 4: MÉTRICAS INTERNAS DE CADA ARIMA (ML.EVALUATE)
-- CAPTURA: evidencia_13_arima_evaluate.png
-- (Deja visible el SQL y la tabla con 4 filas de métricas in-sample)
-- ----------------------------------------------------------------------------
SELECT 'R1' AS ventana, m.* FROM ML.EVALUATE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_r1`) m
UNION ALL
SELECT 'R2', m.* FROM ML.EVALUATE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_r2`) m
UNION ALL
SELECT 'R3', m.* FROM ML.EVALUATE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_r3`) m
UNION ALL
SELECT 'R4', m.* FROM ML.EVALUATE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_r4`) m;


-- ----------------------------------------------------------------------------
-- BLOQUE 5a (CORREGIDO): SEGUNDO MODELO DE FORECAST (noviembre, datos completos)
-- Entrena con ENE-OCT (304 días), pronostica NOV (30 días).
-- Noviembre tiene datos reales completos para comparación válida.
-- SIN CAPTURA: Solo verifica que diga "Query completed"
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_nov`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'trip_date',
  time_series_data_col = 'trip_count',
  auto_arima = TRUE,
  holiday_region = 'US',
  decompose_time_series = TRUE,
  clean_spikes_and_dips = TRUE,
  adjust_step_changes = TRUE
) AS
SELECT pickup_date AS trip_date, trip_count
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily`
WHERE pickup_date <= DATE '2022-10-31';


-- ----------------------------------------------------------------------------
-- BLOQUE 5b (CORREGIDO): TABLA DE PRONÓSTICO DE NOVIEMBRE
-- SIN CAPTURA: Solo verifica que diga "Query completed"
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.forecast_november` AS
SELECT
  DATE(f.forecast_timestamp)                 AS fecha,
  ROUND(f.forecast_value, 1)                 AS viajes_predichos,
  ROUND(f.prediction_interval_lower_bound, 1) AS limite_inferior,
  ROUND(f.prediction_interval_upper_bound, 1) AS limite_superior,
  a.trip_count                               AS viajes_reales,
  ROUND(f.forecast_value - a.trip_count, 1)  AS error_abs
FROM ML.FORECAST(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_nov`,
                 STRUCT(30 AS horizon, 0.95 AS confidence_level)) f
LEFT JOIN `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily` a
       ON a.pickup_date = DATE(f.forecast_timestamp);


-- ----------------------------------------------------------------------------
-- BLOQUE 5c (CORREGIDO): MÉTRICAS DEL FORECAST DE NOVIEMBRE
-- CAPTURA: evidencia_13_november.png
-- (Deja visible el SQL y la tabla con rmse, mae, mape, cobertura)
-- ----------------------------------------------------------------------------
SELECT
  COUNTIF(viajes_reales IS NOT NULL)                          AS dias_evaluados,
  ROUND(SQRT(AVG(POW(viajes_predichos - viajes_reales, 2))), 1) AS rmse_viajes,
  ROUND(AVG(ABS(viajes_predichos - viajes_reales)), 1)          AS mae_viajes,
  ROUND(100 * AVG(ABS(SAFE_DIVIDE(viajes_predichos - viajes_reales, viajes_reales))), 2) AS mape_pct,
  ROUND(100 * COUNTIF(viajes_reales BETWEEN limite_inferior AND limite_superior)
        / COUNTIF(viajes_reales IS NOT NULL), 2)                AS cobertura_ic_pct
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.forecast_november`
WHERE viajes_reales IS NOT NULL;

-- ----------------------------------------------------------------------------
-- BLOQUE 6a: MODELO COMPLETO (todo 2022) para descomposición y anomalías
-- SIN CAPTURA: Solo verifica que diga "Query completed"
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_trips_full`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'trip_date',
  time_series_data_col = 'trip_count',
  auto_arima = TRUE,
  holiday_region = 'US',
  decompose_time_series = TRUE,
  clean_spikes_and_dips = TRUE,
  adjust_step_changes = TRUE
) AS
SELECT pickup_date AS trip_date, trip_count
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily`;


-- ----------------------------------------------------------------------------
-- BLOQUE 6b: TABLA DE DESCOMPOSICIÓN (para dashboard)
-- SIN CAPTURA: Solo verifica que diga "Query completed"
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_forecast_decompose` AS
SELECT *
FROM ML.EXPLAIN_FORECAST(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_trips_full`,
                         STRUCT(30 AS horizon, 0.95 AS confidence_level));


-- ----------------------------------------------------------------------------
-- BLOQUE 6c: TABLA DE ANOMALÍAS
-- SIN CAPTURA: Solo verifica que diga "Query completed"
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_anomalies` AS
SELECT *
FROM ML.DETECT_ANOMALIES(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fc_trips_full`,
                         STRUCT(0.95 AS anomaly_prob_threshold));


-- ----------------------------------------------------------------------------
-- BLOQUE 6d: DÍAS ANÓMALOS DETECTADOS
-- CAPTURA: evidencia_13_anomalias.png
-- (Deja visible el SQL y la tabla con fechas anómalas y probabilidad)
-- ----------------------------------------------------------------------------
SELECT trip_date AS fecha, trip_count,
       ROUND(anomaly_probability, 3) AS prob_anomalia
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_anomalies`
WHERE is_anomaly
ORDER BY fecha;

-- ----------------------------------------------------------------------------
-- BLOQUE 7: INVENTARIO DE TABLAS DE FORECAST
-- CAPTURA: evidencia_13_inventario.png
-- (Deja visible el SQL y la tabla con 4 conteos de filas)
-- ----------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.forecast_rolling`)         AS filas_rolling,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.forecast_rolling_metrics`) AS filas_metricas,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.forecast_november`)        AS filas_november,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_anomalies`)           AS filas_anomalias;