-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/04_ml/09_modelos_regresion.sql
-- Objetivo  : Entrenar dos modelos de regresión para predecir fare_amount
--             (rúbrica 1.4): un baseline lineal interpretable y un modelo
--             de árboles con tuning automático de hiperparámetros.
-- Problema  : ¿cuál será la tarifa de medidor de un viaje dadas las
--             características conocidas al inicio del servicio?
-- Costo     : M1 aprox. 2.5 GB procesados. M2 aprox. 20 GB (8 ensayos
--             VIZIER, cada uno relee el split TRAIN a través de la vista).
-- Tiempo    : M1 ~1-3 min. M2 ~10-25 min (job asíncrono: puede cerrar la
--             pestaña, el entrenamiento sigue en Job history).
-- Evidencias: evidencia_09_m1_creado.png, evidencia_09_m1_training.png,
--             evidencia_09_m2_creado.png, evidencia_09_m2_training.png.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- MODELO M1: REGRESIÓN LINEAL (baseline interpretable).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_linear`
OPTIONS(
  model_type        = 'LINEAR_REG',
  input_label_cols  = ['fare_amount'],
  data_split_method = 'CUSTOM',
  data_split_col    = 'is_eval',
  l2_reg            = 0.05,
  ls_init_learn_rate = 0.1,
  max_iterations    = 30,
  early_stop        = TRUE
) AS
SELECT
  trip_distance, trip_duration_minutes, avg_speed_mph, passenger_count,
  pickup_hour, pickup_dow, pickup_month,
  is_weekend, is_rush_am, is_rush_pm, is_night, is_holiday,
  is_airport_pickup, is_airport_dropoff, is_hot_zone,
  extra, tolls_amount,
  pickup_borough, dropoff_borough, vendor_id_str, distance_bucket,
  fare_amount,
  (split_set = 'EVAL') AS is_eval
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.vw_ml_fare`
WHERE split_set IN ('TRAIN', 'EVAL');

-- Información de entrenamiento de M1 (iteraciones, pérdida, duración).
-- Capturar como evidencia_09_m1_training.png.
SELECT * FROM ML.TRAINING_INFO(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_linear`);


-- ----------------------------------------------------------------------------
-- MODELO M2: BOOSTED TREE REGRESSOR CON TUNING AUTOMÁTICO (VIZIER).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_btree`
OPTIONS(
  model_type                = 'BOOSTED_TREE_REGRESSOR',
  input_label_cols          = ['fare_amount'],
  data_split_method         = 'CUSTOM',
  data_split_col            = 'split_set',
  booster_type              = 'GBTREE',
  max_iterations            = 30, 
  early_stop                = FALSE, 
  min_split_loss            = 0,
  l2_reg                    = 0.1,
  num_trials                = 3, 
  max_parallel_trials       = 3,     
  max_tree_depth            = HPARAM_CANDIDATES([6, 10]), 
  learn_rate                = HPARAM_CANDIDATES([0.05, 0.1]),
  subsample                 = HPARAM_CANDIDATES([0.8, 1.0])
) AS
SELECT
  trip_distance, trip_duration_minutes, avg_speed_mph, passenger_count,
  pickup_hour, pickup_dow, pickup_month,
  is_weekend, is_rush_am, is_rush_pm, is_night, is_holiday,
  is_airport_pickup, is_airport_dropoff, is_hot_zone,
  extra, tolls_amount,
  pickup_borough, dropoff_borough, vendor_id_str, distance_bucket,
  fare_amount,
  split_set
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.vw_ml_fare`
WHERE split_set IN ('TRAIN', 'EVAL');

-- Información de entrenamiento de M2 (un registro por ensayo del tuning).
-- Capturar como evidencia_09_m2_training.png.
SELECT * FROM ML.TRIAL_INFO(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_btree`);