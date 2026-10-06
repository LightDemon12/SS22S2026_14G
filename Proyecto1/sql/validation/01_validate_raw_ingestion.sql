-- =============================================================================
-- SCRIPT DE VALIDACIÓN 01: CONTEO Y VERIFICACIÓN DE LA CAPA RAW
-- =============================================================================

-- 1. Verificación de fuentes transaccionales replicadas
SELECT 'raw.sucursal' AS tabla, count(*) AS total_registros, max(_extracted_at) AS ultima_extraccion FROM raw.sucursal
UNION ALL
SELECT 'raw.categoria', count(*), max(_extracted_at) FROM raw.categoria
UNION ALL
SELECT 'raw.marca', count(*), max(_extracted_at) FROM raw.marca
UNION ALL
SELECT 'raw.producto', count(*), max(_extracted_at) FROM raw.producto
UNION ALL
SELECT 'raw.cliente', count(*), max(_extracted_at) FROM raw.cliente
UNION ALL
SELECT 'raw.venta', count(*), max(_extracted_at) FROM raw.venta
UNION ALL
SELECT 'raw.venta_detalle', count(*), max(_extracted_at) FROM raw.venta_detalle

-- 2. Verificación de fuentes externas (CSV)
UNION ALL
SELECT 'raw.inventario_bodega', count(*), max(_extracted_at) FROM raw.inventario_bodega
UNION ALL
SELECT 'raw.proveedores_precios', count(*), max(_extracted_at) FROM raw.proveedores_precios
UNION ALL
SELECT 'raw.promociones', count(*), max(_extracted_at) FROM raw.promociones
UNION ALL
SELECT 'raw.metas_ventas', count(*), max(_extracted_at) FROM raw.metas_ventas
UNION ALL
SELECT 'raw.devoluciones', count(*), max(_extracted_at) FROM raw.devoluciones
ORDER BY tabla;
