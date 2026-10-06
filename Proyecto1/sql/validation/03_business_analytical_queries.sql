-- =============================================================================
-- SCRIPT DE VALIDACIÓN 03: CONSULTAS ANALÍTICAS DE NEGOCIO (BI)
-- =============================================================================

-- Consulta 1: Ventas totales, descuentos y venta neta por Categoría de Producto
SELECT 
    p.categoria,
    COUNT(f.id_detalle) AS total_lineas_vendidas,
    SUM(f.cantidad) AS unidades_vendidas,
    SUM(f.monto_bruto) AS total_venta_bruta,
    SUM(f.monto_descuento) AS total_descuentos,
    SUM(f.monto_neto) AS total_venta_neta,
    ROUND(AVG(f.porcentaje_descuento) * 100, 2) AS pct_descuento_promedio
FROM analytics.fct_ventas f
JOIN analytics.dim_productos p ON f.id_producto = p.id_producto
GROUP BY p.categoria
ORDER BY total_venta_neta DESC;

-- Consulta 2: Rendimiento de Ventas por Sucursal y Departamento
SELECT 
    s.nombre_sucursal,
    s.departamento,
    COUNT(DISTINCT f.id_venta) AS total_transacciones,
    SUM(f.monto_neto) AS facturacion_total_neta,
    ROUND(AVG(f.monto_neto), 2) AS ticket_promedio_linea
FROM analytics.fct_ventas f
JOIN analytics.dim_sucursales s ON f.id_sucursal = s.id_sucursal
GROUP BY s.nombre_sucursal, s.departamento
ORDER BY facturacion_total_neta DESC;

-- Consulta 3: Top 10 Clientes con Mayor Volumen de Compra
SELECT 
    c.id_cliente,
    c.nombre_cliente,
    c.tipo_cliente,
    c.municipio,
    COUNT(DISTINCT f.id_venta) AS total_ordenes,
    SUM(f.monto_neto) AS gasto_acumulado_neto
FROM analytics.fct_ventas f
JOIN analytics.dim_clientes c ON f.id_cliente = c.id_cliente
GROUP BY c.id_cliente, c.nombre_cliente, c.tipo_cliente, c.municipio
ORDER BY gasto_acumulado_neto DESC
LIMIT 10;
