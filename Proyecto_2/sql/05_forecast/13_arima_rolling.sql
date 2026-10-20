-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/05_forecast/13_arima_rolling.sql
-- Objetivo  : Implementar pronósticos de serie temporal con BigQuery ML
--             (ARIMA_PLUS) mediante la técnica de ROLLING FORECAST:
--             re-entrenar el modelo desplazando el origen y encadenar los
--             pronósticos de 4 ventanas mensuales consecutivas, comparando
--             cada ventana contra los valores reales ya ocurridos.
--             Esto cumple el entregable "comparación de al menos 2
--             predicciones con los modelos de ML (Rolling Forecast)".
-- Por qué rolling y no un solo forecast largo: un pronóstico único de 122
--             días acumula error creciente; el rolling simula el proceso
--             real de un analista que reentrena cada mes con la información
--             disponible hasta ese corte. La comparación de MAPE entre
--             ventanas mide la estabilidad del modelo en el tiempo.
-- Fuente    : agg_daily (365 filas). Todos los entrenamientos son baratos:
--             el costo total del archivo es menor a 0.1 GB procesados.
-- Evidencias: evidencia_13_modelos_creados.png (bloque 1),
--             evidencia_13_rolling_tabla.png (bloque 2),
--             evidencia_13_rolling_metricas.png (bloque 3),
--             evidencia_13_arima_evaluate.png (bloque 4),
--             evidencia_13_revenue.png (bloque 5),
--             evidencia_13_anomalías.png (bloque 6).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BLOQUE 1: CUATRO MODELOS DE ROLLING FORECAST (conteo diario de viajes).
-- Cada modelo entrena SOLO con datos anteriores a su corte y pronostica el
-- mes siguiente completo. Ningún modelo ve el mes que va a pronosticar
-- (equivalente temporal del anti data leakage de la fase 4).
--   R1: entrena ENE-AGO  -> pronostica SEP (30 días)
--   R2: entrena ENE-SEP  -> pronostica OCT (31 días)
--   R3: entrena ENE-OCT  -> pronostica NOV (30 días)
--   R4: entrena ENE-NOV  -> pronostica DIC (31 días)
-- HIPERPARÁMETROS / OPCIONES Y SU PORQUÉ:
--   auto_arima = TRUE          : BQML busca el orden (p,d,q) óptimo por
--                                ventana; documentar el orden elegido en el
--                                README vía ML.EVALUATE / TRAINING_INFO.
--   holiday_region = 'US'      : captura festivos estadounidenses que
--                                desploman o elevan la demanda de taxi.
--   decompose_time_series      : separa tendencia, estacionalidad y residuo;
--                                alimenta la gráfica de descomposición.
--   clean_spikes_and_dips      : suaviza atípicos puntuales (tormentas,
--                                caídas del sistema) sin borrarlos del dato.
--   adjust_step_changes        : corrige cambios de nivel abruptos (por ej.
--                                fin de una ola de restricciones sanitarias).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_r1`
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
FROM `ss2-2026-pareja14.taxi_ss2_2026.agg_daily`
WHERE pickup_date <= DATE '2022-08-31';

CREATE OR REPLACE MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_r2`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'trip_date',
  time_series_data_col = 'trip_count',
  auto_arima = TRUE, holiday_region = 'US',
  decompose_time_series = TRUE,
  clean_spikes_and_dips = TRUE, adjust_step_changes = TRUE
) AS
SELECT pickup_date AS trip_date, trip_count
FROM `ss2-2026-pareja14.taxi_ss2_2026.agg_daily`
WHERE pickup_date <= DATE '2022-09-30';

CREATE OR REPLACE MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_r3`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'trip_date',
  time_series_data_col = 'trip_count',
  auto_arima = TRUE, holiday_region = 'US',
  decompose_time_series = TRUE,
  clean_spikes_and_dips = TRUE, adjust_step_changes = TRUE
) AS
SELECT pickup_date AS trip_date, trip_count
FROM `ss2-2026-pareja14.taxi_ss2_2026.agg_daily`
WHERE pickup_date <= DATE '2022-10-31';

CREATE OR REPLACE MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_r4`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'trip_date',
  time_series_data_col = 'trip_count',
  auto_arima = TRUE, holiday_region = 'US',
  decompose_time_series = TRUE,
  clean_spikes_and_dips = TRUE, adjust_step_changes = TRUE
) AS
SELECT pickup_date AS trip_date, trip_count
FROM `ss2-2026-pareja14.taxi_ss2_2026.agg_daily`
WHERE pickup_date <= DATE '2022-11-30';

-- ----------------------------------------------------------------------------
-- BLOQUE 2: TABLA CONSOLIDADA DEL ROLLING FORECAST.
-- Une los 4 pronósticos con los valores REALES de agg_daily y calcula el
-- error por día. Incluye los límites del intervalo de confianza al 95%
-- para la banda de incertidumbre del dashboard.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.forecast_rolling` AS
WITH p AS (
  SELECT 'R1_pron_sep' AS ventana, forecast_timestamp, forecast_value,
         prediction_interval_lower_bound AS li, prediction_interval_upper_bound AS ls
  FROM ML.FORECAST(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_r1`,
                   STRUCT(30 AS horizon, 0.95 AS confidence_level))
  UNION ALL
  SELECT 'R2_pron_oct', forecast_timestamp, forecast_value,
         prediction_interval_lower_bound, prediction_interval_upper_bound
  FROM ML.FORECAST(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_r2`,
                   STRUCT(31 AS horizon, 0.95 AS confidence_level))
  UNION ALL
  SELECT 'R3_pron_nov', forecast_timestamp, forecast_value,
         prediction_interval_lower_bound, prediction_interval_upper_bound
  FROM ML.FORECAST(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_r3`,
                   STRUCT(30 AS horizon, 0.95 AS confidence_level))
  UNION ALL
  SELECT 'R4_pron_dic', forecast_timestamp, forecast_value,
         prediction_interval_lower_bound, prediction_interval_upper_bound
  FROM ML.FORECAST(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_r4`,
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
LEFT JOIN `ss2-2026-pareja14.taxi_ss2_2026.agg_daily` a
       ON a.pickup_date = DATE(p.forecast_timestamp);

-- ----------------------------------------------------------------------------
-- BLOQUE 3: MÉTRICAS DEL ROLLING FORECAST POR VENTANA (backtest honesto).
-- Estas métricas son FUERA DE MUESTRA: cada ventana se compara contra días
-- que el modelo correspondiente nunca vio. Es la evidencia central del
-- criterio 1.5 aplicada a series de tiempo.
--   mape_pct          : error porcentual medio (métrica de negocio).
--   cobertura_ic_pct  : % de días reales que caen dentro del intervalo al
--                       95%. Debe rondar 95%; muy por debajo indica
--                       intervalos mal calibrados.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.forecast_rolling_metrics` AS
SELECT
  ventana,
  COUNTIF(viajes_reales IS NOT NULL)                          AS dias_evaluados,
  ROUND(SQRT(AVG(POW(viajes_predichos - viajes_reales, 2))), 1) AS rmse_viajes,
  ROUND(AVG(ABS(viajes_predichos - viajes_reales)), 1)          AS mae_viajes,
  ROUND(100 * AVG(ABS(error_pct)), 2)                           AS mape_pct,
  ROUND(100 * COUNTIF(viajes_reales BETWEEN limite_inferior AND limite_superior)
        / COUNTIF(viajes_reales IS NOT NULL), 2)                AS cobertura_ic_pct
FROM `ss2-2026-pareja14.taxi_ss2_2026.forecast_rolling`
WHERE viajes_reales IS NOT NULL
GROUP BY ventana
ORDER BY ventana;

-- ----------------------------------------------------------------------------
-- BLOQUE 4: MÉTRICAS INTERNAS DE CADA ARIMA (dentro de muestra).
-- Complementan el backtest: si el MAPE interno es mucho menor que el del
-- bloque 3, hay sobreajuste o cambio de régimen entre periodos.
-- ----------------------------------------------------------------------------
SELECT 'R1' AS ventana, m.* FROM ML.EVALUATE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_r1`) m
UNION ALL
SELECT 'R2', m.* FROM ML.EVALUATE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_r2`) m
UNION ALL
SELECT 'R3', m.* FROM ML.EVALUATE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_r3`) m
UNION ALL
SELECT 'R4', m.* FROM ML.EVALUATE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_r4`) m;

-- ----------------------------------------------------------------------------
-- BLOQUE 5: SEGUNDA SERIE PRONOSTICADA (ingreso diario por tarifa).
-- Segundo modelo de forecast para la comparación exigida por el entregable:
-- dos series distintas (demanda e ingreso) pronosticadas y contrastadas con
-- la realidad de OCT-DIC.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_revenue`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'trip_date',
  time_series_data_col = 'revenue_fare',
  auto_arima = TRUE, holiday_region = 'US',
  decompose_time_series = TRUE,
  clean_spikes_and_dips = TRUE, adjust_step_changes = TRUE
) AS
SELECT pickup_date AS trip_date, revenue_fare
FROM `ss2-2026-pareja14.taxi_ss2_2026.agg_daily`
WHERE pickup_date <= DATE '2022-09-30';

CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.forecast_revenue` AS
SELECT
  DATE(f.forecast_timestamp)                 AS fecha,
  ROUND(f.forecast_value, 2)                 AS revenue_predicho,
  ROUND(f.prediction_interval_lower_bound, 2) AS limite_inferior,
  ROUND(f.prediction_interval_upper_bound, 2) AS limite_superior,
  a.revenue_fare                             AS revenue_real,
  ROUND(SAFE_DIVIDE(f.forecast_value - a.revenue_fare, a.revenue_fare), 4) AS error_pct
FROM ML.FORECAST(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_revenue`,
                 STRUCT(92 AS horizon, 0.95 AS confidence_level)) f
LEFT JOIN `ss2-2026-pareja14.taxi_ss2_2026.agg_daily` a
       ON a.pickup_date = DATE(f.forecast_timestamp);

-- Métrica resumen del forecast de ingreso (capturar en evidencia_13_revenue).
SELECT
  COUNTIF(revenue_real IS NOT NULL)                 AS dias_evaluados,
  ROUND(100 * AVG(ABS(error_pct)), 2)               AS mape_pct,
  ROUND(100 * COUNTIF(revenue_real BETWEEN limite_inferior AND limite_superior)
        / COUNTIF(revenue_real IS NOT NULL), 2)     AS cobertura_ic_pct
FROM `ss2-2026-pareja14.taxi_ss2_2026.forecast_revenue`;

-- ----------------------------------------------------------------------------
-- BLOQUE 6: MODELO COMPLETO + DESCOMPOSICIÓN + ANOMALÍAS.
-- Entrena con todo 2022 para (a) descomponer la serie en tendencia,
-- estacionalidad semanal/anual y efecto festivo, y (b) detectar días
-- anómalos (eventos climáticos, huelgas, fallas) que justifican hallazgos
-- temporales del README.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_trips_full`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'trip_date',
  time_series_data_col = 'trip_count',
  auto_arima = TRUE, holiday_region = 'US',
  decompose_time_series = TRUE,
  clean_spikes_and_dips = TRUE, adjust_step_changes = TRUE
) AS
SELECT pickup_date AS trip_date, trip_count
FROM `ss2-2026-pareja14.taxi_ss2_2026.agg_daily`;

CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.dash_forecast_decompose` AS
SELECT *
FROM ML.EXPLAIN_FORECAST(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_trips_full`,
                         STRUCT(30 AS horizon, 0.95 AS confidence_level));

CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.dash_anomalies` AS
SELECT *
FROM ML.DETECT_ANOMALIES(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fc_trips_full`,
                         STRUCT(0.95 AS anomaly_prob_threshold));

-- Días anómalos detectados (capturar; citar 2 o 3 en el README como hallazgo).
SELECT DATE(time_series_timestamp) AS fecha, trip_count,
       ROUND(anomaly_probability, 3) AS prob_anomalia
FROM `ss2-2026-pareja14.taxi_ss2_2026.dash_anomalies`
WHERE is_anomaly
ORDER BY fecha;

-- ----------------------------------------------------------------------------
-- BLOQUE 7: INVENTARIO DE TABLAS DE FORECAST (0 bytes).
-- ----------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.forecast_rolling`)         AS filas_rolling,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.forecast_rolling_metrics`) AS filas_metricas,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.forecast_revenue`)         AS filas_revenue,
  (SELECT COUNT(*) FROM `ss2-2026-pareja14.taxi_ss2_2026.dash_anomalies`)           AS filas_anomalías;