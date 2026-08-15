/* =====================================================================
   Practica 1 - Seminario de Sistemas 2
   ETL con Python: de dataset crudo a tabla relacional lista para analisis

   Script de creacion del modelo multidimensional (esquema estrella)
   Motor destino: Microsoft SQL Server 2019+

   Convenciones:
     - Claves subrogadas (surrogate keys) IDENTITY en todas las dimensiones
     - dim_aeropuerto es una dimension de ROL: se referencia dos veces desde
       el hecho (aeropuerto de origen y aeropuerto de destino)
     - dim_pasajero es una dimension de tipo 2 (Slowly Changing Dimension
       Type 2): conserva el historial de cambios en genero/edad/nacionalidad
       de un mismo pasajero (passenger_id) mediante fecha_inicio_validez,
       fecha_fin_validez y es_actual. Si en una carga futura el mismo
       passenger_id llega con un atributo distinto, el ETL cierra la version
       vigente (fecha_fin_validez = fecha de carga, es_actual = 0) e inserta
       una nueva fila con es_actual = 1.
   ===================================================================== */

IF DB_ID('DW_Vuelos') IS NULL
BEGIN
    PRINT 'Este script asume que ya existe / fue creada la base de datos DW_Vuelos.';
END
GO

-- USE DW_Vuelos;
-- GO

/* =====================================================================
   1. LIMPIEZA DE OBJETOS EXISTENTES (ejecucion idempotente)
   ===================================================================== */
IF OBJECT_ID('dbo.fact_vuelos', 'U')       IS NOT NULL DROP TABLE dbo.fact_vuelos;
IF OBJECT_ID('dbo.dim_pasajero', 'U')      IS NOT NULL DROP TABLE dbo.dim_pasajero;
IF OBJECT_ID('dbo.dim_fecha', 'U')         IS NOT NULL DROP TABLE dbo.dim_fecha;
IF OBJECT_ID('dbo.dim_aerolinea', 'U')     IS NOT NULL DROP TABLE dbo.dim_aerolinea;
IF OBJECT_ID('dbo.dim_aeropuerto', 'U')    IS NOT NULL DROP TABLE dbo.dim_aeropuerto;
IF OBJECT_ID('dbo.dim_aeronave', 'U')      IS NOT NULL DROP TABLE dbo.dim_aeronave;
IF OBJECT_ID('dbo.dim_clase_cabina', 'U')  IS NOT NULL DROP TABLE dbo.dim_clase_cabina;
IF OBJECT_ID('dbo.dim_canal_venta', 'U')   IS NOT NULL DROP TABLE dbo.dim_canal_venta;
IF OBJECT_ID('dbo.dim_metodo_pago', 'U')   IS NOT NULL DROP TABLE dbo.dim_metodo_pago;
IF OBJECT_ID('dbo.dim_estado_vuelo', 'U')  IS NOT NULL DROP TABLE dbo.dim_estado_vuelo;
GO

/* =====================================================================
   2. DIMENSIONES
   ===================================================================== */

-- 2.1 Dimension Fecha (grano: dia). Se referencia desde fact_vuelos
--     como fecha de salida del vuelo.
CREATE TABLE dbo.dim_fecha (
    fecha_key        INT           NOT NULL PRIMARY KEY,        -- formato YYYYMMDD
    fecha            DATE          NOT NULL,
    anio             SMALLINT      NOT NULL,
    mes              TINYINT       NOT NULL,
    nombre_mes       NVARCHAR(20)  NOT NULL,
    trimestre        TINYINT       NOT NULL,
    dia              TINYINT       NOT NULL,
    dia_semana        TINYINT      NOT NULL,                     -- 1=Lunes ... 7=Domingo
    nombre_dia_semana NVARCHAR(20) NOT NULL,
    es_fin_semana     BIT          NOT NULL
);
GO

-- 2.2 Dimension Aerolinea (nombres homologados a partir de airline_code)
CREATE TABLE dbo.dim_aerolinea (
    aerolinea_key   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    airline_code    NVARCHAR(5)   NOT NULL UNIQUE,
    airline_name    NVARCHAR(100) NOT NULL
);
GO

-- 2.3 Dimension Aeropuerto (dimension de ROL: origen y destino)
CREATE TABLE dbo.dim_aeropuerto (
    aeropuerto_key  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    codigo_iata     NVARCHAR(5) NOT NULL UNIQUE
);
GO

-- 2.4 Dimension Aeronave (tipo de equipo)
CREATE TABLE dbo.dim_aeronave (
    aeronave_key    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    aircraft_type   NVARCHAR(10) NOT NULL UNIQUE
);
GO

-- 2.5 Dimension Clase de cabina
CREATE TABLE dbo.dim_clase_cabina (
    clase_key       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    cabin_class     NVARCHAR(30) NOT NULL UNIQUE
);
GO

-- 2.6 Dimension Canal de venta
CREATE TABLE dbo.dim_canal_venta (
    canal_key       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    sales_channel   NVARCHAR(30) NOT NULL UNIQUE
);
GO

-- 2.7 Dimension Metodo de pago
CREATE TABLE dbo.dim_metodo_pago (
    metodo_pago_key INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    payment_method  NVARCHAR(30) NOT NULL UNIQUE
);
GO

-- 2.8 Dimension Estado del vuelo
CREATE TABLE dbo.dim_estado_vuelo (
    estado_key      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    status          NVARCHAR(20) NOT NULL UNIQUE
);
GO

-- 2.9 Dimension Pasajero — SLOWLY CHANGING DIMENSION TIPO 2
CREATE TABLE dbo.dim_pasajero (
    pasajero_key         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,   -- clave subrogada
    passenger_id         NVARCHAR(50)  NOT NULL,                   -- clave de negocio (natural)
    genero               NVARCHAR(20)  NOT NULL,
    edad                 TINYINT       NULL,
    nacionalidad         NVARCHAR(5)   NULL,
    version              INT           NOT NULL DEFAULT 1,
    fecha_inicio_validez  DATETIME2     NOT NULL,
    fecha_fin_validez     DATETIME2     NULL,                      -- NULL = version vigente
    es_actual             BIT           NOT NULL DEFAULT 1
);
CREATE INDEX IX_dim_pasajero_business_key ON dbo.dim_pasajero (passenger_id, es_actual);
GO

/* =====================================================================
   3. TABLA DE HECHOS
   Grano: un registro por pasajero-boleto en un vuelo (record_id origen)
   ===================================================================== */
CREATE TABLE dbo.fact_vuelos (
    fact_key            BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    record_id           INT            NOT NULL UNIQUE,     -- dimension degenerada (id de origen)
    flight_number       NVARCHAR(10)   NOT NULL,

    -- Claves foraneas hacia las dimensiones
    fecha_salida_key    INT            NOT NULL REFERENCES dbo.dim_fecha(fecha_key),
    aerolinea_key       INT            NOT NULL REFERENCES dbo.dim_aerolinea(aerolinea_key),
    origen_key          INT            NOT NULL REFERENCES dbo.dim_aeropuerto(aeropuerto_key),
    destino_key         INT            NOT NULL REFERENCES dbo.dim_aeropuerto(aeropuerto_key),
    aeronave_key        INT            NOT NULL REFERENCES dbo.dim_aeronave(aeronave_key),
    clase_key           INT            NOT NULL REFERENCES dbo.dim_clase_cabina(clase_key),
    canal_key           INT            NOT NULL REFERENCES dbo.dim_canal_venta(canal_key),
    metodo_pago_key      INT           NOT NULL REFERENCES dbo.dim_metodo_pago(metodo_pago_key),
    estado_key           INT           NOT NULL REFERENCES dbo.dim_estado_vuelo(estado_key),
    pasajero_key         INT           NOT NULL REFERENCES dbo.dim_pasajero(pasajero_key),

    -- Atributos de fecha/hora completos (no forman parte de dim_fecha)
    fecha_hora_salida    DATETIME2     NOT NULL,
    fecha_hora_llegada   DATETIME2     NULL,                -- NULL si el vuelo fue cancelado
    fecha_hora_reserva   DATETIME2     NOT NULL,

    seat                 NVARCHAR(5)   NULL,

    -- Medidas (hechos aditivos / semi-aditivos)
    duration_min         SMALLINT      NULL,
    delay_min            SMALLINT      NULL,
    ticket_price_usd     DECIMAL(10,2) NOT NULL,
    bags_total            TINYINT      NOT NULL,
    bags_checked           TINYINT     NOT NULL
);

CREATE INDEX IX_fact_vuelos_fecha_salida  ON dbo.fact_vuelos (fecha_salida_key);
CREATE INDEX IX_fact_vuelos_aerolinea     ON dbo.fact_vuelos (aerolinea_key);
CREATE INDEX IX_fact_vuelos_pasajero      ON dbo.fact_vuelos (pasajero_key);
CREATE INDEX IX_fact_vuelos_origen_destino ON dbo.fact_vuelos (origen_key, destino_key);
GO

PRINT 'Modelo dimensional DW_Vuelos creado correctamente (9 dimensiones + 1 hecho).';
GO
