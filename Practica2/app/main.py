import subprocess
import time
import pandas as pd
import numpy as np
from sqlalchemy import create_engine, text
import urllib
import os
from dotenv import load_dotenv

load_dotenv()

# ==========================================
# CONFIGURACIÓN GENERAL
# ==========================================
DB_USER = os.getenv("DB_USER", "sa")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_NAME = os.getenv("DB_NAME", "DW_Vuelos")
DB_PORT = os.getenv("DB_PORT", "1433")
CONTAINER_NAME = os.getenv("CONTAINER_NAME", "sql_server_bi")
DRIVER = "ODBC Driver 18 for SQL Server"

if not DB_PASSWORD:
    raise ValueError("Error: La contraseña de la base de datos no está definida en el archivo .env")

def gestionar_docker():
    print("--- 1. CONFIGURACIÓN DE INFRAESTRUCTURA DOCKER ---")
    print("Eliminando contenedor anterior si existe...")
    subprocess.run(["docker", "rm", "-f", CONTAINER_NAME], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    print("Iniciando nuevo contenedor SQL Server...")
    cmd_run = [
        "docker", "run",
        "-e", "ACCEPT_EULA=Y",
        "-e", f"MSSQL_SA_PASSWORD={DB_PASSWORD}",
        "-p", "1433:1433",
        "--name", CONTAINER_NAME,
        "-d", "mcr.microsoft.com/mssql/server:2022-latest"
    ]
    subprocess.run(cmd_run, check=True)
    
    # SQL Server toma unos segundos en estar listo para aceptar conexiones
    print("Esperando 20 segundos para que el motor de base de datos arranque completamente...")
    time.sleep(20)

def crear_base_y_tablas():
    print(f"\n--- 2. CREACIÓN DE BASE DE DATOS '{DB_NAME}' Y MODELO MULTIDIMENSIONAL ---")
    
    params_master = urllib.parse.quote_plus(
        f"DRIVER={{{DRIVER}}};SERVER=localhost,{DB_PORT};DATABASE=master;UID={DB_USER};PWD={DB_PASSWORD};TrustServerCertificate=yes"
    )
    engine_master = create_engine(f"mssql+pyodbc:///?odbc_connect={params_master}", isolation_level="AUTOCOMMIT")
    
    with engine_master.connect() as conn:
        try:
            conn.execute(text(f"CREATE DATABASE {DB_NAME}"))
        except Exception:
            pass
            
    params_dw = urllib.parse.quote_plus(
        f"DRIVER={{{DRIVER}}};SERVER=localhost,{DB_PORT};DATABASE={DB_NAME};UID={DB_USER};PWD={DB_PASSWORD};TrustServerCertificate=yes"
    )
    engine_dw = create_engine(f"mssql+pyodbc:///?odbc_connect={params_dw}")
    
    ddl_script = """
    CREATE TABLE Dim_Aerolinea (
        Aerolinea_SK INT IDENTITY(1,1) PRIMARY KEY,
        Airline_Code VARCHAR(10) NOT NULL,
        Airline_Name VARCHAR(100)
    );

    CREATE TABLE Dim_Aeropuerto (
        Aeropuerto_SK INT IDENTITY(1,1) PRIMARY KEY,
        Airport_Code VARCHAR(10) NOT NULL
    );

    CREATE TABLE Dim_Tiempo (
        Tiempo_SK INT PRIMARY KEY,
        Fecha DATE,
        Anio INT,
        Mes INT,
        Dia INT,
        Trimestre INT,
        DiaSemana VARCHAR(20)
    );

    CREATE TABLE Dim_Pasajero (
        Pasajero_SK INT IDENTITY(1,1) PRIMARY KEY,
        Passenger_ID VARCHAR(50) NOT NULL,
        Gender VARCHAR(5),
        Age FLOAT,
        Nationality VARCHAR(10),
        Fecha_Inicio DATETIME DEFAULT GETDATE(),
        Fecha_Fin DATETIME NULL,
        Es_Activo BIT DEFAULT 1
    );

    CREATE TABLE Dim_Estado_Vuelo (
        Estado_Vuelo_SK INT IDENTITY(1,1) PRIMARY KEY,
        Status_Name VARCHAR(20) NOT NULL
    );

    CREATE TABLE Dim_Canal_Venta (
        Canal_Venta_SK INT IDENTITY(1,1) PRIMARY KEY,
        Channel_Name VARCHAR(50) NOT NULL
    );

    CREATE TABLE Dim_Metodo_Pago (
        Metodo_Pago_SK INT IDENTITY(1,1) PRIMARY KEY,
        Payment_Name VARCHAR(50) NOT NULL
    );

    CREATE TABLE Dim_Vuelo (
        Vuelo_SK INT IDENTITY(1,1) PRIMARY KEY,
        Flight_Number VARCHAR(20) NOT NULL
    );

    CREATE TABLE Fact_Vuelos (
        Fact_ID INT IDENTITY(1,1) PRIMARY KEY,
        Record_ID INT NOT NULL,
        Vuelo_SK INT FOREIGN KEY REFERENCES Dim_Vuelo(Vuelo_SK),
        Aerolinea_SK INT FOREIGN KEY REFERENCES Dim_Aerolinea(Aerolinea_SK),
        Origen_Aeropuerto_SK INT FOREIGN KEY REFERENCES Dim_Aeropuerto(Aeropuerto_SK),
        Destino_Aeropuerto_SK INT FOREIGN KEY REFERENCES Dim_Aeropuerto(Aeropuerto_SK),
        Salida_Tiempo_SK INT FOREIGN KEY REFERENCES Dim_Tiempo(Tiempo_SK),
        Llegada_Tiempo_SK INT FOREIGN KEY REFERENCES Dim_Tiempo(Tiempo_SK),
        Pasajero_SK INT FOREIGN KEY REFERENCES Dim_Pasajero(Pasajero_SK),
        Estado_Vuelo_SK INT FOREIGN KEY REFERENCES Dim_Estado_Vuelo(Estado_Vuelo_SK),
        Canal_Venta_SK INT FOREIGN KEY REFERENCES Dim_Canal_Venta(Canal_Venta_SK),
        Metodo_Pago_SK INT FOREIGN KEY REFERENCES Dim_Metodo_Pago(Metodo_Pago_SK),
        Duration_Min FLOAT,
        Delay_Min FLOAT,
        Ticket_Price_USD_Est FLOAT,
        Bags_Total INT,
        Bags_Checked INT
    );
    """
    with engine_dw.connect() as conn:
        for statement in ddl_script.split(';'):
            if statement.strip():
                conn.execute(text(statement.strip()))
        conn.commit()
    
    return engine_dw

def generar_diagrama_mermaid():
    print("\n--- 3. GENERANDO DIAGRAMA MERMAID ---")
    mermaid_code = """```mermaid
erDiagram
    Fact_Vuelos {
        INT Fact_ID PK
        INT Record_ID
        FLOAT Duration_Min
        FLOAT Delay_Min
        FLOAT Ticket_Price_USD_Est
        INT Bags_Total
        INT Bags_Checked
    }
    
    Dim_Aerolinea {
        INT Aerolinea_SK PK
        VARCHAR Airline_Code
        VARCHAR Airline_Name
    }
    
    Dim_Aeropuerto {
        INT Aeropuerto_SK PK
        VARCHAR Airport_Code
    }
    
    Dim_Tiempo {
        INT Tiempo_SK PK
        DATE Fecha
        INT Anio
        INT Mes
        INT Dia
        INT Trimestre
        VARCHAR DiaSemana
    }
    
    Dim_Pasajero {
        INT Pasajero_SK PK
        VARCHAR Passenger_ID
        VARCHAR Gender
        FLOAT Age
        VARCHAR Nationality
        DATETIME Fecha_Inicio
        DATETIME Fecha_Fin
        BIT Es_Activo
    }

    Dim_Estado_Vuelo {
        INT Estado_Vuelo_SK PK
        VARCHAR Status_Name
    }

    Dim_Canal_Venta {
        INT Canal_Venta_SK PK
        VARCHAR Channel_Name
    }

    Dim_Metodo_Pago {
        INT Metodo_Pago_SK PK
        VARCHAR Payment_Name
    }

    Dim_Vuelo {
        INT Vuelo_SK PK
        VARCHAR Flight_Number
    }

    Fact_Vuelos }|--|| Dim_Vuelo : "Vuelo_SK"
    Fact_Vuelos }|--|| Dim_Aerolinea : "Aerolinea_SK"
    Fact_Vuelos }|--|| Dim_Aeropuerto : "Origen_Aeropuerto_SK"
    Fact_Vuelos }|--|| Dim_Aeropuerto : "Destino_Aeropuerto_SK"
    Fact_Vuelos }|--|| Dim_Tiempo : "Salida_Tiempo_SK"
    Fact_Vuelos }|--|| Dim_Tiempo : "Llegada_Tiempo_SK"
    Fact_Vuelos }|--|| Dim_Pasajero : "Pasajero_SK"
    Fact_Vuelos }|--|| Dim_Estado_Vuelo : "Estado_Vuelo_SK"
    Fact_Vuelos }|--|| Dim_Canal_Venta : "Canal_Venta_SK"
    Fact_Vuelos }|--|| Dim_Metodo_Pago : "Metodo_Pago_SK"
```"""
    with open("diagrama_db.md", "w", encoding="utf-8") as f:
        f.write(f"# Diagrama Entidad-Relación {DB_NAME}\n\n")
        f.write(mermaid_code)

def ejecutar_etl(engine_dw):
    print("\n--- 4. PROCESO ETL: EXTRACCIÓN Y TRANSFORMACIÓN ---")
    ruta_archivo = "raw-data/dataset_vuelos_crudo.csv"
    df = pd.read_csv(ruta_archivo, sep=None, engine="python", encoding="utf-8")

    df['destination_airport'] = df['destination_airport'].str.upper()
    df['origin_airport'] = df['origin_airport'].str.upper()
    df['airline_name'] = df['airline_name'].str.title()

    diccionario_generos = {
        'm': 'M', 'masculino': 'M', 'Masculino': 'M', 'M': 'M',
        'f': 'F', 'femenino': 'F', 'Femenino': 'F', 'F': 'F',
        'x': 'X', 'nobinario': 'X', 'NoBinario': 'X', 'X': 'X'
    }
    df['passenger_gender'] = df['passenger_gender'].str.strip().map(diccionario_generos).fillna(df['passenger_gender'])
    df['ticket_price'] = df['ticket_price'].astype(str).str.replace(',', '.').astype(float)

    for col in ['departure_datetime', 'arrival_datetime', 'booking_datetime']:
        df[col] = pd.to_datetime(df[col], format='mixed', errors='coerce')

    filtro_cancelados = df['status'] == 'CANCELLED'
    df.loc[filtro_cancelados, 'arrival_datetime'] = pd.NaT
    df.loc[filtro_cancelados, ['delay_min', 'duration_min']] = np.nan

    filtro_atiempo = df['status'] == 'ON_TIME'
    df.loc[filtro_atiempo, 'delay_min'] = df.loc[filtro_atiempo, 'delay_min'].fillna(0)

    print("--- 5. PROCESO ETL: CARGA DE DATOS ---")
    try:
        dim_aerolinea = df[['airline_code', 'airline_name']].drop_duplicates().rename(columns={'airline_code': 'Airline_Code', 'airline_name': 'Airline_Name'})
        dim_aerolinea.to_sql('Dim_Aerolinea', engine_dw, if_exists='append', index=False)
        dim_aerolinea_db = pd.read_sql("SELECT Aerolinea_SK, Airline_Code FROM Dim_Aerolinea", engine_dw)

        aeropuertos = pd.concat([df['origin_airport'], df['destination_airport']]).dropna().unique()
        dim_aeropuerto = pd.DataFrame({'Airport_Code': aeropuertos})
        dim_aeropuerto.to_sql('Dim_Aeropuerto', engine_dw, if_exists='append', index=False)
        dim_aeropuerto_db = pd.read_sql("SELECT Aeropuerto_SK, Airport_Code FROM Dim_Aeropuerto", engine_dw)

        fechas = pd.concat([df['departure_datetime'], df['arrival_datetime']]).dropna().dt.date.unique()
        dim_tiempo = pd.DataFrame({'Fecha': fechas})
        dim_tiempo['Tiempo_SK'] = pd.to_datetime(dim_tiempo['Fecha']).dt.strftime('%Y%m%d').astype(int)
        dim_tiempo['Anio'] = pd.to_datetime(dim_tiempo['Fecha']).dt.year
        dim_tiempo['Mes'] = pd.to_datetime(dim_tiempo['Fecha']).dt.month
        dim_tiempo['Dia'] = pd.to_datetime(dim_tiempo['Fecha']).dt.day
        dim_tiempo['Trimestre'] = pd.to_datetime(dim_tiempo['Fecha']).dt.quarter
        dim_tiempo['DiaSemana'] = pd.to_datetime(dim_tiempo['Fecha']).dt.day_name()
        dim_tiempo.to_sql('Dim_Tiempo', engine_dw, if_exists='append', index=False)

        dim_pasajero = df[['passenger_id', 'passenger_gender', 'passenger_age', 'passenger_nationality']].drop_duplicates(subset=['passenger_id'])
        dim_pasajero = dim_pasajero.rename(columns={'passenger_id': 'Passenger_ID', 'passenger_gender': 'Gender', 'passenger_age': 'Age', 'passenger_nationality': 'Nationality'})
        dim_pasajero.to_sql('Dim_Pasajero', engine_dw, if_exists='append', index=False)
        dim_pasajero_db = pd.read_sql("SELECT Pasajero_SK, Passenger_ID FROM Dim_Pasajero", engine_dw)

        dim_estado = pd.DataFrame({'Status_Name': df['status'].dropna().unique()})
        dim_estado.to_sql('Dim_Estado_Vuelo', engine_dw, if_exists='append', index=False)
        dim_estado_db = pd.read_sql("SELECT Estado_Vuelo_SK, Status_Name FROM Dim_Estado_Vuelo", engine_dw)

        dim_canal = pd.DataFrame({'Channel_Name': df['sales_channel'].dropna().unique()})
        dim_canal.to_sql('Dim_Canal_Venta', engine_dw, if_exists='append', index=False)
        dim_canal_db = pd.read_sql("SELECT Canal_Venta_SK, Channel_Name FROM Dim_Canal_Venta", engine_dw)

        dim_pago = pd.DataFrame({'Payment_Name': df['payment_method'].dropna().unique()})
        dim_pago.to_sql('Dim_Metodo_Pago', engine_dw, if_exists='append', index=False)
        dim_pago_db = pd.read_sql("SELECT Metodo_Pago_SK, Payment_Name FROM Dim_Metodo_Pago", engine_dw)

        dim_vuelo = pd.DataFrame({'Flight_Number': df['flight_number'].dropna().unique()})
        dim_vuelo.to_sql('Dim_Vuelo', engine_dw, if_exists='append', index=False)
        dim_vuelo_db = pd.read_sql("SELECT Vuelo_SK, Flight_Number FROM Dim_Vuelo", engine_dw)

        fact = df.copy()
        fact = fact.merge(dim_vuelo_db, left_on='flight_number', right_on='Flight_Number', how='left')
        fact = fact.merge(dim_aerolinea_db, left_on='airline_code', right_on='Airline_Code', how='left')
        fact = fact.merge(dim_aeropuerto_db, left_on='origin_airport', right_on='Airport_Code', how='left').rename(columns={'Aeropuerto_SK': 'Origen_Aeropuerto_SK'})
        fact = fact.merge(dim_aeropuerto_db, left_on='destination_airport', right_on='Airport_Code', how='left').rename(columns={'Aeropuerto_SK': 'Destino_Aeropuerto_SK'})
        fact = fact.merge(dim_pasajero_db, left_on='passenger_id', right_on='Passenger_ID', how='left')
        fact = fact.merge(dim_estado_db, left_on='status', right_on='Status_Name', how='left')
        fact = fact.merge(dim_canal_db, left_on='sales_channel', right_on='Channel_Name', how='left')
        fact = fact.merge(dim_pago_db, left_on='payment_method', right_on='Payment_Name', how='left')

        fact['Salida_Tiempo_SK'] = fact['departure_datetime'].dt.strftime('%Y%m%d').fillna(0).astype(int)
        fact['Llegada_Tiempo_SK'] = fact['arrival_datetime'].dt.strftime('%Y%m%d').astype(float)

        columnas_fact = [
            'record_id', 'Vuelo_SK', 'Aerolinea_SK', 'Origen_Aeropuerto_SK', 'Destino_Aeropuerto_SK',
            'Salida_Tiempo_SK', 'Llegada_Tiempo_SK', 'Pasajero_SK', 'Estado_Vuelo_SK', 'Canal_Venta_SK', 
            'Metodo_Pago_SK', 'duration_min', 'delay_min', 'ticket_price_usd_est', 'bags_total', 'bags_checked'
        ]
        
        fact_final = fact[columnas_fact].copy()
        fact_final.columns = [
            'Record_ID', 'Vuelo_SK', 'Aerolinea_SK', 'Origen_Aeropuerto_SK', 'Destino_Aeropuerto_SK',
            'Salida_Tiempo_SK', 'Llegada_Tiempo_SK', 'Pasajero_SK', 'Estado_Vuelo_SK', 'Canal_Venta_SK', 
            'Metodo_Pago_SK', 'Duration_Min', 'Delay_Min', 'Ticket_Price_USD_Est', 'Bags_Total', 'Bags_Checked'
        ]

        fact_final.to_sql('Fact_Vuelos', engine_dw, if_exists='append', index=False)
        print("Proceso finalizado con éxito.")

    except Exception as e:
        print(f"Ocurrió un error en la carga de datos: {e}")

if __name__ == "__main__":
    gestionar_docker()
    engine = crear_base_y_tablas()
    generar_diagrama_mermaid()
    ejecutar_etl(engine)