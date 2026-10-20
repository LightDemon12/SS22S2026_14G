-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/04_ml/11_evaluacion.sql
-- Objetivo  : Evaluar y comparar los 4 modelos con métricas pertinentes y
--             los hiperparámetros resultantes del tuning (rúbrica 1.5),
--             y persistir la comparación en tablas para el dashboard.
-- Nota      : ML.EVALUATE sin consulta de entrada usa el split EVAL guardado
--             durante el entrenamiento (definido por split_set), por lo que
--             las métricas nunca se calculan sobre TRAIN ni sobre TEST.
-- Costo     : aprox. 1-2 GB en total (evaluaciones y explicaciones).
-- Evidencias: evidencia_11_eval_regresion.png, evidencia_11_eval_clasif.png,
--             evidencia_11_confusion.png, evidencia_11_trials.png,
--             evidencia_11_explain.png, evidencia_11_weights.png.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BLOQUE 1: MÉTRICAS DE REGRESIÓN (M1 vs M2).
-- RMSE en dólares es la métrica de negocio: error típico de predicción.
-- R2 indica proporción de varianza explicada.
-- ----------------------------------------------------------------------------
SELECT 'M1_regresion_lineal' AS modelo,
       ROUND(mean_squared_error, 4)     AS mse,
       ROUND(mean_absolute_error, 4)    AS mae_usd,
       ROUND(SQRT(mean_squared_error), 4) AS rmse_usd,
       ROUND(r2_score, 4)               AS r2
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_linear`)
UNION ALL
SELECT 'M2_boosted_trees',
       ROUND(mean_squared_error, 4),
       ROUND(mean_absolute_error, 4),
       ROUND(SQRT(mean_squared_error), 4),
       ROUND(r2_score, 4)
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_btree`);

-- ----------------------------------------------------------------------------
-- BLOQUE 2: MÉTRICAS DE CLASIFICACIÓN (M3 vs M4).
-- roc_auc es la métrica principal por haber desbalance de clases;
-- precision/recall/f1 describen el costo de cada tipo de error.
-- ----------------------------------------------------------------------------
SELECT 'M3_regresion_logistica' AS modelo,
       ROUND(accuracy, 4)  AS accuracy,
       ROUND(precision, 4) AS precision,
       ROUND(recall, 4)    AS recall,
       ROUND(f1_score, 4)  AS f1,
       ROUND(roc_auc, 4)   AS roc_auc,
       ROUND(log_loss, 4)  AS log_loss
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_logistic`)
UNION ALL
SELECT 'M4_random_forest',
       ROUND(accuracy, 4), ROUND(precision, 4), ROUND(recall, 4),
       ROUND(f1_score, 4), ROUND(roc_auc, 4), ROUND(log_loss, 4)
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_rf`);

-- ----------------------------------------------------------------------------
-- BLOQUE 3: MATRICES DE CONFUSIÓN DE AMBOS CLASIFICADORES.
-- Permite ver si el modelo mejora detectando la clase minoritaria
-- (high_tip = 1) o solo acierta la mayoritaria.
-- ----------------------------------------------------------------------------
SELECT 'M3_regresion_logistica' AS modelo, m.*
FROM ML.CONFUSION_MATRIX(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_logistic`) m
UNION ALL
SELECT 'M4_random_forest', m.*
FROM ML.CONFUSION_MATRIX(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_rf`) m;

-- ----------------------------------------------------------------------------
-- BLOQUE 4: CURVAS ROC PERSISTIDAS PARA EL DASHBOARD.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.ml_roc_curves` AS
SELECT 'M3_regresion_logistica' AS modelo, c.*
FROM ML.ROC_CURVE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_logistic`) c
UNION ALL
SELECT 'M4_random_forest', c.*
FROM ML.ROC_CURVE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_rf`) c;

-- ----------------------------------------------------------------------------
-- BLOQUE 5: RESULTADOS DEL TUNING DE HIPERPARÁMETROS.
-- Cada fila es un ensayo de VIZIER con sus hiperparámetros y su eval_loss.
-- La fila con menor eval_loss es la configuración ganadora: citarla en el
-- README como "hiperparámetros finales del modelo" (rúbrica 1.5).
-- ----------------------------------------------------------------------------
SELECT trial_id, eval_loss, duration_ms,
       TO_JSON_STRING(trial_params) AS hiperparametros
FROM ML.TRIAL_INFO(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_btree`)
ORDER BY eval_loss ASC;

SELECT trial_id, eval_loss, duration_ms,
       TO_JSON_STRING(trial_params) AS hiperparametros
FROM ML.TRIAL_INFO(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_rf`)
ORDER BY eval_loss ASC;

-- ----------------------------------------------------------------------------
-- BLOQUE 6: IMPORTANCIA DE VARIABLES (justificación de ingeniería de
-- características, rúbrica 2.3). Si is_rush_pm o trip_distance aparecen
-- arriba, confirma que las features derivadas aportan señal real.
-- ----------------------------------------------------------------------------
SELECT * FROM ML.GLOBAL_EXPLAIN(
  MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_btree`, top_k_features => 15);

SELECT * FROM ML.GLOBAL_EXPLAIN(
  MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_rf`, top_k_features => 15);

-- ----------------------------------------------------------------------------
-- BLOQUE 7: PESOS DEL MODELO LINEAL (interpretabilidad económica).
-- El peso de trip_distance es el precio marginal por milla estimado.
-- ----------------------------------------------------------------------------
SELECT processed_input AS variable, ROUND(weight, 4) AS peso
FROM ML.WEIGHTS(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_linear`)
ORDER BY ABS(weight) DESC;

-- ----------------------------------------------------------------------------
-- BLOQUE 8: ESTADÍSTICAS DE FEATURES CALCULADAS SOLO SOBRE TRAIN.
-- Prueba documental de que el escalado interno de BQML no usó EVAL ni TEST
-- (argumento adicional anti leakage para la rúbrica 1.6).
-- ----------------------------------------------------------------------------
SELECT *
FROM ML.FEATURE_INFO(
  MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_linear`,
  INPUT => (
    SELECT trip_distance, trip_duration_minutes, avg_speed_mph, passenger_count,
           pickup_hour, fare_amount, split_set
    FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_fare`
  ),
  threshold => 0.001);

-- ----------------------------------------------------------------------------
-- BLOQUE 9: TABLA PERSISTIDA DE COMPARACIÓN (fuente del dashboard).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.ml_metrics_comparativa` AS
SELECT 'M1_regresion_lineal' AS modelo, 'Regresion' AS tipo,
       mean_squared_error AS mse, mean_absolute_error AS mae,
       SQRT(mean_squared_error) AS rmse, r2_score AS r2,
       CAST(NULL AS FLOAT64) AS accuracy, CAST(NULL AS FLOAT64) AS roc_auc,
       CAST(NULL AS FLOAT64) AS f1_score
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_linear`)
UNION ALL
SELECT 'M2_boosted_trees', 'Regresion',
       mean_squared_error, mean_absolute_error, SQRT(mean_squared_error),
       r2_score, NULL, NULL, NULL
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_btree`)
UNION ALL
SELECT 'M3_regresion_logistica', 'Clasificacion',
       NULL, NULL, NULL, NULL, accuracy, roc_auc, f1_score
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_logistic`)
UNION ALL
SELECT 'M4_random_forest', 'Clasificacion',
       NULL, NULL, NULL, NULL, accuracy, roc_auc, f1_score
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_rf`);