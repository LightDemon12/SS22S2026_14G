-- =============================================================================
-- SCRIPT DE VALIDACIÓN 02: ESTRUCTURA DEL MODELO DIMENSIONAL (ANALYTICS)
-- =============================================================================

-- 1. Verificación de conteos en Dimensiones y Hechos
SELECT 'analytics.dim_clientes' AS tabla, count(*) AS total_filas FROM analytics.dim_clientes
UNION ALL
SELECT 'analytics.dim_productos', count(*) FROM analytics.dim_productos
UNION ALL
SELECT 'analytics.dim_sucursales', count(*) FROM analytics.dim_sucursales
UNION ALL
SELECT 'analytics.fct_ventas', count(*) FROM analytics.fct_ventas;

-- 2. Verificación de integridad referencial (huérfanos en la tabla de hechos)
-- Clientes huérfanos
SELECT count(*) AS huerfanos_clientes
FROM analytics.fct_ventas f
LEFT JOIN analytics.dim_clientes c ON f.id_cliente = c.id_cliente
WHERE c.id_cliente IS NULL;

-- Productos huérfanos
SELECT count(*) AS huerfanos_productos
FROM analytics.fct_ventas f
LEFT JOIN analytics.dim_productos p ON f.id_producto = p.id_producto
WHERE p.id_producto IS NULL;

-- Sucursales huérfanas
SELECT count(*) AS huerfanas_sucursales
FROM analytics.fct_ventas f
LEFT JOIN analytics.dim_sucursales s ON f.id_sucursal = s.id_sucursal
WHERE s.id_sucursal IS NULL;
