-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/03_optimizacion/05_tabla_std.sql
-- Objetivo  : Certificar el estado físico INICIAL (baseline) de la tabla de
--             hechos: SIN particiones y SIN clustering. Este archivo no crea
--             tablas: la tabla fact_trips_std fue materializada en
--             sql/02_transformaciones/04_metricas.sql (bloque 1). Recrearla
--             aquí duplicaría el almacenamiento (límite sandbox: 10 GB).
-- Costo     : 0 bytes en todos los bloques (INFORMATION_SCHEMA = metadatos).
-- Evidencias: evidencia_05_std_sin_particiones.png (bloque 1),
--             evidencia_05_std_opciones.png (bloque 2),
--             evidencia_05_std_tamano.png (bloque 3).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BLOQUE 1: Conteo de particiones de la tabla estándar.
-- Resultado esperado: 1 fila con partition_id NULL, es decir, la tabla NO
-- está particionada (BigQuery reporta una única "partición" anónima).
-- Este es el punto de comparación contra las ~365 particiones de la
-- tabla optimizada (archivo 06).
-- ----------------------------------------------------------------------------
SELECT
  COUNT(*)            AS n_particiones,
  MIN(partition_id)   AS primera_particion,
  MAX(partition_id)   AS ultima_particion
FROM `ss2-2026-pareja14.taxi_ss2_2026.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name = 'fact_trips_std';

-- ----------------------------------------------------------------------------
-- BLOQUE 2: Opciones físicas declaradas en la tabla estándar.
-- Resultado esperado: únicamente la opción 'description'. La ausencia de
-- opciones de partición/clustering confirma que es una tabla plana.
-- ----------------------------------------------------------------------------
SELECT
  table_name,
  option_name,
  option_value
FROM `ss2-2026-pareja14.taxi_ss2_2026.INFORMATION_SCHEMA.TABLE_OPTIONS`
WHERE table_name = 'fact_trips_std'
ORDER BY option_name;

-- ----------------------------------------------------------------------------
-- BLOQUE 3: Tamaño lógico y volumen de la línea base.
-- Anotar estos números en la tabla comparativa del README: son el "antes".
-- ----------------------------------------------------------------------------
SELECT
  table_id,
  row_count                           AS filas,
  size_bytes                          AS bytes_logicos,
  ROUND(size_bytes / POW(1024, 3), 2) AS gb_logicos
FROM `ss2-2026-pareja14.taxi_ss2_2026.__TABLES__`
WHERE table_id = 'fact_trips_std';