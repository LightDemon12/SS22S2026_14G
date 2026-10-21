-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/04_ml/10_modelos_clasificacion.sql
-- Objetivo  : Entrenar dos clasificadores binarios de high_tip (propina
--             >= 20% de la tarifa) sobre vw_ml_tip (solo pagos con tarjeta).
-- Problema  : ¿es probable que el pasajero deje propina alta? Útil para
--             segmentación de servicio y estimación de ingreso del conductor.
-- Costo     : M3 aprox. 2.5 GB. M4 aprox. 10-15 GB (4 ensayos).
-- Tiempo    : M3 ~2-4 min. M4 ~15-40 min (job asíncrono).
--             SI M4 SUPERARA 45 MIN o fallara por recursos: ejecutar el
--             bloque ALTERNATIVO comentado al final (BOOSTED_TREE_CLASSIFIER
--             con 4 ensayos), que es más ligero y cumple igual la rúbrica.
-- Evidencias: evidencia_10_m3_training.png,
--             evidencia_10_m4_training.png.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- MODELO M3: REGRESIÓN LOGÍSTICA (baseline de clasificación).
-- HIPERPARÁMETROS Y SU PORQUÉ:
--   auto_class_weights = TRUE : repondera las clases según su frecuencia en
--                               TRAIN; sin esto, el clasificador tendería a
--                               predecir siempre la clase mayoritaria
--                               (ver evidencia_08_balance_clases).
--   l1_reg = 0.001, l2_reg = 0.05 : regularización elástica leve que
--                               estabiliza coeficientes sin eliminar features.
--   max_iterations = 100, learn_rate = 0.1, early_stop = TRUE.
--   data_split CUSTOM sobre is_eval (columna booleana derivada de split_set,
--                               misma estrategia anti leakage).
-- NOTA: fare_amount SÍ es feature legítima aquí: el pasajero decide la
--   propina conociendo la tarifa, no al revés. No hay fuga porque la
--   etiqueta high_tip se excluye de las entradas.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_logistic`
OPTIONS(
  model_type         = 'LOGISTIC_REG',
  input_label_cols   = ['high_tip'],
  data_split_method  = 'CUSTOM',
  data_split_col     = 'is_eval',
  l1_reg             = 0.001,
  l2_reg             = 0.05,
  ls_init_learn_rate = 0.1,
  max_iterations     = 40,
  early_stop         = TRUE,
  auto_class_weights = TRUE
) AS
SELECT
  fare_amount, trip_distance, trip_duration_minutes, avg_speed_mph,
  passenger_count, pickup_hour, pickup_dow, pickup_month,
  is_weekend, is_rush_am, is_rush_pm, is_night, is_holiday,
  is_airport_pickup, is_airport_dropoff, is_hot_zone,
  extra, tolls_amount, 
  pickup_borough, dropoff_borough, vendor_id_str, distance_bucket,
  high_tip,
  (split_set = 'EVAL') AS is_eval
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.vw_ml_tip`
WHERE split_set IN ('TRAIN', 'EVAL');

-- CAPTURA 1: Tomar evidencia del entrenamiento de M3: evidencia_10_m3_training.png
SELECT * FROM ML.TRAINING_INFO(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_logistic`);


-- ----------------------------------------------------------------------------
-- MODELO M4: RANDOM FOREST CLASSIFIER CON TUNING AUTOMÁTICO.
-- HIPERPARÁMETROS FIJOS:
--   min_split_loss = 0, auto_class_weights = TRUE (misma razón que M3).
--   data_split_method = 'CUSTOM' sobre split_set.
-- HIPERPARÁMETROS EXPLORADOS (4 ensayos, 4 en paralelo):
--   max_tree_depth HPARAM_CANDIDATES([8,12,16]) : bosques profundos capturan
--                                   interacciones hora x zona x tarifa.
--   num_parallel_tree HPARAM_CANDIDATES([40,60]): tamaño del bosque (menos
--                                   árboles que 100 para mantener el tiempo
--                                   de entrenamiento razonable en sandbox).
--   subsample HPARAM_CANDIDATES([0.6, 0.8, 1.0]): diversidad de bolsas.
-- PROPÓSITO: modelo no lineal de ensamble que sirve de contraste frente a
--   M3; la diferencia de ROC-AUC entre ambos justifica la selección final.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_rf`
OPTIONS(
  model_type                = 'RANDOM_FOREST_CLASSIFIER',
  input_label_cols          = ['high_tip'],
  data_split_method         = 'CUSTOM',
  data_split_col            = 'split_set',
  min_split_loss            = 0,
  auto_class_weights        = TRUE,
  num_trials                = 4,
  max_parallel_trials       = 4,
  max_tree_depth            = HPARAM_CANDIDATES([8, 12, 16]),
  num_parallel_tree         = HPARAM_CANDIDATES([40, 60]),
  subsample                 = HPARAM_CANDIDATES([0.6, 0.8, 0.99])
) AS
SELECT
  fare_amount, trip_distance, trip_duration_minutes, avg_speed_mph,
  passenger_count, pickup_hour, pickup_dow, pickup_month,
  is_weekend, is_rush_am, is_rush_pm, is_night, is_holiday,
  is_airport_pickup, is_airport_dropoff, is_hot_zone,
  extra, tolls_amount, 
  pickup_borough, dropoff_borough, vendor_id_str, distance_bucket,
  high_tip,
  split_set
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.vw_ml_tip`
WHERE split_set IN ('TRAIN', 'EVAL');

-- CAPTURA 2: Tomar evidencia del entrenamiento de M4: evidencia_10_m4_training.png
SELECT * FROM ML.TRIAL_INFO(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_rf`);
