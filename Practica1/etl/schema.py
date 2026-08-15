"""
schema.py
Definicion del modelo multidimensional (esquema estrella) usando
SQLAlchemy Core. Es agnostico de motor: al llamar metadata.create_all(engine)
genera automaticamente el DDL correcto tanto para SQL Server (mssql+pyodbc)
como para SQLite (usado localmente para pruebas del proceso ETL sin
necesidad de tener SQL Server instalado).

La version "oficial" del modelo para SQL Server, con tipos T-SQL explicitos
(NVARCHAR, DATETIME2, DECIMAL, IDENTITY, indices, etc.) esta en:
    ../sql/01_create_schema_sqlserver.sql
"""

from sqlalchemy import (
    MetaData, Table, Column, Integer, BigInteger, SmallInteger, String,
    Date, DateTime, Numeric, Boolean, ForeignKey, UniqueConstraint, Index
)

metadata = MetaData()

# ---------------------------------------------------------------------
# Dimensiones
# ---------------------------------------------------------------------

dim_fecha = Table(
    "dim_fecha", metadata,
    Column("fecha_key", Integer, primary_key=True),  # YYYYMMDD
    Column("fecha", Date, nullable=False),
    Column("anio", SmallInteger, nullable=False),
    Column("mes", SmallInteger, nullable=False),
    Column("nombre_mes", String(20), nullable=False),
    Column("trimestre", SmallInteger, nullable=False),
    Column("dia", SmallInteger, nullable=False),
    Column("dia_semana", SmallInteger, nullable=False),
    Column("nombre_dia_semana", String(20), nullable=False),
    Column("es_fin_semana", Boolean, nullable=False),
)

dim_aerolinea = Table(
    "dim_aerolinea", metadata,
    Column("aerolinea_key", Integer, primary_key=True, autoincrement=True),
    Column("airline_code", String(5), nullable=False),
    Column("airline_name", String(100), nullable=False),
    UniqueConstraint("airline_code", name="uq_dim_aerolinea_code"),
)

dim_aeropuerto = Table(
    "dim_aeropuerto", metadata,
    Column("aeropuerto_key", Integer, primary_key=True, autoincrement=True),
    Column("codigo_iata", String(5), nullable=False),
    UniqueConstraint("codigo_iata", name="uq_dim_aeropuerto_iata"),
)

dim_aeronave = Table(
    "dim_aeronave", metadata,
    Column("aeronave_key", Integer, primary_key=True, autoincrement=True),
    Column("aircraft_type", String(10), nullable=False),
    UniqueConstraint("aircraft_type", name="uq_dim_aeronave_tipo"),
)

dim_clase_cabina = Table(
    "dim_clase_cabina", metadata,
    Column("clase_key", Integer, primary_key=True, autoincrement=True),
    Column("cabin_class", String(30), nullable=False),
    UniqueConstraint("cabin_class", name="uq_dim_clase_cabina"),
)

dim_canal_venta = Table(
    "dim_canal_venta", metadata,
    Column("canal_key", Integer, primary_key=True, autoincrement=True),
    Column("sales_channel", String(30), nullable=False),
    UniqueConstraint("sales_channel", name="uq_dim_canal_venta"),
)

dim_metodo_pago = Table(
    "dim_metodo_pago", metadata,
    Column("metodo_pago_key", Integer, primary_key=True, autoincrement=True),
    Column("payment_method", String(30), nullable=False),
    UniqueConstraint("payment_method", name="uq_dim_metodo_pago"),
)

dim_estado_vuelo = Table(
    "dim_estado_vuelo", metadata,
    Column("estado_key", Integer, primary_key=True, autoincrement=True),
    Column("status", String(20), nullable=False),
    UniqueConstraint("status", name="uq_dim_estado_vuelo"),
)

# Dimension de pasajero - Slowly Changing Dimension Tipo 2
dim_pasajero = Table(
    "dim_pasajero", metadata,
    Column("pasajero_key", Integer, primary_key=True, autoincrement=True),
    Column("passenger_id", String(50), nullable=False),   # clave de negocio
    Column("genero", String(20), nullable=False),
    Column("edad", SmallInteger, nullable=True),
    Column("nacionalidad", String(5), nullable=True),
    Column("version", Integer, nullable=False, default=1),
    Column("fecha_inicio_validez", DateTime, nullable=False),
    Column("fecha_fin_validez", DateTime, nullable=True),
    Column("es_actual", Boolean, nullable=False, default=True),
    Index("ix_dim_pasajero_business_key", "passenger_id", "es_actual"),
)

# ---------------------------------------------------------------------
# Tabla de hechos
# ---------------------------------------------------------------------

fact_vuelos = Table(
    "fact_vuelos", metadata,
    # Nota: se usa Integer (en vez de BigInteger) para que SQLite reconozca
    # la columna como alias de ROWID y funcione el autoincremento en pruebas
    # locales. En SQL Server el DDL oficial (sql/01_create_schema_sqlserver.sql)
    # define fact_key como BIGINT IDENTITY, mas apropiado para volumenes grandes.
    Column("fact_key", Integer, primary_key=True, autoincrement=True),
    Column("record_id", Integer, nullable=False),
    Column("flight_number", String(10), nullable=False),

    Column("fecha_salida_key", Integer, ForeignKey("dim_fecha.fecha_key"), nullable=False),
    Column("aerolinea_key", Integer, ForeignKey("dim_aerolinea.aerolinea_key"), nullable=False),
    Column("origen_key", Integer, ForeignKey("dim_aeropuerto.aeropuerto_key"), nullable=False),
    Column("destino_key", Integer, ForeignKey("dim_aeropuerto.aeropuerto_key"), nullable=False),
    Column("aeronave_key", Integer, ForeignKey("dim_aeronave.aeronave_key"), nullable=False),
    Column("clase_key", Integer, ForeignKey("dim_clase_cabina.clase_key"), nullable=False),
    Column("canal_key", Integer, ForeignKey("dim_canal_venta.canal_key"), nullable=False),
    Column("metodo_pago_key", Integer, ForeignKey("dim_metodo_pago.metodo_pago_key"), nullable=False),
    Column("estado_key", Integer, ForeignKey("dim_estado_vuelo.estado_key"), nullable=False),
    Column("pasajero_key", Integer, ForeignKey("dim_pasajero.pasajero_key"), nullable=False),

    Column("fecha_hora_salida", DateTime, nullable=False),
    Column("fecha_hora_llegada", DateTime, nullable=True),
    Column("fecha_hora_reserva", DateTime, nullable=False),

    Column("seat", String(5), nullable=True),

    Column("duration_min", SmallInteger, nullable=True),
    Column("delay_min", SmallInteger, nullable=True),
    Column("ticket_price_usd", Numeric(10, 2), nullable=False),
    Column("bags_total", SmallInteger, nullable=False),
    Column("bags_checked", SmallInteger, nullable=False),

    UniqueConstraint("record_id", name="uq_fact_vuelos_record_id"),
)
