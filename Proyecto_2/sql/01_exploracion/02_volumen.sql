-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/01_exploracion/02_volumen.sql
-- Objetivo  : Validar que el dataset cumple el requisito mínimo de 1 millón
--             de registros (rúbrica 9.1) y establecer la cobertura temporal
--             que después define el split TRAIN/EVAL/TEST de los modelos.
-- Costo     : Bloque 1 = 0 bytes (COUNT(*) usa metadatos).
--             Bloques 2 y 3 = aprox. 0.4 GB (solo lee pickup_datetime).
-- Evidencias: evidencia_02_volumen.png (bloque 1),
--             evidencia_02_cobertura.png (bloque 2),
--             evidencia_02_mensual.png (bloque 3).
-- Resultado esperado bloque 1: 36,256,539 registros.
-- Nota para el README: el enunciado menciona "más de 100 millones", cifra
-- que corresponde a la familia completa de tablas TLC; la tabla yellow 2022
-- por sí sola tiene 36.26 M, muy por encima del mínimo exigido.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BLOQUE 1: conteo total de registros. Requisito >= 1,000,000.
-- Capturar: resultado (36256539) junto al mensaje "will process 0 B".
-- ----------------------------------------------------------------------------
SELECT COUNT(*) AS total_registros
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`;

-- ----------------------------------------------------------------------------
-- BLOQUE 2: ventana temporal y granularidad de cobertura.
-- Justifica que el split de ML pueda hacerse por rangos de fecha.
-- ----------------------------------------------------------------------------
SELECT
  MIN(pickup_datetime)                              AS primer_viaje,
  MAX(pickup_datetime)                              AS ultimo_viaje,
  COUNT(DISTINCT DATE(pickup_datetime))             AS dias_con_datos,
  COUNT(DISTINCT EXTRACT(MONTH FROM pickup_datetime)) AS meses_cubiertos,
  ROUND(COUNT(*) / COUNT(DISTINCT DATE(pickup_datetime)), 0) AS viajes_por_dia
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`;

-- ----------------------------------------------------------------------------
-- BLOQUE 3: distribución mensual de viajes (función de ventana sobre
-- agregados). Detecta meses incompletos que deban excluirse del análisis.
-- ----------------------------------------------------------------------------
SELECT
  EXTRACT(MONTH FROM pickup_datetime)               AS mes,
  COUNT(*)                                          AS viajes,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_del_anio
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`
GROUP BY 1
ORDER BY 1;