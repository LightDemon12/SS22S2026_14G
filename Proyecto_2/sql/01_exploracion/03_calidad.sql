-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/01_exploracion/03_calidad.sql
-- Objetivo  : Cuantificar nulos, inconsistencias y valores atípicos en UNA
--             sola pasada, para justificar con números cada regla de
--             limpieza que se aplicará en la fase de transformación.
-- Costo     : Bloque 1 = aprox. 4.5 GB (lee 13 de 20 columnas, no todas).
--             Bloques 2 y 3 = aprox. 0.6 GB cada uno.
-- Evidencias: evidencia_03_perfil.png (bloque 1),
--             evidencia_03_rate_code.png (bloque 2),
--             evidencia_03_payment_type.png (bloque 3).
-- Nota técnica: rate_code y payment_type son STRING con formato '1.0',
-- por lo que se usa doble cast SAFE_CAST(STRING -> FLOAT64 -> INT64).
-- Un cast directo a INT64 devolvería NULL y ocultaría el problema.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BLOQUE 1: perfil de calidad de una sola pasada.
-- Cada COUNTIF es una regla de limpieza candidata; el número resultante
-- indica cuántos registros afectaría. Capturar la cuadricula completa.
-- ----------------------------------------------------------------------------
SELECT
  COUNT(*)                                                    AS total_filas,
  -- Nulos en columnas críticas
  COUNTIF(pickup_datetime IS NULL)                            AS nulos_pickup,
  COUNTIF(dropoff_datetime IS NULL)                           AS nulos_dropoff,
  COUNTIF(trip_distance IS NULL)                              AS nulos_distancia,
  COUNTIF(fare_amount IS NULL)                                AS nulos_tarifa,
  COUNTIF(total_amount IS NULL)                               AS nulos_total,
  -- Inconsistencias temporales
  COUNTIF(dropoff_datetime <= pickup_datetime)                AS duracion_cero_o_negativa,
  COUNTIF(TIMESTAMP_DIFF(dropoff_datetime, pickup_datetime, MINUTE) > 240) AS viajes_mas_de_4_horas,
  -- Valores físicamente implausibles
  COUNTIF(trip_distance <= 0)                                 AS distancia_cero_o_negativa,
  COUNTIF(trip_distance > 100)                                AS distancia_mayor_100_mi,
  COUNTIF(passenger_count <= 0 OR passenger_count IS NULL)    AS pasajeros_invalidos,
  COUNTIF(passenger_count > 9)                                AS pasajeros_mayor_9,
  -- Inconsistencias económicas
  COUNTIF(fare_amount < 2.5)                                  AS tarifa_bajo_minimo_legal,
  COUNTIF(fare_amount > 500)                                  AS tarifa_mayor_500,
  COUNTIF(total_amount < 0)                                   AS total_negativo,
  COUNTIF(total_amount > 1000)                                AS total_mayor_1000,
  COUNTIF(tip_amount < 0)                                     AS propina_negativa,
  -- Códigos fuera de catálogo TLC (doble cast por STRING '1.0')
  COUNTIF(SAFE_CAST(SAFE_CAST(rate_code AS FLOAT64) AS INT64) IS NULL)          AS rate_code_ilegible,
  COUNTIF(SAFE_CAST(SAFE_CAST(rate_code AS FLOAT64) AS INT64) NOT BETWEEN 1 AND 6) AS rate_code_fuera_catalogo,
  COUNTIF(SAFE_CAST(SAFE_CAST(payment_type AS FLOAT64) AS INT64) IS NULL)       AS payment_type_ilegible,
  COUNTIF(SAFE_CAST(SAFE_CAST(payment_type AS FLOAT64) AS INT64) NOT BETWEEN 1 AND 6) AS payment_type_fuera_catalogo,
  -- Zonas de taxi
  COUNTIF(pickup_location_id IS NULL)                         AS nulos_zona_origen,
  COUNTIF(dropoff_location_id IS NULL)                        AS nulos_zona_destino,
  -- Porcentajes que determinan decisiones de modelado
  ROUND(100 * COUNTIF(SAFE_CAST(SAFE_CAST(payment_type AS FLOAT64) AS INT64) = 2) / COUNT(*), 2) AS pct_pago_efectivo,
  ROUND(100 * COUNTIF(SAFE_CAST(SAFE_CAST(rate_code AS FLOAT64) AS INT64) <> 1) / COUNT(*), 2)   AS pct_tarifa_no_estandar,
  ROUND(100 * COUNTIF(store_and_fwd_flag = 'Y') / COUNT(*), 2) AS pct_store_and_fwd
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`;

-- ----------------------------------------------------------------------------
-- BLOQUE 2: distribución del código de tarifa.
-- Hallazgo esperado: rate_code = 1 (tarifa por taxímetro) concentra la gran
-- mayoría; los códigos 2-5 son tarifas planas (aeropuerto, negociada, etc.)
-- cuya tarifa NO depende de la distancia. Decisión derivada: el modelo de
-- regresión de tarifa se entrena solo con rate_code = 1.
-- ----------------------------------------------------------------------------
SELECT
  COALESCE(rate_code, 'NULL')                          AS rate_code,
  COUNT(*)                                             AS viajes,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)     AS pct,
  ROUND(AVG(fare_amount), 2)                           AS tarifa_promedio,
  ROUND(AVG(trip_distance), 2)                         AS distancia_promedio
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`
GROUP BY 1
ORDER BY viajes DESC;

-- ----------------------------------------------------------------------------
-- BLOQUE 3: distribución del tipo de pago y comportamiento de propinas.
-- Hallazgo esperado: payment_type = 2 (efectivo) registra tip_amount = 0
-- sistemáticamente, porque la propina en efectivo no se captura en el
-- sistema TLC. Decisión derivada: el clasificador de propina alta se
-- entrena solo con payment_type = 1 (tarjeta); incluir efectivo crearía
-- una etiqueta degenerada que el modelo aprendería de forma trivial.
-- ----------------------------------------------------------------------------
SELECT
  COALESCE(payment_type, 'NULL')                       AS payment_type,
  COUNT(*)                                             AS viajes,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)     AS pct,
  ROUND(AVG(tip_amount), 3)                            AS propina_promedio,
  ROUND(100 * COUNTIF(tip_amount > 0) / COUNT(*), 2)   AS pct_con_propina
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`
GROUP BY 1
ORDER BY viajes DESC;

-- ----------------------------------------------------------------------------
-- INTERPRETACIÓN PARA EL README (con números obtenidos el 2026-10-20):
-- Regla L1: se excluyen viajes con dropoff <= pickup o duración fuera de
--           1-240 min: 74,761 registros (30,360 de duración no positiva +
--           44,401 de más de 4 horas).
-- Regla L2: se excluyen distancias <= 0 o > 100 mi: 512,826 registros
--           (511,442 + 1,384). Es el 1.41% de la tabla.
-- Regla L3: se excluyen pasajeros <= 0 o NULL: 1,344,959 registros (3.71%),
--           el defecto individual más frecuente del dataset.
-- Regla L4: se excluyen tarifas fuera de [2.5, 500] o totales fuera de
--           [2.5, 1000]: 476,836 registros (246,228 + 2,235 + 228,292 + 81).
-- Regla L5: se excluyen códigos fuera del catálogo TLC: 1,363,232 registros
--           (1,241,840 con rate_code NULL y payment_type = 0 simultáneamente,
--           que forman un bloque de captura incompleta con distancia promedio
--           de 78.58 mi; más 121,392 con rate_code = 99).
-- Regla L6: se excluyen propinas negativas (ajustes o anulaciones):
--           3,135 registros.
-- Nota metodológica: las reglas se solapan (un registro puede violar varias),
-- por lo que la suma de excluidos es mayor que el descarte final. La cifra
-- exacta de retención se reporta en 04_metricas.sql bloque 2a (pct_conservado).
-- Regla M1: el modelo de regresión se entrena solo con rate_code = 1
--           (91.3% de los viajes, tarifa de medidor, promedio 12.24 USD y
--           2.82 mi), porque las tarifas planas (código 2: 50.65 USD y
--           17.31 mi en promedio) no dependen del taxímetro.
-- Regla M2: el modelo de clasificación se entrena solo con payment_type = 1
--           (75.94% de los viajes, 96.03% con propina), porque en efectivo
--           (19.59% de los viajes) el sistema TLC no captura la propina:
--           pct_con_propina = 0.02% y propina promedio 0.001 USD. Incluir
--           efectivo crearía una etiqueta degenerada.
-- ----------------------------------------------------------------------------