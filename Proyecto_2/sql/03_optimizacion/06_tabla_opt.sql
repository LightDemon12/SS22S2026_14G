-- ============================================================================
-- PROYECTO 2 - SEMINARIO DE SISTEMAS 2 - 2S2026 - PAREJA 14
-- Archivo   : sql/03_optimizacion/06_tabla_opt.sql
-- Objetivo  : Crear la versión OPTIMIZADA de la tabla de hechos con
--             partición por fecha y clustering por ubicaciones, cargarla y
--             certificar que ambas técnicas quedaron aplicadas físicamente
--             (estado "DESPUÉS" del benchmark).
-- ----------------------------------------------------------------------------
-- MODO DE EJECUCIÓN (DOS PASADAS):
--   PASADA 1 (DE CORRIDO): ejecutar el archivo completo como un solo script.
--     Construye y carga la tabla de principio a fin. Es idempotente: el DROP
--     del bloque 1a garantiza que re-ejecutar el archivo nunca duplica filas.
--   PASADA 2 (BLOQUE POR BLOQUE, SOLO LECTURA): re-ejecutar individualmente
--     los bloques 1c, 2, 3, 4, 5 y 6 para tomar las capturas de evidencia con
--     el editor y los bytes estimados visibles en pantalla.
--     PROHIBIDO re-ejecutar 1a, 1b o 1d en la pasada 2: 1a/1b borrarían la
--     carga y 1d duplicaría los 33,377,653 registros. La captura del bloque
--     1d se toma de la PASADA 1 (mensaje del job o Job history).
-- ----------------------------------------------------------------------------
-- INCIDENTE DOCUMENTADO (llevar al README, sección lecciones aprendidas):
--   CAUSA RAÍZ: el dataset heredaba partition_expiration_days = 60. Como las
--   particiones se fechan con pickup_date (año 2022, más de 3 años antes de
--   la fecha actual), BigQuery purgaba TODAS las particiones en el instante
--   mismo en que un INSERT o un CREATE AS SELECT terminaba de escribirlas.
--   Síntomas que esto explicaba: INSERT que reportaba 33,377,653 filas
--   seguidos de COUNT(*) = 0; CREATE TABLE AS SELECT que "cargaba 0 filas";
--   vista INFORMATION_SCHEMA.PARTITIONS con 0 filas o 1 fila NULL.
--   La tabla fact_trips_std nunca perdió datos porque NO está particionada
--   (su expiración es a nivel de tabla y no depende de la fecha del dato).
--   CORRECCIÓN DEFINITIVA: partition_expiration_days = NULL en el bloque 1b.
-- ----------------------------------------------------------------------------
-- Costo     : 1a, 1b, 1c y 2 = 0 B. 1d = lee fact_trips_std completa
--             (aprox. 4.2 GB). 3 = pocos MB. 4, 5 y 6 = ~10 MB cada uno.
-- Prerrequisito: fact_trips_std existente con 33,377,653 filas
--             (verificado con 05_tabla_std.sql bloque 3 antes de correr).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- BLOQUE 1a: ELIMINACIÓN PREVENTIVA DE CUALQUIER TABLA PREVIA.
-- Garantiza que el CREATE del bloque 1b defina la disposición física desde
-- cero (sin heredar esquemas previos) y hace idempotente todo el archivo.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_opt`;

-- ----------------------------------------------------------------------------
-- BLOQUE 1b: ESQUEMA PARTICIONADO Y CLUSTERIZADO (SIN DATOS).
--
-- Nota de sintaxis: se usa CREATE TABLE (sin OR REPLACE) porque el DROP
-- previo garantiza que la tabla no existe; es la formulación exacta que en
-- este entorno produjo is_partitioning_column = YES. La carga de datos NO
-- vive en este CREATE (ver bloque 1d).
--
-- DECISIONES DE DISEÑO (justificación exigida por rúbrica 1.3 y 2.5):
-- 1) PARTITION BY pickup_date (granularidad DIARIA):
--    - El 100% de las consultas analíticas del proyecto filtra por rango
--      temporal (benchmarks, agregados diarios, forecast, split de ML).
--    - 335 particiones (días con datos en 2022; la ventana real del dataset
--      termina el 2022-12-01), muy por debajo del límite de 4000 por tabla.
--    - Se elige DÍA y no MES porque las consultas típicas piden "una semana"
--      o "un mes": con partición diaria el podado es exacto; con partición
--      mensual una consulta de 7 días leería 2 meses completos.
--    - Se particiona sobre la columna DATE materializada (pickup_date) y no
--      sobre DATE(pickup_datetime) para que el filtro en WHERE sea trivial
--      y visible para cualquier persona que consulte la tabla.
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
-- 3) Los datos provienen de fact_trips_std (bloque 1d), garantizando que el
--    benchmark compare DOS DISPOSICIONES FÍSICAS DEL MISMO CONJUNTO DE DATOS,
--    no conjuntos distintos. Esa es la validez experimental de la comparación.
-- 4) partition_expiration_days = NULL desactiva el vencimiento por fecha de
--    partición que purgaba los datos históricos (ver incidente arriba).
--    Si el editor rechazara NULL, usar partition_expiration_days = 36500
--    (100 años): mismo efecto práctico para la línea de tiempo del curso.
--
-- EVIDENCIA: evidencia_06_esquema_creado.png (mensaje "created a new table").
-- ----------------------------------------------------------------------------
CREATE TABLE `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_opt`
PARTITION BY pickup_date
CLUSTER BY pickup_location_id, dropoff_location_id
OPTIONS(
  description = 'Tabla optimizada: particion diaria por pickup_date y clustering por zona origen/destino',
  partition_expiration_days = 36500
)
AS
SELECT *
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_std`
WHERE FALSE;

-- ----------------------------------------------------------------------------
-- BLOQUE 1c: VERIFICACIÓN DEL ESQUEMA ANTES DE CARGAR (0 bytes).
-- Resultado esperado: UNA fila con is_partitioning_column = 'YES'.
-- Si dijera 'NO': DETENERSE, no ejecutar 1d y reportar el incidente.
-- EVIDENCIA (pasada 2): evidencia_06_esquema_particion.png
-- ----------------------------------------------------------------------------
SELECT column_name, is_partitioning_column
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'fact_trips_opt'
  AND column_name = 'pickup_date';

-- ----------------------------------------------------------------------------
-- BLOQUE 1d: CARGA DE DATOS (único método de carga verificado en este
-- entorno). Con la expiración desactivada, las particiones de 2022 YA NO son
-- purgadas después de la escritura.
-- Mensaje esperado: "This statement added 33,377,653 rows to fact_trips_opt".
-- EVIDENCIA: capturar este mensaje EN LA PASADA 1 como
--            evidencia_06_carga_insert.png. NO re-ejecutar después.
-- ----------------------------------------------------------------------------
INSERT INTO `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_opt`
SELECT *
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_std`;

-- ----------------------------------------------------------------------------
-- REGLA DE ORO A PARTIR DE ESTE PUNTO: sobre fact_trips_opt ya no se ejecuta
-- ningún DDL (ni CREATE, ni OR REPLACE, ni DROP) hasta terminar el proyecto.
-- De aquí en adelante, solo lecturas: bloques 2 a 6, benchmark 07, vistas de
-- features y modelos de BigQuery ML.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- BLOQUE 2: INTEGRIDAD DE LA CARGA (0 bytes).
-- Resultado esperado: 33,377,653 Y QUE SE MANTENGA ASÍ (con la expiración
-- corregida, el conteo ya no debe caer a 0 segundos después).
-- EVIDENCIA (pasada 2): evidencia_06_conteo.png
-- ----------------------------------------------------------------------------
SELECT COUNT(*) AS filas_opt
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_opt`;

-- ----------------------------------------------------------------------------
-- BLOQUE 3: PRUEBA FUNCIONAL DE PODADO DE PARTICIONES (pocos MB).
-- Es la evidencia más sólida de que el particionamiento funciona: no depende
-- de ninguna vista de metadatos, solo de bytes reales procesados.
-- Resultado esperado: revenue del orden de 1 a 2 millones de USD (un día de
-- operación), NO null.
-- Procedimiento de captura: ejecutar sobre opt y anotar los bytes del job
-- (orden de 1-20 MB); luego cambiar únicamente la tabla a fact_trips_std y,
-- SIN EJECUTAR, leer la estimación bajo el editor (orden de 100-200 MB).
-- EVIDENCIA (pasada 2): evidencia_06_podado_opt.png (ambas cifras visibles).
-- ----------------------------------------------------------------------------
SELECT ROUND(SUM(fare_amount), 2) AS revenue_dia
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.fact_trips_opt`
WHERE pickup_date = DATE '2022-07-15';

-- ----------------------------------------------------------------------------
-- BLOQUE 4: OPCIONES FÍSICAS DE AMBAS TABLAS, LADO A LADO (~10 MB).
-- Lectura esperada tras la corrección: en fact_trips_opt la opción
-- partition_expiration_days ya NO debe aparecer con valor 60.0 (desaparece o
-- se ve NULL); esa diferencia contra la captura anterior es la prueba
-- documental de que el incidente quedó corregido. En fact_trips_std deben
-- verse description y expiration_timestamp (expiración a nivel de tabla,
-- inofensiva porque no depende de la fecha del dato).
-- EVIDENCIA (pasada 2): evidencia_06_opciones.png
-- ----------------------------------------------------------------------------
SELECT
  table_name,
  option_name,
  option_value
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.INFORMATION_SCHEMA.TABLE_OPTIONS`
WHERE table_name IN ('fact_trips_std', 'fact_trips_opt')
ORDER BY table_name, option_name;

-- ----------------------------------------------------------------------------
-- BLOQUE 5: TAMAÑO DE AMBAS COPIAS (~10 MB, 0 B según optimización de motor).
-- Deben ser casi idénticos (mismos datos, distinta disposición física):
-- aprox. 4.2 GB cada una. Si opt pesara mucho menos, algo se filtró en la
-- carga y habría que repetir la pasada 1 completa.
-- EVIDENCIA (pasada 2): evidencia_06_tamanos.png
-- ----------------------------------------------------------------------------
SELECT
  table_id,
  row_count                           AS filas,
  ROUND(size_bytes / POW(1024, 3), 2) AS gb_logicos
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.__TABLES__`
WHERE table_id IN ('fact_trips_std', 'fact_trips_opt')
ORDER BY table_id;

-- ----------------------------------------------------------------------------
-- BLOQUE 6: VERIFICACIÓN DE PARTICIONES (~10 MB). Se coloca AL FINAL del
-- archivo a propósito: al ejecutarse varios minutos después del INSERT, da
-- tiempo a que el metadato se propague por completo.
-- Resultado esperado: ~335 particiones, primera 20220101, última 20221201,
-- contra 1 partición NULL de la tabla estándar (05_tabla_std.sql bloque 1).
-- Si mostrara un valor inconsistente, re-ejecutar SOLO este bloque unos
-- minutos después; los criterios de aceptación primarios siguen siendo los
-- bloques 1c, 2, 3 y la pestaña Details.
-- EVIDENCIA (pasada 2): evidencia_06_particiones.png
-- ----------------------------------------------------------------------------
SELECT
  COUNT(*)            AS n_particiones,
  MIN(partition_id)   AS primera_particion,
  MAX(partition_id)   AS ultima_particion
FROM `ss2-2026-pareja14-v2.taxi_ss2_2026.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name = 'fact_trips_opt';

-- ----------------------------------------------------------------------------
-- BLOQUE UI (sin SQL): abrir fact_trips_opt en el Explorer de la consola y
-- capturar la pestaña Details, donde debe leerse
--   "Partitioned by: pickup_date"
--   "Clustered by: pickup_location_id, dropoff_location_id"
-- EVIDENCIA: evidencia_06_details_clustering.png
-- Esta captura es la prueba oficial de clustering para la rúbrica 1.3,
-- independiente de cualquier vista de metadatos.
-- ----------------------------------------------------------------------------