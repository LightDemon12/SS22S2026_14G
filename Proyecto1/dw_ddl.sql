-- =============================================================================
-- PROYECTO 1 - DATA WAREHOUSE & ELT (SG-FOOD)
-- SCRIPT DDL COMPLETO DEL DATA WAREHOUSE
-- Incluye: Creación de Schemas, Capa RAW, Capa ANALYTICS (Dimensiones y Hechos),
-- Llaves Primarias, Llaves Foráneas e Índices de Rendimiento.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. CREACIÓN DE ESQUEMAS DEL DATA WAREHOUSE
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS intermediate;
CREATE SCHEMA IF NOT EXISTS analytics;

-- -----------------------------------------------------------------------------
-- 2. CAPA RAW (TABLAS FUENTE OPERACIONALES Y EXTERNAS)
-- -----------------------------------------------------------------------------

-- 2.1 Tablas Replicadas del Sistema Transaccional (OLTP)
DROP TABLE IF EXISTS raw.sucursal CASCADE;
CREATE TABLE raw.sucursal (
    id_sucursal INTEGER,
    nombre VARCHAR(100),
    ciudad VARCHAR(100),
    departamento VARCHAR(100),
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS raw.categoria CASCADE;
CREATE TABLE raw.categoria (
    id_categoria INTEGER,
    nombre VARCHAR(100),
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS raw.marca CASCADE;
CREATE TABLE raw.marca (
    id_marca INTEGER,
    nombre VARCHAR(100),
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS raw.producto CASCADE;
CREATE TABLE raw.producto (
    id_producto INTEGER,
    sku VARCHAR(20),
    nombre VARCHAR(150),
    id_categoria INTEGER,
    id_marca INTEGER,
    unidad_medida VARCHAR(30),
    costo_base NUMERIC(12, 2),
    precio_lista NUMERIC(12, 2),
    activo BOOLEAN,
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS raw.cliente CASCADE;
CREATE TABLE raw.cliente (
    id_cliente INTEGER,
    nit VARCHAR(20),
    nombre VARCHAR(150),
    tipo_cliente VARCHAR(40),
    municipio VARCHAR(100),
    departamento VARCHAR(100),
    fecha_alta DATE,
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS raw.venta CASCADE;
CREATE TABLE raw.venta (
    id_venta BIGINT,
    fecha DATE,
    id_cliente INTEGER,
    id_sucursal INTEGER,
    canal VARCHAR(30),
    metodo_pago VARCHAR(30),
    estado VARCHAR(20),
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS raw.venta_detalle CASCADE;
CREATE TABLE raw.venta_detalle (
    id_detalle BIGINT,
    id_venta BIGINT,
    id_producto INTEGER,
    cantidad INTEGER,
    precio_unitario NUMERIC(12, 2),
    descuento NUMERIC(5, 4),
    subtotal NUMERIC(14, 2),
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2.2 Tablas para Fuentes Externas (Archivos CSV)
DROP TABLE IF EXISTS raw.inventario_bodega CASCADE;
CREATE TABLE raw.inventario_bodega (
    fecha_corte DATE,
    id_sucursal INTEGER,
    id_producto INTEGER,
    stock_disponible INTEGER,
    stock_minimo INTEGER,
    stock_maximo INTEGER,
    lote VARCHAR(50),
    fecha_vencimiento DATE,
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS raw.proveedores_precios CASCADE;
CREATE TABLE raw.proveedores_precios (
    id_proveedor INTEGER,
    proveedor VARCHAR(150),
    id_producto INTEGER,
    costo_proveedor NUMERIC(12, 2),
    plazo_dias INTEGER,
    fecha_vigencia DATE,
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS raw.promociones CASCADE;
CREATE TABLE raw.promociones (
    id_promocion INTEGER,
    nombre VARCHAR(150),
    fecha_inicio DATE,
    fecha_fin DATE,
    id_categoria INTEGER,
    porcentaje_descuento NUMERIC(5, 4),
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS raw.metas_ventas CASCADE;
CREATE TABLE raw.metas_ventas (
    periodo VARCHAR(10),
    id_sucursal INTEGER,
    meta_ventas NUMERIC(14, 2),
    meta_unidades INTEGER,
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS raw.devoluciones CASCADE;
CREATE TABLE raw.devoluciones (
    id_devolucion INTEGER,
    fecha DATE,
    id_venta BIGINT,
    id_producto INTEGER,
    cantidad INTEGER,
    motivo VARCHAR(150),
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS raw.casos_calidad_opcionales CASCADE;
CREATE TABLE raw.casos_calidad_opcionales (
    entidad VARCHAR(100),
    campo VARCHAR(100),
    valor_prueba VARCHAR(100),
    tipo_incidencia VARCHAR(200),
    _extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- 3. CAPA ANALYTICS (MODELO DIMENSIONAL DE ESTRELLA)
-- -----------------------------------------------------------------------------

-- 3.1 Dimensión Clientes
DROP TABLE IF EXISTS analytics.dim_clientes CASCADE;
CREATE TABLE analytics.dim_clientes (
    id_cliente INTEGER PRIMARY KEY,
    nit VARCHAR(20),
    nombre_cliente VARCHAR(150) NOT NULL,
    tipo_cliente VARCHAR(40),
    municipio VARCHAR(100),
    departamento VARCHAR(100),
    fecha_alta DATE NOT NULL
);

-- 3.2 Dimensión Productos (Desnormalizada con Categoría y Marca)
DROP TABLE IF EXISTS analytics.dim_productos CASCADE;
CREATE TABLE analytics.dim_productos (
    id_producto INTEGER PRIMARY KEY,
    sku VARCHAR(20) NOT NULL UNIQUE,
    nombre_producto VARCHAR(150) NOT NULL,
    id_categoria INTEGER,
    categoria VARCHAR(100) NOT NULL,
    id_marca INTEGER,
    marca VARCHAR(100) NOT NULL,
    unidad_medida VARCHAR(30),
    costo_base NUMERIC(12, 2) NOT NULL,
    precio_lista NUMERIC(12, 2) NOT NULL,
    margen_unitario_teorico NUMERIC(12, 2),
    es_activo BOOLEAN NOT NULL DEFAULT TRUE
);

-- 3.3 Dimensión Sucursales
DROP TABLE IF EXISTS analytics.dim_sucursales CASCADE;
CREATE TABLE analytics.dim_sucursales (
    id_sucursal INTEGER PRIMARY KEY,
    nombre_sucursal VARCHAR(100) NOT NULL,
    ciudad VARCHAR(100) NOT NULL,
    departamento VARCHAR(100) NOT NULL
);

-- 3.4 Tabla de Hechos: Ventas (Grain: Línea de detalle de venta)
DROP TABLE IF EXISTS analytics.fct_ventas CASCADE;
CREATE TABLE analytics.fct_ventas (
    id_detalle BIGINT PRIMARY KEY,
    id_venta BIGINT NOT NULL,
    id_cliente INTEGER NOT NULL REFERENCES analytics.dim_clientes(id_cliente),
    id_producto INTEGER NOT NULL REFERENCES analytics.dim_productos(id_producto),
    id_sucursal INTEGER NOT NULL REFERENCES analytics.dim_sucursales(id_sucursal),
    fecha_venta DATE NOT NULL,
    canal_venta VARCHAR(30),
    metodo_pago VARCHAR(30),
    estado_venta VARCHAR(20),
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(12, 2) NOT NULL,
    porcentaje_descuento NUMERIC(5, 4) NOT NULL DEFAULT 0,
    monto_bruto NUMERIC(14, 2) NOT NULL,
    monto_descuento NUMERIC(14, 2) NOT NULL DEFAULT 0,
    monto_neto NUMERIC(14, 2) NOT NULL
);

-- -----------------------------------------------------------------------------
-- 4. ÍNDICES ANALÍTICOS DE RENDIMIENTO
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_fct_ventas_fecha ON analytics.fct_ventas(fecha_venta);
CREATE INDEX IF NOT EXISTS idx_fct_ventas_cliente ON analytics.fct_ventas(id_cliente);
CREATE INDEX IF NOT EXISTS idx_fct_ventas_producto ON analytics.fct_ventas(id_producto);
CREATE INDEX IF NOT EXISTS idx_fct_ventas_sucursal ON analytics.fct_ventas(id_sucursal);
