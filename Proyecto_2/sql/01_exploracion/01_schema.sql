-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/01_exploracion/01_schema.sql
-- Objetivo  : Documentar la estructura real de la tabla pública antes de
--             escribir cualquier transformación. Google publica esta tabla
--             con códigos en STRING ('1.0') y montos en NUMERIC, distinto de
--             otras versiones del dataset; asumir tipos equivocados rompería
--             todo el proyecto en silencio.
-- Costo     : Bloques 1 y 2 = 0 bytes (INFORMATION_SCHEMA es metadato).
--             Bloque 3 = aprox. 1.5 GB (solo 6 de 20 columnas).
-- Evidencias: evidencia_01_schema.png (bloque 1),
--             evidencia_01_metadata.png (bloque 2),
--             evidencia_01_muestra.png (bloque 3, opcional: el tab Preview
--             de la consola da la misma muestra gratis).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BLOQUE 1: Esquema completo de la tabla (nombres, tipos, nulidad).
-- Capturar: cuadricula de resultados con las 20 filas visibles.
-- ----------------------------------------------------------------------------
SELECT
  ordinal_position  AS posicion,
  column_name       AS columna,
  data_type         AS tipo_dato,
  is_nullable       AS acepta_nulos
FROM `bigquery-public-data.new_york_taxi_trips.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'tlc_yellow_trips_2022'
ORDER BY ordinal_position;

-- ----------------------------------------------------------------------------
-- BLOQUE 2: Metadatos de volumen y tamaño lógico de la tabla.
-- Refuerza la validación de volumen con una fuente independiente del COUNT.
-- Si la consola reportara error en row_count, usar el tab Details de la
-- consola (36.26M rows / 6.97 GB) como evidencia equivalente.
-- ----------------------------------------------------------------------------
SELECT
  table_name,
  row_count                                AS filas,
  size_bytes                               AS bytes_logicos,
  ROUND(size_bytes / POW(1024, 3), 2)      AS gb_logicos,
  creation_time,
  last_modified_time
FROM `bigquery-public-data.new_york_taxi_trips.INFORMATION_SCHEMA.TABLES`
WHERE table_name = 'tlc_yellow_trips_2022';

-- ----------------------------------------------------------------------------
-- BLOQUE 3 (opcional): muestra de filas aplicando column pruning.
-- Se leen 6 columnas en lugar de 20: ~1.5 GB en vez de 6.97 GB de un SELECT *.
-- Sirve para inspeccionar el formato real de los STRING ('1.0' en rate_code).
-- ----------------------------------------------------------------------------
SELECT
  vendor_id,
  pickup_datetime,
  dropoff_datetime,
  trip_distance,
  fare_amount,
  payment_type
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`
LIMIT 15;