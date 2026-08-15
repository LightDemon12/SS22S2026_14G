"""
etl_vuelos.py
Practica 1 - Seminario de Sistemas 2 - USAC
ETL con Python: de dataset crudo a tabla relacional (modelo dimensional)
lista para analisis.

Fases:
  1. EXTRACCION : lee data/dataset_vuelos_crudo.csv
  2. TRANSFORMACION: limpieza, homologacion y estandarizacion de datos
  3. CARGA        : construye el esquema estrella (dim_* + fact_vuelos)
                    en la base de datos destino (SQL Server o SQLite)

Motor de base de datos
-----------------------
El motor se selecciona mediante la variable de entorno DB_URL:

  - SQL Server (entrega oficial):
        DB_URL="mssql+pyodbc://usuario:password@servidor/DW_Vuelos?driver=ODBC+Driver+17+for+SQL+Server"

  - SQLite (modo de prueba local, sin instalar SQL Server):
        DB_URL="sqlite:///vuelos_dw.db"      (o simplemente no definir DB_URL,
                                               este es el valor por defecto)

Uso:
    python etl_vuelos.py
    DB_URL="mssql+pyodbc://..." python etl_vuelos.py
"""

import os
import sys
import logging
from datetime import datetime

import pandas as pd
import numpy as np
from sqlalchemy import create_engine, select, insert, update

from schema import (
    metadata, dim_fecha, dim_aerolinea, dim_aeropuerto, dim_aeronave,
    dim_clase_cabina, dim_canal_venta, dim_metodo_pago, dim_estado_vuelo,
    dim_pasajero, fact_vuelos,
)

# ---------------------------------------------------------------------
# Configuracion y logging
# ---------------------------------------------------------------------
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(BASE_DIR, "..", "data", "dataset_vuelos_crudo.csv")
DB_URL = os.environ.get("DB_URL", "sqlite:///" + os.path.join(BASE_DIR, "..", "vuelos_dw.db"))
LOG_PATH = os.path.join(BASE_DIR, "..", "docs", "evidencia_ejecucion_etl.txt")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout), logging.FileHandler(LOG_PATH, mode="w", encoding="utf-8")],
)
log = logging.getLogger("etl_vuelos")

# Mapeo canonico de aerolineas (a partir del codigo IATA)
AIRLINE_CANONICAL = {
    "FR": "Ryanair", "AV": "Avianca", "IB": "Iberia", "DL": "Delta",
    "WN": "Southwest", "AA": "American Airlines", "AM": "Aeromexico",
    "B6": "JetBlue", "BA": "British Airways", "CM": "Copa Airlines",
    "LA": "LATAM", "UA": "United",
}

# Mapeo de valores de genero (min/mayus/es/en) a categoria homologada
GENDER_MAP = {
    "M": "Masculino", "m": "Masculino", "MASCULINO": "Masculino",
    "F": "Femenino", "f": "Femenino", "FEMENINO": "Femenino",
    "X": "Otro / Prefiere no decir", "x": "Otro / Prefiere no decir",
    "NOBINARIO": "No binario",
}

MESES_ES = ["", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio",
            "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]
DIAS_ES = ["Lunes", "Martes", "Miercoles", "Jueves", "Viernes", "Sabado", "Domingo"]


# =======================================================================
# 1. EXTRACCION
# =======================================================================
def extraer(csv_path: str) -> pd.DataFrame:
    log.info("=== FASE 1: EXTRACCION ===")
    df = pd.read_csv(csv_path)
    log.info(f"Se leyeron {len(df):,} filas y {df.shape[1]} columnas desde {os.path.basename(csv_path)}")
    return df


# =======================================================================
# 2. TRANSFORMACION
# =======================================================================
def parse_fecha_mixta(valor: str):
    """Convierte fechas en dos formatos posibles a datetime:
       - 'DD/MM/YYYY HH:MM'            (24 horas)
       - 'MM-DD-YYYY hh:mm AM/PM'      (12 horas)
    """
    if pd.isna(valor) or str(valor).strip() == "":
        return pd.NaT
    valor = str(valor).strip()
    try:
        if "-" in valor:
            return pd.to_datetime(valor, format="%m-%d-%Y %I:%M %p", errors="raise")
        return pd.to_datetime(valor, format="%d/%m/%Y %H:%M", errors="raise")
    except (ValueError, TypeError):
        return pd.to_datetime(valor, errors="coerce", dayfirst=True)


def normalizar_genero(valor: str) -> str:
    if pd.isna(valor):
        return "Desconocido"
    valor = str(valor).strip()
    return GENDER_MAP.get(valor, GENDER_MAP.get(valor.upper(), "Desconocido"))


def transformar(df_raw: pd.DataFrame) -> pd.DataFrame:
    log.info("=== FASE 2: TRANSFORMACION ===")
    df = df_raw.copy()
    filas_antes = len(df)

    # --- 2.1 Eliminacion de duplicados -------------------------------
    df = df.drop_duplicates(subset=["record_id"])
    log.info(f"Duplicados eliminados por record_id: {filas_antes - len(df)}")

    # --- 2.2 Codigos de aeropuerto en mayusculas ----------------------
    df["origin_airport"] = df["origin_airport"].str.strip().str.upper()
    df["destination_airport"] = df["destination_airport"].str.strip().str.upper()

    # --- 2.3 Homologacion de aerolinea (por codigo IATA) --------------
    df["airline_code"] = df["airline_code"].str.strip().str.upper()
    df["airline_name"] = df["airline_code"].map(AIRLINE_CANONICAL).fillna(df["airline_name"].str.title())

    # --- 2.4 Estandarizacion de genero ---------------------------------
    df["passenger_gender"] = df["passenger_gender"].apply(normalizar_genero)

    # --- 2.5 Tratamiento de nulos: edad, nacionalidad, canal de venta --
    edad_mediana = df["passenger_age"].median()
    n_edad_nula = df["passenger_age"].isna().sum()
    df["passenger_age"] = df["passenger_age"].fillna(edad_mediana).astype(int)
    log.info(f"passenger_age: {n_edad_nula} nulos imputados con la mediana ({edad_mediana:.0f} anios)")

    n_nac_nula = df["passenger_nationality"].isna().sum()
    df["passenger_nationality"] = df["passenger_nationality"].fillna("XX")  # XX = desconocida
    log.info(f"passenger_nationality: {n_nac_nula} nulos marcados como 'XX' (desconocida)")

    n_canal_nulo = df["sales_channel"].isna().sum()
    df["sales_channel"] = df["sales_channel"].fillna("DESCONOCIDO")
    log.info(f"sales_channel: {n_canal_nulo} nulos marcados como 'DESCONOCIDO'")

    # --- 2.6 Estandarizacion de fechas (dos formatos mixtos) -----------
    for col in ["departure_datetime", "arrival_datetime", "booking_datetime"]:
        df[col] = df[col].apply(parse_fecha_mixta)
    n_llegada_nula = df["arrival_datetime"].isna().sum()
    log.info(f"arrival_datetime: {n_llegada_nula} valores nulos "
             f"(vuelos CANCELLED, es un nulo legitimo, no se imputa)")

    # --- 2.7 Estandarizacion de ticket_price (coma/punto decimal) ------
    df["ticket_price"] = (
        df["ticket_price"].astype(str).str.replace(",", ".", regex=False).astype(float)
    )
    # Se utiliza la conversion a USD ya estimada en el crudo (ticket_price_usd_est),
    # limpiada de decimales y renombrada como medida oficial del hecho.
    df["ticket_price_usd"] = df["ticket_price_usd_est"].round(2)

    # --- 2.8 duration_min / delay_min: nulos legitimos para CANCELLED --
    # Se dejan como nulos (no se imputan) porque un vuelo cancelado no
    # tiene duracion real ni retraso medible.
    df["duration_min"] = df["duration_min"]
    df["delay_min"] = df["delay_min"]

    # --- 2.9 bags: enteros ---------------------------------------------
    df["bags_total"] = df["bags_total"].astype(int)
    df["bags_checked"] = df["bags_checked"].astype(int)

    # --- 2.10 Revision final de nulos -----------------------------------
    log.info("Valores nulos por columna tras la transformacion:")
    for col, n in df.isnull().sum().items():
        if n > 0:
            log.info(f"   - {col}: {n}")

    log.info(f"Filas resultantes tras la transformacion: {len(df):,}")
    return df


# =======================================================================
# 3. CARGA
# =======================================================================
def construir_dim_fecha(fechas: pd.Series) -> pd.DataFrame:
    """Genera un calendario continuo que cubre el rango de fechas de salida."""
    fecha_min = fechas.min().normalize()
    fecha_max = fechas.max().normalize()
    rango = pd.date_range(fecha_min, fecha_max, freq="D")
    registros = []
    for f in rango:
        registros.append({
            "fecha_key": int(f.strftime("%Y%m%d")),
            "fecha": f.date(),
            "anio": f.year,
            "mes": f.month,
            "nombre_mes": MESES_ES[f.month],
            "trimestre": (f.month - 1) // 3 + 1,
            "dia": f.day,
            "dia_semana": f.isoweekday(),
            "nombre_dia_semana": DIAS_ES[f.isoweekday() - 1],
            "es_fin_semana": f.isoweekday() in (6, 7),
        })
    return pd.DataFrame(registros)


def cargar_dimension_simple(engine, tabla, columna_negocio, valores: pd.Series):
    """Inserta valores unicos de una columna en una tabla de dimension simple
    (si aun no existen) y retorna un dict {valor_negocio: surrogate_key}."""
    valores_unicos = sorted(set(valores.dropna().tolist()))
    with engine.begin() as conn:
        existentes = {
            row[0]: row[1]
            for row in conn.execute(select(tabla.c[columna_negocio], tabla.c[tabla.primary_key.columns.keys()[0]]))
        }
        nuevos = [v for v in valores_unicos if v not in existentes]
        if nuevos:
            conn.execute(insert(tabla), [{columna_negocio: v} for v in nuevos])
        # recargar mapping completo
        mapping = {
            row[0]: row[1]
            for row in conn.execute(select(tabla.c[columna_negocio], tabla.c[tabla.primary_key.columns.keys()[0]]))
        }
    return mapping


def cargar_dim_aerolinea(engine, df):
    combos = df[["airline_code", "airline_name"]].drop_duplicates()
    with engine.begin() as conn:
        existentes = {row[0]: row[1] for row in conn.execute(
            select(dim_aerolinea.c.airline_code, dim_aerolinea.c.aerolinea_key))}
        nuevos = [
            {"airline_code": r.airline_code, "airline_name": r.airline_name}
            for r in combos.itertuples() if r.airline_code not in existentes
        ]
        if nuevos:
            conn.execute(insert(dim_aerolinea), nuevos)
        mapping = {row[0]: row[1] for row in conn.execute(
            select(dim_aerolinea.c.airline_code, dim_aerolinea.c.aerolinea_key))}
    return mapping


def cargar_dim_pasajero_scd2(engine, df, fecha_carga: datetime):
    """Implementa la logica SCD Tipo 2 para dim_pasajero.
    Para cada passenger_id:
      - Si no existe -> se inserta version 1 (vigente).
      - Si existe y los atributos (genero/edad/nacionalidad) cambiaron
        respecto de la version vigente -> se cierra la version anterior
        (fecha_fin_validez = fecha_carga, es_actual = 0) y se inserta una
        nueva version (version += 1, es_actual = 1).
      - Si existe y los atributos son iguales -> no se hace nada.
    Retorna un dict {passenger_id: pasajero_key_vigente}.
    """
    pasajeros = df[["passenger_id", "passenger_gender", "passenger_age", "passenger_nationality"]].drop_duplicates(
        subset=["passenger_id"]
    )

    mapping = {}
    altas, cambios = 0, 0
    with engine.begin() as conn:
        vigentes = {
            row.passenger_id: row
            for row in conn.execute(
                select(dim_pasajero).where(dim_pasajero.c.es_actual == True)  # noqa: E712
            )
        }
        for r in pasajeros.itertuples():
            actual = vigentes.get(r.passenger_id)
            if actual is None:
                # Alta nueva (version 1)
                result = conn.execute(insert(dim_pasajero).values(
                    passenger_id=r.passenger_id,
                    genero=r.passenger_gender,
                    edad=int(r.passenger_age),
                    nacionalidad=r.passenger_nationality,
                    version=1,
                    fecha_inicio_validez=fecha_carga,
                    fecha_fin_validez=None,
                    es_actual=True,
                ))
                mapping[r.passenger_id] = result.inserted_primary_key[0]
                altas += 1
            else:
                cambio = (
                    actual.genero != r.passenger_gender
                    or actual.edad != int(r.passenger_age)
                    or actual.nacionalidad != r.passenger_nationality
                )
                if cambio:
                    conn.execute(
                        update(dim_pasajero)
                        .where(dim_pasajero.c.pasajero_key == actual.pasajero_key)
                        .values(fecha_fin_validez=fecha_carga, es_actual=False)
                    )
                    result = conn.execute(insert(dim_pasajero).values(
                        passenger_id=r.passenger_id,
                        genero=r.passenger_gender,
                        edad=int(r.passenger_age),
                        nacionalidad=r.passenger_nationality,
                        version=actual.version + 1,
                        fecha_inicio_validez=fecha_carga,
                        fecha_fin_validez=None,
                        es_actual=True,
                    ))
                    mapping[r.passenger_id] = result.inserted_primary_key[0]
                    cambios += 1
                else:
                    mapping[r.passenger_id] = actual.pasajero_key
    log.info(f"dim_pasajero (SCD2): {altas:,} altas nuevas, {cambios:,} nuevas versiones por cambio de atributos")
    return mapping


def cargar(df: pd.DataFrame, db_url: str):
    log.info("=== FASE 3: CARGA ===")
    engine = create_engine(db_url)
    metadata.create_all(engine)
    log.info(f"Esquema creado/verificado en: {db_url}")

    fecha_carga = datetime.now()

    # --- Dimensiones simples --------------------------------------------
    map_aeropuerto = cargar_dimension_simple(
        engine, dim_aeropuerto, "codigo_iata",
        pd.concat([df["origin_airport"], df["destination_airport"]])
    )
    map_aeronave = cargar_dimension_simple(engine, dim_aeronave, "aircraft_type", df["aircraft_type"])
    map_clase = cargar_dimension_simple(engine, dim_clase_cabina, "cabin_class", df["cabin_class"])
    map_canal = cargar_dimension_simple(engine, dim_canal_venta, "sales_channel", df["sales_channel"])
    map_metodo_pago = cargar_dimension_simple(engine, dim_metodo_pago, "payment_method", df["payment_method"])
    map_estado = cargar_dimension_simple(engine, dim_estado_vuelo, "status", df["status"])
    map_aerolinea = cargar_dim_aerolinea(engine, df)

    # --- Dimension fecha (calendario) ------------------------------------
    df_fecha = construir_dim_fecha(df["departure_datetime"])
    with engine.begin() as conn:
        existentes = {row[0] for row in conn.execute(select(dim_fecha.c.fecha_key))}
        nuevos = df_fecha[~df_fecha["fecha_key"].isin(existentes)]
        if len(nuevos):
            conn.execute(insert(dim_fecha), nuevos.to_dict(orient="records"))
    log.info(f"dim_fecha: {len(df_fecha):,} fechas en el calendario ({df_fecha['fecha'].min()} a {df_fecha['fecha'].max()})")

    # --- Dimension pasajero (SCD2) ----------------------------------------
    map_pasajero = cargar_dim_pasajero_scd2(engine, df, fecha_carga)

    # --- Tabla de hechos -----------------------------------------------
    registros_fact = []
    for r in df.itertuples():
        registros_fact.append({
            "record_id": int(r.record_id),
            "flight_number": r.flight_number,
            "fecha_salida_key": int(r.departure_datetime.strftime("%Y%m%d")),
            "aerolinea_key": map_aerolinea[r.airline_code],
            "origen_key": map_aeropuerto[r.origin_airport],
            "destino_key": map_aeropuerto[r.destination_airport],
            "aeronave_key": map_aeronave[r.aircraft_type],
            "clase_key": map_clase[r.cabin_class],
            "canal_key": map_canal[r.sales_channel],
            "metodo_pago_key": map_metodo_pago[r.payment_method],
            "estado_key": map_estado[r.status],
            "pasajero_key": map_pasajero[r.passenger_id],
            "fecha_hora_salida": r.departure_datetime.to_pydatetime(),
            "fecha_hora_llegada": None if pd.isna(r.arrival_datetime) else r.arrival_datetime.to_pydatetime(),
            "fecha_hora_reserva": r.booking_datetime.to_pydatetime(),
            "seat": None if pd.isna(r.seat) else r.seat,
            "duration_min": None if pd.isna(r.duration_min) else int(r.duration_min),
            "delay_min": None if pd.isna(r.delay_min) else int(r.delay_min),
            "ticket_price_usd": float(r.ticket_price_usd),
            "bags_total": int(r.bags_total),
            "bags_checked": int(r.bags_checked),
        })

    with engine.begin() as conn:
        conn.execute(dim_fecha.delete().where(1 == 0))  # no-op, mantiene la conexion "tibia"
        # Carga por lotes para eficiencia
        batch = 1000
        for i in range(0, len(registros_fact), batch):
            conn.execute(insert(fact_vuelos), registros_fact[i:i + batch])

    log.info(f"fact_vuelos: {len(registros_fact):,} registros cargados")
    return engine


# =======================================================================
# MAIN
# =======================================================================
def main():
    log.info(f"Motor de base de datos destino: {DB_URL}")
    df_raw = extraer(CSV_PATH)
    df_clean = transformar(df_raw)
    engine = cargar(df_clean, DB_URL)
    log.info("=== PROCESO ETL FINALIZADO CORRECTAMENTE ===")
    return engine


if __name__ == "__main__":
    main()
