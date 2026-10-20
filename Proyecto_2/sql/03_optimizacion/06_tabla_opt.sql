-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/03_optimizacion/06_tabla_opt.sql
-- Objetivo  : Crear la versión OPTIMIZADA de la tabla de hechos con
--             partición por fecha y clustering por ubicaciones, y certificar
--             que ambas técnicas quedaron aplicadas (estado "DESPUÉS").
-- Costo     : Bloque 1 lee fact_trips_std completa (aprox. 3 GB) y escribe
--             una copia similar. Bloques 2 a 4 = 0 bytes.
-- Evidencias: evidencia_06_creacion_opt.png (bloque 1),
--             evidencia_06_particiones.png (bloque 2),
--             evidencia_06_opciones.png (bloque 3),
--             evidencia_06_details_clustering.png (tab Details de la consola).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BLOQUE 1: CREACIÓN DE LA TABLA OPTIMIZADA.
--
-- DECISIONES DE DISEÑO (justificación exigida por rúbrica 1.3 y 2.5):
--
-- 1) PARTITION BY pickup_date (granularidad DIARIA):
--    - El 100% de las consultas analíticas del proyecto filtra por rango
--      temporal (benchmarks, agregados diarios, forecast, split de ML).
--    - 365 particiones anuales, muy por debajo del límite de 4000 por tabla.
--    - Se elige DÍA y no MES porque las consultas típicas piden "una semana"
--      o "un mes": con partición diaria el podado es exacto; con partición
--      mensual una consulta de 7 días leería 2 meses completos.
--    - Se particiona sobre la columna DATE materializada (pickup_date) y no
--      sobre DATE(pickup_datetime) para que el filtro en WHERE sea trivial
--      y visible para cualquier persona que consulte la tabla.
--
-- 2) CLUSTER BY pickup_location_id, dropoff_location_id:
--    - Son los filtros y agrupaciones geográficas más frecuentes del
--      proyecto (top zonas, rutas origen-destino, modelos por borough).
--    - El ORDEN importa: primero pickup_location_id (más selectivo y más
--      usado), luego dropoff_location_id. BigQuery poda bloques usando el
--      prefijo del orden de clustering.
--    - Se limitan a 2 columnas: con 4 columnas de clustering los bloques se
--      fragmentan demasiado y las consultas amplias (sin filtro geográfico)
--      perderían rendimiento en lugar de ganarlo.
--    - NO se clusteriza por vendor_id ni payment_type: con 2 y 6 valores
--      distintos su cardinalidad es demasiado baja para aportar podado.
--
-- 3) Los datos provienen de fact_trips_std (SELECT *), garantizando que el
--    benchmark compare DOS DISPOSICIONES FÍSICAS DEL MISMO CONJUNTO DE DATOS,
--    no conjuntos distintos. Esa es la validez experimental de la comparación.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_opt`
PARTITION BY pickup_date
CLUSTER BY pickup_location_id, dropoff_location_id
OPTIONS(description='Tabla optimizada: particion diaria por pickup_date y clustering por zona origen/destino')
AS
SELECT *
FROM `ss2-2026-pareja14.taxi_ss2_2026.fact_trips_std`;

-- ----------------------------------------------------------------------------
-- BLOQUE 2: Verificación de particionamiento.
-- Resultado esperado: n_particiones aproximadamente 365 (una por día con
-- datos), contra 1 de la tabla estándar (archivo 05, bloque 1).
-- ----------------------------------------------------------------------------
SELECT
  COUNT(*)            AS n_particiones,
  MIN(partition_id)   AS primera_particion,
  MAX(partition_id)   AS ultima_particion
FROM `ss2-2026-pareja14.taxi_ss2_2026.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name = 'fact_trips_opt';

-- ----------------------------------------------------------------------------
-- BLOQUE 3: Opciones físicas de ambas tablas, lado a lado.
-- En fact_trips_opt deben aparecer las opciones de descripción y, según la
-- versión de la vista, los campos de clustering. Si clustering_fields no
-- apareciera aquí, la evidencia oficial es el tab Details de la consola
-- (captura evidencia_06_details_clustering.png), que muestra
-- "Clustered by: pickup_location_id, dropoff_location_id".
-- ----------------------------------------------------------------------------
SELECT
  table_name,
  option_name,
  option_value
FROM `ss2-2026-pareja14.taxi_ss2_2026.INFORMATION_SCHEMA.TABLE_OPTIONS`
WHERE table_name IN ('fact_trips_std', 'fact_trips_opt')
ORDER BY table_name, option_name;

-- ----------------------------------------------------------------------------
-- BLOQUE 4: Tamaño de ambas copias (deben ser casi idénticos: mismos datos).
-- Si opt pesara mucho menos que std, algo se filtró por error en el CREATE.
-- ----------------------------------------------------------------------------
SELECT
  table_id,
  row_count                           AS filas,
  ROUND(size_bytes / POW(1024, 3), 2) AS gb_logicos
FROM `ss2-2026-pareja14.taxi_ss2_2026.__TABLES__`
WHERE table_id IN ('fact_trips_std', 'fact_trips_opt')
ORDER BY table_id;