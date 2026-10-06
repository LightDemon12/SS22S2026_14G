-- =============================================================================
-- SCRIPT DE VALIDACIÓN 04: CHEQUEOS DE CALIDAD Y CONSISTENCIA NUMÉRICA
-- =============================================================================

-- 1. Validar que no existan montos negativos o inconsistentes
SELECT count(*) AS lineas_monto_negativo
FROM analytics.fct_ventas
WHERE monto_bruto < 0 OR monto_neto < 0 OR monto_descuento < 0;

-- 2. Validar consistencia de cálculo: monto_bruto - monto_descuento = monto_neto
SELECT count(*) AS lineas_inconsistencia_calculo
FROM analytics.fct_ventas
WHERE ABS((monto_bruto - monto_descuento) - monto_neto) > 0.05;

-- 3. Validar unicidad de llaves primarias en dimensiones
SELECT 'dim_clientes' AS dimension, count(*) - count(DISTINCT id_cliente) AS duplicados_pk FROM analytics.dim_clientes
UNION ALL
SELECT 'dim_productos', count(*) - count(DISTINCT id_producto) FROM analytics.dim_productos
UNION ALL
SELECT 'dim_sucursales', count(*) - count(DISTINCT id_sucursal) FROM analytics.dim_sucursales
UNION ALL
SELECT 'fct_ventas', count(*) - count(DISTINCT id_detalle) FROM analytics.fct_ventas;
