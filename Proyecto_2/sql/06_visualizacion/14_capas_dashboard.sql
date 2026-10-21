-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/06_visualizacion/14_capas_dashboard.sql
-- Objetivo  : Materializar las últimas capas pequeñas que alimentan el
--             tablero de Looker Studio y dejar documentado en este archivo
--             el plan de construcción del informe visual (entregable 3.4).
-- Principio : Looker Studio NUNCA se conecta a fact_trips_opt (30 M filas):
--             todas las fuentes del dashboard son tablas agregadas de menos
--             de 1,000 filas. Consultas rápidas, costo cercano a cero y
--             gráficos que cargan al instante durante la calificación.
-- Costo     : < 0.5 GB en total (solo lee pred_fare_test y agregados).
-- Evidencias: evidencia_14_capas.png (bloque 6),
--             evidencia_14_dashboard_p1..p4.png (capturas del tablero).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BLOQUE 1: MATRICES DE CONFUSIÓN PERSISTIDAS (página de modelos).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.ml_confusion_matrices` AS
SELECT 'M3_regresion_logistica' AS modelo, c.*
FROM ML.CONFUSION_MATRIX(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_logistic`) c
UNION ALL
SELECT 'M4_random_forest', c.*
FROM ML.CONFUSION_MATRIX(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_rf`) c;

-- ----------------------------------------------------------------------------
-- BLOQUE 2: IMPORTANCIA DE VARIABLES PERSISTIDA (página de modelos).
-- Fuente de la gráfica de barras que justifica la ingeniería de
-- características (rúbrica 2.3) dentro del propio dashboard.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.ml_feature_importance` AS
SELECT 'M2_boosted_trees' AS modelo, feature AS variable, ROUND(attribution, 4) AS importancia
FROM ML.GLOBAL_EXPLAIN(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_fare_btree`, top_k_features => 15)
UNION ALL
SELECT 'M4_random_forest', feature, ROUND(attribution, 4)
FROM ML.GLOBAL_EXPLAIN(MODEL `ss2-2026-pareja14-v2.taxi_ss2_2026.mdl_tip_rf`, top_k_features => 15);

-- ----------------------------------------------------------------------------
-- BLOQUE 3: KPIs GLOBALES (scorecards de la página 1).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_kpis` AS
SELECT
  (SELECT SUM(trip_count) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily`) AS total_viajes,
  (SELECT ROUND(SUM(revenue_fare), 2) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily`) AS revenue_fare_usd,
  (SELECT ROUND(SUM(revenue_tips), 2) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily`) AS revenue_tips_usd,
  (SELECT ROUND(SUM(revenue_fare) / SUM(trip_count), 2) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily`) AS fare_promedio_usd,
  (SELECT CONCAT(CAST(pickup_hour AS STRING), ':00 - ', nombre_dia)
     FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_hourly_profile`
    ORDER BY n_viajes DESC LIMIT 1) AS pico_demanda,
  (SELECT zone FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_zones`
    WHERE rank_origen = 1) AS zona_top_origen;

-- ----------------------------------------------------------------------------
-- BLOQUE 4: CAPAS EXPLORATORIAS RESTANTES.
-- dash_monthly      : tendencia mensual (línea de la página 2).
-- dash_zones_top    : top 15 zonas ya rankeadas (barras de la página 2).
-- dash_scatter_fare : dispersión distancia vs tarifa REAL vs PREDICHA,
--                     agregada en buckets de 0.5 mi para que el gráfico de
--                     dispersión sea legible y ligero (aprox. 40 filas).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_monthly` AS
SELECT
  EXTRACT(MONTH FROM pickup_date) AS mes,
  FORMAT_DATE('%b', DATE(CONCAT('2022-', LPAD(CAST(EXTRACT(MONTH FROM pickup_date) AS STRING), 2, '0'), '-01'))) AS nombre_mes,
  SUM(trip_count)                    AS viajes,
  ROUND(SUM(revenue_fare), 2)        AS revenue_fare,
  ROUND(SUM(revenue_tips), 2)        AS revenue_tips,
  ROUND(SUM(revenue_fare) / SUM(trip_count), 2) AS fare_promedio
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily`
GROUP BY 1, 2
ORDER BY 1;

CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_zones_top` AS
SELECT *
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_zones`
WHERE rank_origen <= 15;

CREATE OR REPLACE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_scatter_fare` AS
SELECT
  ROUND(FLOOR(trip_distance * 2) / 2, 1) AS distancia_bucket_mi,
  COUNT(*)                          AS n_viajes,
  ROUND(AVG(fare_real), 2)          AS fare_real_prom,
  ROUND(AVG(fare_predicho), 2)      AS fare_pred_prom
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.pred_fare_test`
GROUP BY 1
ORDER BY 1;

-- ----------------------------------------------------------------------------
-- BLOQUE 5: RESUMEN DE DISPERSIÓN REAL VS PREDICHA (métrica de la página 3).
-- ----------------------------------------------------------------------------
SELECT
  ROUND(SQRT(AVG(POW(fare_real_prom - fare_pred_prom, 2))), 3) AS rmse_entre_promedios,
  MAX(n_viajes) AS viajes_en_bucket_mayor
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_scatter_fare`;

-- ----------------------------------------------------------------------------
-- BLOQUE 6: INVENTARIO FINAL DE FUENTES DEL DASHBOARD (0 bytes).
-- Capturar como evidencia_14_capas.png. Estas 16 tablas son exactamente las
-- fuentes de datos que se conectan en Looker Studio.
-- ----------------------------------------------------------------------------
SELECT 'dash_kpis' AS fuente, COUNT(*) AS filas FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_kpis`
UNION ALL SELECT 'agg_daily', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_daily`
UNION ALL SELECT 'agg_hourly_profile', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_hourly_profile`
UNION ALL SELECT 'dash_zones_top', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_zones_top`
UNION ALL SELECT 'agg_payment', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_payment`
UNION ALL SELECT 'agg_routes', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.agg_routes`
UNION ALL SELECT 'dash_monthly', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_monthly`
UNION ALL SELECT 'dash_scatter_fare', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_scatter_fare`
UNION ALL SELECT 'ml_metrics_comparativa', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.ml_metrics_comparativa`
UNION ALL SELECT 'ml_roc_curves', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.ml_roc_curves`
UNION ALL SELECT 'ml_confusion_matrices', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.ml_confusion_matrices`
UNION ALL SELECT 'ml_feature_importance', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.ml_feature_importance`
UNION ALL SELECT 'dash_tip_calibration', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_tip_calibration`
UNION ALL SELECT 'dash_pred_fare_daily', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_pred_fare_daily`
UNION ALL SELECT 'forecast_rolling', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.forecast_rolling`
UNION ALL SELECT 'forecast_rolling_metrics', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.forecast_rolling_metrics`
UNION ALL SELECT 'forecast_revenue', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.forecast_revenue`
UNION ALL SELECT 'dash_anomalies', COUNT(*) FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.dash_anomalies`;


-- ============================================================================
-- GUÍA DE CONSTRUCCIÓN DEL TABLOERO EN LOOKER STUDIO (ejecutar en la UI)
-- ============================================================================
-- PASO 1: lookerstudio.google.com -> Informe en blanco -> conector BigQuery
--         -> proyecto ss2-2026-pareja14-v2 -> dataset taxi_ss2_2026.
--         Conectar las 16 fuentes del bloque 6 (una por una).
--
-- PASO 2: Página 1 "Resumen ejecutivo"
--   - 5 scorecards con dash_kpis: total_viajes, revenue_fare_usd,
--     revenue_tips_usd, fare_promedio_usd, pico_demanda.
--   - Línea temporal: fuente agg_daily, dimensión pickup_date,
--     métricas trip_count y revenue_fare.
--   - Control de intervalo de fechas ligado a agg_daily.
--
-- PASO 3: Página 2 "Análisis exploratorio" (>= 3 visualizaciones exigidas)
--   V1 Mapa de calor: fuente agg_hourly_profile, filas nombre_dia,
--      columnas pickup_hour, métrica n_viajes (tabla con escala de color).
--   V2 Barras: fuente dash_zones_top, dimensión zone, métrica viajes_origen,
--      desglose borough.
--   V3 Línea: fuente dash_monthly, dimensión nombre_mes, métricas viajes y
--      revenue_fare (eje derecho).
--   V4 Barras: fuente agg_payment, dimensión metodo_pago, métricas
--      n_viajes y pct_con_propina (muestra propina cero en efectivo).
--   V5 Tabla: fuente agg_routes, top rutas origen-destino.
--   Cada gráfico con un cuadro de texto de UNA frase interpretativa.
--
-- PASO 4: Página 3 "Modelos de BigQuery ML"
--   - Barras agrupadas: ml_metrics_comparativa, dimensión modelo,
--     métricas rmse y r2 (regresión) y roc_auc y f1_score (clasificación).
--   - Curvas ROC: ml_roc_curves, dimensión false_positive_rate,
--     métrica recall, serie modelo.
--   - Tabla: ml_confusion_matrices.
--   - Línea de calibración: dash_tip_calibration, dimensión
--     bucket_probabilidad, métricas probabilidad_promedio y tasa_real_high_tip.
--   - Barras de importancia: ml_feature_importance, dimensión variable,
--     métrica importancia, serie modelo.
--   - Dispersión: dash_scatter_fare, dimensión distancia_bucket_mi,
--     métricas fare_real_prom y fare_pred_prom (real vs predicho).
--
-- PASO 5: Página 4 "Rolling Forecast"
--   - Línea principal: forecast_rolling, dimensión fecha, métricas
--     viajes_reales y viajes_predichos, serie ventana; agregar
--     limite_inferior y limite_superior como líneas punteadas (banda 95%).
--   - Control de lista desplegable sobre el campo ventana.
--   - Barras: forecast_rolling_metrics, dimensión ventana, métricas
--     mape_pct y cobertura_ic_pct.
--   - Línea secundaria: forecast_revenue, dimensión fecha, métricas
--     revenue_real y revenue_predicho.
--   - Tabla de anomalías: dash_anomalies filtrada por is_anomaly = true.
--
-- PASO 6: Compartir -> "Cualquier persona con el enlace" -> Lector.
--         Copiar el enlace al README. Exportar PDF de respaldo a
--         docs/dashboard_export.pdf por si el enlace falla el día de revisión.
-- ============================================================================