-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/04_ml/11_evaluacion.sql
-- Objetivo  : Evaluar y comparar los 4 modelos, persistir resultados.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BLOQUE 1: MÉTRICAS DE REGRESIÓN (M1 vs M2)
-- CAPTURA: evidencia_11_eval_regresion.png
-- (Deja visible el SQL y la tabla con 2 filas: M1 y M2)
-- ----------------------------------------------------------------------------
SELECT 'M1_regresion_lineal' AS modelo,
       ROUND(mean_squared_error, 4)     AS mse,
       ROUND(mean_absolute_error, 4)    AS mae_usd,
       ROUND(SQRT(mean_squared_error), 4) AS rmse_usd,
       ROUND(r2_score, 4)               AS r2
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_linear`)
UNION ALL
SELECT 'M2_boosted_trees',
       ROUND(mean_squared_error, 4),
       ROUND(mean_absolute_error, 4),
       ROUND(SQRT(mean_squared_error), 4),
       ROUND(r2_score, 4)
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_btree`);


-- ----------------------------------------------------------------------------
-- BLOQUE 2: MÉTRICAS DE CLASIFICACIÓN (M3 vs M4)
-- CAPTURA: evidencia_11_eval_clasif.png
-- (Deja visible el SQL y la tabla con 2 filas: M3 y M4)
-- ----------------------------------------------------------------------------
SELECT 'M3_regresion_logistica' AS modelo,
       ROUND(accuracy, 4)  AS accuracy,
       ROUND(precision, 4) AS precision,
       ROUND(recall, 4)    AS recall,
       ROUND(f1_score, 4)  AS f1,
       ROUND(roc_auc, 4)   AS roc_auc,
       ROUND(log_loss, 4)  AS log_loss
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_logistic`)
UNION ALL
SELECT 'M4_random_forest',
       ROUND(accuracy, 4), ROUND(precision, 4), ROUND(recall, 4),
       ROUND(f1_score, 4), ROUND(roc_auc, 4), ROUND(log_loss, 4)
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_rf`);


-- ----------------------------------------------------------------------------
-- BLOQUE 3: MATRICES DE CONFUSIÓN
--  CAPTURA: evidencia_11_confusion.png
-- (Deja visible el SQL y la tabla con 4 filas por modelo)
-- ----------------------------------------------------------------------------
SELECT 'M3_regresion_logistica' AS modelo, expected_label, _0, _1
FROM ML.CONFUSION_MATRIX(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_logistic`)
UNION ALL
SELECT 'M4_random_forest', expected_label, _0, _1
FROM ML.CONFUSION_MATRIX(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_rf`);

-- ----------------------------------------------------------------------------
-- BLOQUE 4: CURVAS ROC (Solo crea tabla para el dashboard)
-- SIN CAPTURA: Solo verifica que diga "Query completed"
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.ml_roc_curves` AS
SELECT 'M3_regresion_logistica' AS modelo, c.*
FROM ML.ROC_CURVE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_logistic`) c
UNION ALL
SELECT 'M4_random_forest', c.*
FROM ML.ROC_CURVE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_rf`) c;


-- ----------------------------------------------------------------------------
-- BLOQUE 5a: TUNING M2 (Boosted Trees)
-- CAPTURA: evidencia_11_trials_btree.png
-- (Deja visible el SQL y la tabla con 8 filas ordenadas por eval_loss)
-- ----------------------------------------------------------------------------
SELECT trial_id,
       hyperparameters.learn_rate,
       hyperparameters.max_tree_depth,
       hyperparameters.subsample,
       training_loss,
       eval_loss,
       status,
       is_optimal
FROM ML.TRIAL_INFO(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_btree`)
ORDER BY CAST(eval_loss AS FLOAT64) ASC;


-- ----------------------------------------------------------------------------
-- BLOQUE 5b: TUNING M4 (Random Forest)
--  CAPTURA: evidencia_11_trials_rf.png
-- (Deja visible el SQL y la tabla con 4 filas ordenadas por eval_loss)
-- ----------------------------------------------------------------------------
SELECT trial_id,
       hyperparameters.max_tree_depth,
       hyperparameters.num_parallel_tree,
       hyperparameters.subsample,
       training_loss,
       eval_loss,
       status,
       is_optimal
FROM ML.TRIAL_INFO(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_rf`)
ORDER BY CAST(eval_loss AS FLOAT64) ASC;


-- ----------------------------------------------------------------------------
-- BLOQUE 6a: IMPORTANCIA DE VARIABLES M2
-- CAPTURA: evidencia_11_explain_btree.png
-- (Deja visible el SQL y la tabla con las 15 features más importantes)
-- ----------------------------------------------------------------------------
SELECT 
  feature,
  ROUND(importance_gain, 4) AS importancia,
  ROUND(importance_gain / SUM(importance_gain) OVER() * 100, 2) AS porcentaje_contribucion
FROM ML.FEATURE_IMPORTANCE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_btree`)
ORDER BY importance_gain DESC
LIMIT 15;

-- ----------------------------------------------------------------------------
-- BLOQUE 6b: IMPORTANCIA DE VARIABLES M4
-- CAPTURA: evidencia_11_explain_rf.png
-- (Deja visible el SQL y la tabla con las 15 features más importantes)
-- ----------------------------------------------------------------------------
SELECT 
  feature,
  ROUND(importance_gain, 4) AS importancia,
  ROUND(importance_gain / SUM(importance_gain) OVER() * 100, 2) AS porcentaje_contribucion
FROM ML.FEATURE_IMPORTANCE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_rf`)
ORDER BY importance_gain DESC
LIMIT 15;

-- ----------------------------------------------------------------------------
-- BLOQUE 7: PESOS DEL MODELO LINEAL (Interpretabilidad)
-- CAPTURA: evidencia_11_weights.png
-- (Deja visible el SQL y la tabla ordenada por peso absoluto)
-- ----------------------------------------------------------------------------
SELECT processed_input AS variable, ROUND(weight, 4) AS peso
FROM ML.WEIGHTS(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_linear`)
ORDER BY ABS(weight) DESC;


-- ----------------------------------------------------------------------------
-- BLOQUE 8: ESTADÍSTICAS DE FEATURES (Anti-leakage proof)
-- CAPTURA: evidencia_11_feature_info.png
-- (Deja visible el SQL y la tabla con min/max/mean de cada feature)
-- ----------------------------------------------------------------------------
SELECT *
FROM ML.FEATURE_INFO(
  MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_linear`,
  INPUT => (
    SELECT trip_distance, trip_duration_minutes, avg_speed_mph, passenger_count,
           pickup_hour, fare_amount, split_set
    FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.vw_ml_fare`
  ),
  threshold => 0.001);


-- ----------------------------------------------------------------------------
-- BLOQUE 9: TABLA PERSISTIDA PARA DASHBOARD
-- SIN CAPTURA: Solo verifica que diga "Query completed"
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.ml_metrics_comparativa` AS
SELECT 'M1_regresion_lineal' AS modelo, 'Regresion' AS tipo,
       mean_squared_error AS mse, mean_absolute_error AS mae,
       SQRT(mean_squared_error) AS rmse, r2_score AS r2,
       CAST(NULL AS FLOAT64) AS accuracy, CAST(NULL AS FLOAT64) AS roc_auc,
       CAST(NULL AS FLOAT64) AS f1_score
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_linear`)
UNION ALL
SELECT 'M2_boosted_trees', 'Regresion',
       mean_squared_error, mean_absolute_error, SQRT(mean_squared_error),
       r2_score, NULL, NULL, NULL
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_btree`)
UNION ALL
SELECT 'M3_regresion_logistica', 'Clasificacion',
       NULL, NULL, NULL, NULL, accuracy, roc_auc, f1_score
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_logistic`)
UNION ALL
SELECT 'M4_random_forest', 'Clasificacion',
       NULL, NULL, NULL, NULL, accuracy, roc_auc, f1_score
FROM ML.EVALUATE(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_rf`);