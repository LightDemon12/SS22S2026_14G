

import os
import sys
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine


# Configuración de Logging

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("ELT_RAW_INGESTION")


# Configuración de Conexión a Base de Datos (Variables de Entorno)

DB_USER = os.getenv("POSTGRES_USER", "admin")
DB_PASSWORD = os.getenv("POSTGRES_PASSWORD", "admin")
# Host apunta al nombre del contenedor en la red Docker ("postgres_dw")
DB_HOST = os.getenv("POSTGRES_HOST", "postgres_dw")
DB_PORT = os.getenv("POSTGRES_PORT", "5432")
DB_NAME = os.getenv("POSTGRES_DB", "sgfood_db")

# Determinación inteligente de la ruta de datos (Docker /opt/airflow/data o local)
BASE_DIR = Path(__file__).resolve().parent
DEFAULT_DATA_DIR = Path("/opt/airflow/data") if Path("/opt/airflow/data").exists() else (BASE_DIR.parent / "data" if (BASE_DIR.parent / "data").exists() else BASE_DIR / "data")
DATA_DIR = Path(os.getenv("DATA_DIR", DEFAULT_DATA_DIR))

# Tablas transaccionales a extraer de oltp_sgfood
OLTP_TABLES: List[str] = [
    "sucursal",
    "categoria",
    "marca",
    "producto",
    "cliente",
    "venta",
    "venta_detalle",
]

# Mapeo de archivos CSV a tablas destino en el esquema raw
CSV_TABLE_MAPPING: Dict[str, Dict[str, str]] = {
    "inventario_bodega.csv": {
        "table": "inventario_bodega",
        "date_cols": ["fecha_corte", "fecha_vencimiento"],
    },
    "proveedores_precios.csv": {
        "table": "proveedores_precios",
        "date_cols": ["fecha_vigencia"],
    },
    "promociones.csv": {
        "table": "promociones",
        "date_cols": ["fecha_inicio", "fecha_fin"],
    },
    "metas_ventas.csv": {
        "table": "metas_ventas",
        "date_cols": [],
    },
    "devoluciones.csv": {
        "table": "devoluciones",
        "date_cols": ["fecha"],
    },
}


def get_db_engine() -> Engine:
    """Crea y retorna un Engine de SQLAlchemy para PostgreSQL."""
    conn_url = f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    return create_engine(conn_url, pool_pre_ping=True)


def truncate_raw_table(engine: Engine, table_name: str, schema: str = "raw") -> None:
    """Trunca la tabla destino en el esquema raw para asegurar idempotencia."""
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE TABLE {schema}.{table_name} RESTART IDENTITY CASCADE;"))
    logger.info(f"Tabla '{schema}.{table_name}' truncada exitosamente.")


def extract_and_load_oltp(engine: Engine, source_schema: str = "oltp_sgfood", target_schema: str = "raw") -> None:
    """
    Extrae datos de todas las tablas del esquema OLTP y las carga en el esquema RAW.
    """
    logger.info("=== Iniciando Extracción y Carga desde esquema OLTP ===")
    extract_time = datetime.now()

    for table in OLTP_TABLES:
        try:
            logger.info(f"Extrayendo tabla '{source_schema}.{table}'...")
            query = f"SELECT * FROM {source_schema}.{table};"
            df = pd.read_sql_query(query, con=engine)
            
            # Limpieza técnica mínima
            df.columns = df.columns.str.strip().str.lower()
            df["_extracted_at"] = extract_time

            # Carga en la capa RAW
            truncate_raw_table(engine, table, schema=target_schema)
            df.to_sql(
                name=table,
                con=engine,
                schema=target_schema,
                if_exists="append",
                index=False,
                chunksize=1000,
                method="multi",
            )
            logger.info(f"-> Cargados {len(df)} registros en '{target_schema}.{table}'.")
        except Exception as e:
            logger.error(f"Error procesando tabla OLTP '{table}': {e}")
            raise


def clean_csv_dataframe(df: pd.DataFrame, date_cols: Optional[List[str]] = None) -> pd.DataFrame:
    """
    Aplica limpieza técnica básica a los DataFrames provenientes de archivos CSV:
    - Normalización de nombres de columnas.
    - Limpieza de espacios en blanco en strings.
    - Conversión de columnas de fecha.
    """
    df.columns = [col.strip().lower().replace(" ", "_") for col in df.columns]

    for col in df.select_dtypes(include=["object"]).columns:
        df[col] = df[col].astype(str).str.strip()
        df[col] = df[col].replace({"nan": None, "None": None, "": None})

    if date_cols:
        for dcol in date_cols:
            if dcol in df.columns:
                df[dcol] = pd.to_datetime(df[dcol], errors="coerce").dt.date

    return df


def extract_and_load_csv(
    engine: Engine,
    data_dir: Path = DATA_DIR,
    target_schema: str = "raw",
    include_quality_cases: bool = False,
) -> None:
    """
    Lee los archivos CSV de la carpeta data/, aplica limpieza y los carga en el esquema RAW.
    """
    logger.info(f"=== Iniciando Extracción y Carga de Archivos CSV desde {data_dir} ===")
    extract_time = datetime.now()

    if not data_dir.exists():
        raise FileNotFoundError(f"El directorio de datos no existe: {data_dir}")

    for filename, config in CSV_TABLE_MAPPING.items():
        file_path = data_dir / filename
        table_name = config["table"]
        date_cols = config.get("date_cols", [])

        if not file_path.exists():
            logger.warning(f"Archivo no encontrado: {file_path}. Se omite.")
            continue

        try:
            logger.info(f"Procesando archivo '{filename}' -> tabla '{target_schema}.{table_name}'...")
            df = pd.read_csv(file_path)
            df = clean_csv_dataframe(df, date_cols=date_cols)
            df["_extracted_at"] = extract_time

            truncate_raw_table(engine, table_name, schema=target_schema)
            df.to_sql(
                name=table_name,
                con=engine,
                schema=target_schema,
                if_exists="append",
                index=False,
                chunksize=1000,
                method="multi",
            )
            logger.info(f"-> Cargados {len(df)} registros en '{target_schema}.{table_name}'.")
        except Exception as e:
            logger.error(f"Error procesando CSV '{filename}': {e}")
            raise

    if include_quality_cases:
        qc_file = data_dir / "casos_calidad_opcionales.csv"
        if qc_file.exists():
            try:
                logger.info(f"Cargando casos de calidad opcionales desde '{qc_file.name}'...")
                df_qc = pd.read_csv(qc_file)
                df_qc = clean_csv_dataframe(df_qc)
                df_qc["_extracted_at"] = extract_time
                truncate_raw_table(engine, "casos_calidad_opcionales", schema=target_schema)
                df_qc.to_sql(
                    name="casos_calidad_opcionales",
                    con=engine,
                    schema=target_schema,
                    if_exists="append",
                    index=False,
                )
                logger.info(f"-> Cargados {len(df_qc)} registros en '{target_schema}.casos_calidad_opcionales'.")
            except Exception as e:
                logger.error(f"Error al cargar casos de calidad: {e}")


def run_pipeline() -> None:
    """Función principal de ejecución del proceso ELT Fase 1 (Raw Ingestion)."""
    start_time = datetime.now()
    logger.info(">>> INICIANDO PIPELINE ELT - FASE 1 (RAW LAYER) <<<")
    
    engine = get_db_engine()
    
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1;"))
        logger.info(f"Conexión a PostgreSQL ({DB_HOST}:{DB_PORT}/{DB_NAME}) establecida exitosamente.")
        
        extract_and_load_oltp(engine)
        extract_and_load_csv(engine, include_quality_cases=True)
        
        elapsed = (datetime.now() - start_time).total_seconds()
        logger.info(f">>> PIPELINE ELT COMPLETADO CON ÉXITO EN {elapsed:.2f} SEGUNDOS <<<")
    except Exception as err:
        logger.critical(f"Fallo crítico en el pipeline ELT: {err}")
        raise


if __name__ == "__main__":
    run_pipeline()
