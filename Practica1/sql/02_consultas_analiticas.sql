/* =====================================================================
   Practica 1 - Seminario de Sistemas 2
   Consultas analiticas sobre el modelo dimensional DW_Vuelos
   Motor: Microsoft SQL Server (T-SQL)

   Estas consultas validan la correcta carga del ETL y generan
   indicadores de negocio solicitados en el enunciado (numero de vuelos,
   destinos mas frecuentes, distribucion por genero, etc.)
   ===================================================================== */

-- =====================================================================
-- 1. Validacion de carga: conteo de filas por tabla
-- =====================================================================
SELECT 'dim_fecha'        AS tabla, COUNT(*) AS filas FROM dbo.dim_fecha
UNION ALL SELECT 'dim_aerolinea',    COUNT(*) FROM dbo.dim_aerolinea
UNION ALL SELECT 'dim_aeropuerto',   COUNT(*) FROM dbo.dim_aeropuerto
UNION ALL SELECT 'dim_aeronave',     COUNT(*) FROM dbo.dim_aeronave
UNION ALL SELECT 'dim_clase_cabina', COUNT(*) FROM dbo.dim_clase_cabina
UNION ALL SELECT 'dim_canal_venta',  COUNT(*) FROM dbo.dim_canal_venta
UNION ALL SELECT 'dim_metodo_pago',  COUNT(*) FROM dbo.dim_metodo_pago
UNION ALL SELECT 'dim_estado_vuelo', COUNT(*) FROM dbo.dim_estado_vuelo
UNION ALL SELECT 'dim_pasajero',     COUNT(*) FROM dbo.dim_pasajero
UNION ALL SELECT 'fact_vuelos',      COUNT(*) FROM dbo.fact_vuelos;
GO

-- =====================================================================
-- 2. Numero total de vuelos por estado (ON_TIME / DELAYED / CANCELLED / DIVERTED)
-- =====================================================================
SELECT ev.status, COUNT(*) AS total_vuelos
FROM dbo.fact_vuelos f
JOIN dbo.dim_estado_vuelo ev ON ev.estado_key = f.estado_key
GROUP BY ev.status
ORDER BY total_vuelos DESC;
GO

-- =====================================================================
-- 3. Top 5 destinos mas frecuentes
-- =====================================================================
SELECT TOP 5 ap.codigo_iata AS destino, COUNT(*) AS total_vuelos
FROM dbo.fact_vuelos f
JOIN dbo.dim_aeropuerto ap ON ap.aeropuerto_key = f.destino_key
GROUP BY ap.codigo_iata
ORDER BY total_vuelos DESC;
GO

-- =====================================================================
-- 4. Top 5 rutas (origen -> destino) mas frecuentes
-- =====================================================================
SELECT TOP 5
       origen.codigo_iata  AS origen,
       destino.codigo_iata AS destino,
       COUNT(*)            AS total_vuelos
FROM dbo.fact_vuelos f
JOIN dbo.dim_aeropuerto origen  ON origen.aeropuerto_key  = f.origen_key
JOIN dbo.dim_aeropuerto destino ON destino.aeropuerto_key = f.destino_key
GROUP BY origen.codigo_iata, destino.codigo_iata
ORDER BY total_vuelos DESC;
GO

-- =====================================================================
-- 5. Distribucion de pasajeros por genero
-- =====================================================================
SELECT p.genero, COUNT(*) AS total_pasajeros,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS porcentaje
FROM dbo.fact_vuelos f
JOIN dbo.dim_pasajero p ON p.pasajero_key = f.pasajero_key
GROUP BY p.genero
ORDER BY total_pasajeros DESC;
GO

-- =====================================================================
-- 6. Aerolinea con mayor cantidad de vuelos retrasados (DELAYED)
-- =====================================================================
SELECT TOP 5 al.airline_name, COUNT(*) AS vuelos_retrasados,
       AVG(CAST(f.delay_min AS FLOAT)) AS retraso_promedio_min
FROM dbo.fact_vuelos f
JOIN dbo.dim_aerolinea al   ON al.aerolinea_key = f.aerolinea_key
JOIN dbo.dim_estado_vuelo ev ON ev.estado_key = f.estado_key
WHERE ev.status = 'DELAYED'
GROUP BY al.airline_name
ORDER BY vuelos_retrasados DESC;
GO

-- =====================================================================
-- 7. Ingreso total (USD) y ticket promedio por clase de cabina
-- =====================================================================
SELECT cc.cabin_class,
       COUNT(*)                              AS total_boletos,
       CAST(SUM(f.ticket_price_usd) AS DECIMAL(12,2)) AS ingreso_total_usd,
       CAST(AVG(f.ticket_price_usd) AS DECIMAL(10,2))  AS ticket_promedio_usd
FROM dbo.fact_vuelos f
JOIN dbo.dim_clase_cabina cc ON cc.clase_key = f.clase_key
GROUP BY cc.cabin_class
ORDER BY ingreso_total_usd DESC;
GO

-- =====================================================================
-- 8. Vuelos y ticket promedio por mes (usando dim_fecha)
-- =====================================================================
SELECT df.anio, df.mes, df.nombre_mes,
       COUNT(*) AS total_vuelos,
       CAST(AVG(f.ticket_price_usd) AS DECIMAL(10,2)) AS ticket_promedio_usd
FROM dbo.fact_vuelos f
JOIN dbo.dim_fecha df ON df.fecha_key = f.fecha_salida_key
GROUP BY df.anio, df.mes, df.nombre_mes
ORDER BY df.anio, df.mes;
GO

-- =====================================================================
-- 9. Canal de venta preferido por metodo de pago (tabla cruzada)
-- =====================================================================
SELECT cv.sales_channel, mp.payment_method, COUNT(*) AS total
FROM dbo.fact_vuelos f
JOIN dbo.dim_canal_venta cv  ON cv.canal_key = f.canal_key
JOIN dbo.dim_metodo_pago mp  ON mp.metodo_pago_key = f.metodo_pago_key
GROUP BY cv.sales_channel, mp.payment_method
ORDER BY cv.sales_channel, total DESC;
GO

-- =====================================================================
-- 10. Nacionalidades de pasajeros mas frecuentes (Top 10)
-- =====================================================================
SELECT TOP 10 p.nacionalidad, COUNT(*) AS total_pasajeros
FROM dbo.fact_vuelos f
JOIN dbo.dim_pasajero p ON p.pasajero_key = f.pasajero_key
GROUP BY p.nacionalidad
ORDER BY total_pasajeros DESC;
GO

-- =====================================================================
-- 11. Verificacion de la dimension SCD Tipo 2 (dim_pasajero):
--     pasajeros con mas de una version historica
-- =====================================================================
SELECT passenger_id, COUNT(*) AS versiones_historicas
FROM dbo.dim_pasajero
GROUP BY passenger_id
HAVING COUNT(*) > 1
ORDER BY versiones_historicas DESC;
GO

-- =====================================================================
-- 12. Equipaje promedio (maletas totales y facturadas) por aerolinea
-- =====================================================================
SELECT al.airline_name,
       CAST(AVG(CAST(f.bags_total AS FLOAT)) AS DECIMAL(5,2))   AS maletas_promedio,
       CAST(AVG(CAST(f.bags_checked AS FLOAT)) AS DECIMAL(5,2)) AS maletas_facturadas_promedio
FROM dbo.fact_vuelos f
JOIN dbo.dim_aerolinea al ON al.aerolinea_key = f.aerolinea_key
GROUP BY al.airline_name
ORDER BY maletas_promedio DESC;
GO
