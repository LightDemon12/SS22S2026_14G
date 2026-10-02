

CREATE SCHEMA IF NOT EXISTS raw;


-- 1. TABLAS COPIA EXACTA DE LA FUENTE TRANSACCIONAL (OLTP_SGFOOD)


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


-- 2. TABLAS PARA FUENTES EXTERNAS (ARCHIVOS CSV)


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
