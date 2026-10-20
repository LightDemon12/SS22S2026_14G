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
-- HIPERPARÁMETROS Y SU PORQUÉ:
--   l2_reg = 0.05        : regularización ridge suave; con 20+ features y
--                          millones de filas el sobreajuste no es el riesgo
--                          principal, pero controla pesos explosivos.
--   learn_rate = 0.1     : paso estándar para descenso de gradiente en BQML.
--   max_iterations = 30  : suficiente para convergencia lineal.
--   early_stop = TRUE    : detiene al estabilizarse la pérdida; ahorra costo.
--   data_split_method CUSTOM + data_split_col split_set:
--                          TRAIN entrena, EVAL evalúa, TEST queda intacto
--                          para la fase de predicciones (anti leakage).
-- PROPÓSITO ANALÍTICO: establecer piso de rendimiento y verificar que el
--   pipeline de datos funciona antes de invertir en modelos costosos. Sus
--   pesos (ML.WEIGHTS) dan interpretabilidad económica del precio por milla.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_linear`
OPTIONS(
  model_type        = 'LINEAR_REG',
  input_label_cols  = ['fare_amount'],
  data_split_method = 'CUSTOM',
  data_split_col    = 'split_set',
  l2_reg            = 0.05,
  learn_rate        = 0.1,
  max_iterations    = 30,
  early_stop        = TRUE
) AS
SELECT
  trip_distance, trip_duration_minutes, avg_speed_mph, passenger_count,
  pickup_hour, pickup_dow, pickup_month,
  is_weekend, is_rush_am, is_rush_pm, is_night, is_holiday,
  is_airport_pickup, is_airport_dropoff, is_hot_zone,
  extra, tolls_amount, congestion_surcharge,
  pickup_borough, dropoff_borough, vendor_id_str, distance_bucket,
  fare_amount,
  split_set
FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_fare`;

-- Información de entrenamiento de M1 (iteraciones, pérdida, duración).
-- Capturar como evidencia_09_m1_training.png.
SELECT * FROM ML.TRAINING_INFO(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_linear`);


-- ----------------------------------------------------------------------------
-- MODELO M2: BOOSTED TREE REGRESSOR CON TUNING AUTOMÁTICO (VIZIER).
-- HIPERPARÁMETROS FIJOS Y SU PORQUÉ:
--   booster_type GBTREE      : gradient boosting estándar, mejor compromiso
--                              precisión/tiempo frente a DART.
--   loss_type MEAN_SQUARED_ERROR : coherente con la métrica RMSE del reporte.
--   max_iterations = 60      : tope de rondas de boosting por ensayo.
--   early_stop = FALSE       : OBLIGATORIO al activar tuning de
--                              hiperparámetros (restricción de BQML); el
--                              criterio de parada lo define VIZIER.
--   min_split_loss = 0, l2_reg = 0.1 : regularización leve anti sobreajuste.
-- HIPERPARÁMETROS EXPLORADOS POR VIZIER (8 ensayos, 2 en paralelo):
--   hp_max_tree_depth [4,8,12]    : profundidad = capacidad de interacción.
--   hp_learn_rate 0.05:0.05:0.2   : paso de aprendizaje (rango discreto).
--   hp_num_parallel_tree [2,4]    : árboles por ronda (bagging interno).
--   hp_subsample [0.7,0.85,1.0]   : fracción de filas por ronda.
-- PROPÓSITO: capturar no linealidades (tarifa mínima, esperas, congestión)
--   que el modelo lineal no puede representar. La comparación M1 vs M2 es
--   la evidencia del criterio 1.5.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_btree`
OPTIONS(
  model_type                = 'BOOSTED_TREE_REGRESSOR',
  input_label_cols          = ['fare_amount'],
  data_split_method         = 'CUSTOM',
  data_split_col            = 'split_set',
  booster_type              = 'GBTREE',
  loss_type                 = 'MEAN_SQUARED_ERROR',
  max_iterations            = 60,
  early_stop                = FALSE,
  min_split_loss            = 0,
  l2_reg                    = 0.1,
  hp_param_tuning_algorithm = 'VIZIER',
  num_trials                = 8,
  max_parallel_trials       = 2,
  hp_max_tree_depth         = [4, 8, 12],
  hp_learn_rate             = 0.05:0.05:0.2,
  hp_num_parallel_tree      = [2, 4],
  hp_subsample              = [0.7, 0.85, 1.0]
) AS
SELECT
  trip_distance, trip_duration_minutes, avg_speed_mph, passenger_count,
  pickup_hour, pickup_dow, pickup_month,
  is_weekend, is_rush_am, is_rush_pm, is_night, is_holiday,
  is_airport_pickup, is_airport_dropoff, is_hot_zone,
  extra, tolls_amount, congestion_surcharge,
  pickup_borough, dropoff_borough, vendor_id_str, distance_bucket,
  fare_amount,
  split_set
FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_fare`;

-- Información de entrenamiento de M2 (un registro por ensayo del tuning).
-- Capturar como evidencia_09_m2_training.png.
SELECT * FROM ML.TRAINING_INFO(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_fare_btree`);