-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/04_ml/10_modelos_clasificacion.sql
-- Objetivo  : Entrenar dos clasificadores binarios de high_tip (propina
--             >= 20% de la tarifa) sobre vw_ml_tip (solo pagos con tarjeta).
-- Problema  : ¿es probable que el pasajero deje propina alta? Útil para
--             segmentación de servicio y estimación de ingreso del conductor.
-- Costo     : M3 aprox. 2.5 GB. M4 aprox. 10-15 GB (4 ensayos VIZIER).
-- Tiempo    : M3 ~2-4 min. M4 ~15-40 min (job asíncrono).
--             SI M4 SUPERARA 45 MIN o fallara por recursos: ejecutar el
--             bloque ALTERNATIVO comentado al final (BOOSTED_TREE_CLASSIFIER
--             con 4 ensayos), que es más ligero y cumple igual la rúbrica.
-- Evidencias: evidencia_10_m3_creado.png, evidencia_10_m3_training.png,
--             evidencia_10_m4_creado.png, evidencia_10_m4_training.png.
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
--   data_split CUSTOM sobre split_set (misma estrategia anti leakage).
-- NOTA: fare_amount SÍ es feature legítima aquí: el pasajero decide la
--   propina conociendo la tarifa, no al revés. No hay fuga porque la
--   etiqueta high_tip se excluye de las entradas.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_logistic`
OPTIONS(
  model_type         = 'LOGISTIC_REG',
  input_label_cols   = ['high_tip'],
  data_split_method  = 'CUSTOM',
  data_split_col     = 'split_set',
  l1_reg             = 0.001,
  l2_reg             = 0.05,
  learn_rate         = 0.1,
  max_iterations     = 100,
  early_stop         = TRUE,
  auto_class_weights = TRUE
) AS
SELECT
  fare_amount, trip_distance, trip_duration_minutes, avg_speed_mph,
  passenger_count, pickup_hour, pickup_dow, pickup_month,
  is_weekend, is_rush_am, is_rush_pm, is_night, is_holiday,
  is_airport_pickup, is_airport_dropoff, is_hot_zone,
  extra, tolls_amount, congestion_surcharge,
  pickup_borough, dropoff_borough, vendor_id_str, distance_bucket,
  high_tip,
  split_set
FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_tip`;

SELECT * FROM ML.TRAINING_INFO(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_logistic`);


-- ----------------------------------------------------------------------------
-- MODELO M4: RANDOM FOREST CLASSIFIER CON TUNING AUTOMÁTICO.
-- HIPERPARÁMETROS FIJOS:
--   min_split_loss = 0, subsample base 0.8 (explorado por VIZIER abajo).
--   auto_class_weights = TRUE (misma razón que M3).
-- HIPERPARÁMETROS EXPLORADOS (4 ensayos, 2 en paralelo):
--   hp_max_tree_depth [8,12,16]   : bosques profundos capturan interacciones
--                                   hora x zona x tarifa.
--   hp_num_parallel_tree [40,60]  : tamaño del bosque (menos árboles que 100
--                                   para mantener el tiempo de entrenamiento
--                                   dentro de lo razonable en sandbox).
--   hp_subsample 0.6:0.2:1.0      : diversidad de bolsas por árbol.
-- PROPÓSITO: modelo no lineal de ensamble que sirve de contraste frente a
--   M3; la diferencia de ROC-AUC entre ambos justifica la selección final.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_rf`
OPTIONS(
  model_type                = 'RANDOM_FOREST_CLASSIFIER',
  input_label_cols          = ['high_tip'],
  data_split_method         = 'CUSTOM',
  data_split_col            = 'split_set',
  min_split_loss            = 0,
  auto_class_weights        = TRUE,
  hp_param_tuning_algorithm = 'VIZIER',
  num_trials                = 4,
  max_parallel_trials       = 2,
  hp_max_tree_depth         = [8, 12, 16],
  hp_num_parallel_tree      = [40, 60],
  hp_subsample              = 0.6:0.2:1.0
) AS
SELECT
  fare_amount, trip_distance, trip_duration_minutes, avg_speed_mph,
  passenger_count, pickup_hour, pickup_dow, pickup_month,
  is_weekend, is_rush_am, is_rush_pm, is_night, is_holiday,
  is_airport_pickup, is_airport_dropoff, is_hot_zone,
  extra, tolls_amount, congestion_surcharge,
  pickup_borough, dropoff_borough, vendor_id_str, distance_bucket,
  high_tip,
  split_set
FROM `ss2-2026-pareja14.taxi_ss2_2026.vw_ml_tip`;

SELECT * FROM ML.TRAINING_INFO(MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_rf`);

-- ----------------------------------------------------------------------------
-- BLOQUE ALTERNATIVO (solo si M4 falla o excede 45 minutos):
-- descomentar y ejecutar; luego tratarlo como M4 en el archivo 11.
-- ----------------------------------------------------------------------------
-- CREATE OR REPLACE MODEL `ss2-2026-pareja14.taxi_ss2_2026.mdl_tip_rf`
-- OPTIONS(
--   model_type                = 'BOOSTED_TREE_CLASSIFIER',
--   input_label_cols          = ['high_tip'],
--   data_split_method         = 'CUSTOM',
--   data_split_col            = 'split_set',
--   booster_type              = 'GBTREE',
--   max_iterations            = 50,
--   early_stop                = FALSE,
--   auto_class_weights        = TRUE,
--   hp_param_tuning_algorithm = 'VIZIER',
--   num_trials                = 4,
--   max_parallel_trials       = 2,
--   hp_max_tree_depth         = [4, 8, 12],
--   hp_learn_rate             = 0.05:0.05:0.2
-- ) AS
-- SELECT ... (mismo SELECT del bloque M4) ...;