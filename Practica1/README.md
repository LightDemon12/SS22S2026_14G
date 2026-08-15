# Práctica 1 — ETL con Python: de dataset crudo a tabla relacional lista para análisis

**Curso:** Seminario de Sistemas 2
**Universidad:** Universidad de San Carlos de Guatemala — Facultad de Ingeniería — Ingeniería en Ciencias y Sistemas
**Estudiante:** Angel — Carné 202100215
**Grupo:** 14
**Repositorio:** `SS22S2026_14G` / Carpeta: `Practica1`

---

## 1. Descripción del proceso ETL

El dataset de origen (`dataset_vuelos_crudo.csv`, 10,000 registros de vuelos/reservas)
proviene de múltiples fuentes heterogéneas simuladas y presenta los problemas típicos
de datos crudos:

| Problema detectado | Ejemplo |
|---|---|
| Nombres de aerolínea con formato inconsistente | `Ryanair`, `RYANAIR` |
| Códigos de aeropuerto en minúscula/mayúscula mixta | `jfk`, `MEX`, `sjo` |
| Género del pasajero en múltiples idiomas/formatos | `M`, `m`, `Masculino`, `masculino`, `X`, `NoBinario` |
| Dos formatos de fecha/hora mezclados | `20/01/2024 10:14` (24h) vs. `03-15-2025 01:58 PM` (12h) |
| Separador decimal mixto en el precio del boleto | `"77,60"` vs. `138.8` |
| Múltiples monedas (`USD`, `GTQ`, `MXN`, `EUR`) | requiere una medida común (USD) |
| Valores faltantes | `passenger_age`, `passenger_nationality`, `sales_channel`, y campos de llegada para vuelos `CANCELLED` |

El proceso ETL (`etl/etl_vuelos.py`) resuelve estos problemas en tres fases:

### 1.1 Extracción
Lectura del archivo `data/dataset_vuelos_crudo.csv` con `pandas.read_csv`.

### 1.2 Transformación
- **Duplicados:** eliminación por `record_id` (clave de origen).
- **Aerolíneas:** se homologa el nombre a partir de un diccionario canónico
  indexado por `airline_code` (evita depender del texto libre inconsistente).
- **Aeropuertos:** códigos IATA normalizados a mayúsculas.
- **Género:** homologado a `Masculino` / `Femenino` / `No binario` /
  `Otro / Prefiere no decir` / `Desconocido`, sin importar el idioma o
  capitalización de origen.
- **Fechas:** función `parse_fecha_mixta()` detecta y convierte los dos
  formatos presentes (`DD/MM/YYYY HH:MM` y `MM-DD-YYYY hh:mm AM/PM`) a
  `datetime` único.
- **Precio del boleto:** se reemplaza la coma decimal por punto y se castea
  a `float`; se usa la conversión a USD ya provista en el crudo
  (`ticket_price_usd_est`) como medida oficial `ticket_price_usd` del hecho.
- **Valores faltantes:**
  - `passenger_age` (112 nulos) → imputados con la mediana.
  - `passenger_nationality` (209 nulos) → marcados como `"XX"` (desconocida).
  - `sales_channel` (144 nulos) → marcados como `"DESCONOCIDO"`.
  - `arrival_datetime`, `duration_min`, `delay_min`, `seat` (560 nulos c/u)
    → **se dejan como nulos intencionalmente**, ya que corresponden en su
    totalidad a vuelos con `status = CANCELLED`: un vuelo cancelado no tiene
    hora de llegada, duración real ni retraso medible, así que imputar un
    valor aquí introduciría información falsa.

### 1.3 Carga
El script construye el modelo dimensional (ver sección 2) directamente en la
base de datos destino usando SQLAlchemy:
1. Se cargan primero las dimensiones simples (aerolínea, aeropuerto,
   aeronave, clase de cabina, canal de venta, método de pago, estado de vuelo).
2. Se construye `dim_fecha` como un calendario continuo que cubre todo el
   rango de fechas de salida presentes en los datos.
3. Se carga `dim_pasajero` aplicando la lógica **SCD Tipo 2** (ver sección 3).
4. Finalmente se cargan los 10,000 registros en `fact_vuelos`, resolviendo
   cada clave foránea contra las dimensiones ya cargadas.

---

## 2. Diseño del modelo multidimensional

Se implementó un **esquema estrella** con 9 dimensiones y 1 tabla de hechos.

![Modelo dimensional](./diagrams/modelo_dimensional.png)

**Grano del hecho `fact_vuelos`:** un registro por pasajero-boleto en un
vuelo (equivalente a un `record_id` del dataset de origen).

**Particularidades del diseño:**
- **`dim_aeropuerto` es una dimensión de ROL**: la misma tabla de aeropuertos
  se referencia dos veces desde `fact_vuelos` (`origen_key` y `destino_key`),
  evitando duplicar el catálogo de aeropuertos.
- **`dim_pasajero` es una dimensión de tipo 2 (Slowly Changing Dimension
  Type 2)** — ver detalle en la sección 3.
- **Medidas del hecho:** `duration_min`, `delay_min`, `ticket_price_usd`,
  `bags_total`, `bags_checked`.
- **Dimensión degenerada:** `record_id` y `flight_number` viven directamente
  en el hecho (no ameritan una tabla de dimensión propia).

El script T-SQL con la definición completa del modelo (tipos de dato,
llaves primarias/foráneas, índices) está en
[`sql/01_create_schema_sqlserver.sql`](./sql/01_create_schema_sqlserver.sql).
La versión "agnóstica de motor" usada por el ETL para poder correr también
contra SQLite está en [`etl/schema.py`](./etl/schema.py) (SQLAlchemy Core).

## 3. Dimensión de tipo 2: `dim_pasajero`

`dim_pasajero` conserva el **historial de cambios** en los atributos del
pasajero (`genero`, `edad`, `nacionalidad`) usando el patrón clásico de SCD
Tipo 2:

| Columna | Propósito |
|---|---|
| `pasajero_key` | Clave subrogada (PK), identifica una **versión** del pasajero |
| `passenger_id` | Clave de negocio (natural), identifica al pasajero real |
| `version` | Número de versión (1, 2, 3, …) |
| `fecha_inicio_validez` / `fecha_fin_validez` | Rango de vigencia de esa versión |
| `es_actual` | `1` si es la versión vigente, `0` si fue reemplazada |

**Lógica de carga (`cargar_dim_pasajero_scd2` en `etl_vuelos.py`):** para cada
`passenger_id` del lote de entrada, el ETL compara sus atributos contra la
versión vigente ya almacenada:
- Si el pasajero no existe → se inserta como **versión 1** (vigente).
- Si existe y **algún atributo cambió** → se cierra la versión anterior
  (`fecha_fin_validez` = fecha de carga, `es_actual = 0`) y se inserta una
  **nueva versión** (`version + 1`, `es_actual = 1`).
- Si existe y los atributos son idénticos → no se hace nada.

Con la carga inicial del dataset (cada `passenger_id` aparece una única vez
en el crudo), todos los pasajeros quedan en **versión 1**; la consulta #11
en `sql/02_consultas_analiticas.sql` lo confirma (cero pasajeros con más de
una versión). El mecanismo queda, sin embargo, completamente funcional: si
en una carga incremental futura llega el mismo `passenger_id` con un
`genero`, `edad` o `nacionalidad` distinto, el ETL generará automáticamente
una segunda versión histórica sin perder la anterior — que es justamente el
comportamiento que se espera de una dimensión Tipo 2.

## 4. Consultas analíticas

El archivo [`sql/02_consultas_analiticas.sql`](./sql/02_consultas_analiticas.sql)
contiene 12 consultas T-SQL que validan la carga y generan indicadores de
negocio. Resultados obtenidos al ejecutar el ETL sobre el dataset completo
(evidencia completa en
[`docs/evidencia_consultas_analiticas.txt`](./docs/evidencia_consultas_analiticas.txt)):

**Conteo de filas por tabla (validación de carga):**

| Tabla | Filas |
|---|---|
| dim_fecha | 731 |
| dim_aerolinea | 12 |
| dim_aeropuerto | 15 |
| dim_aeronave | 12 |
| dim_clase_cabina | 4 |
| dim_canal_venta | 6 |
| dim_metodo_pago | 5 |
| dim_estado_vuelo | 4 |
| dim_pasajero | 10,000 |
| **fact_vuelos** | **10,000** |

**Vuelos por estado:** ON_TIME 7,278 · DELAYED 1,970 · CANCELLED 560 · DIVERTED 192

**Top 5 destinos más frecuentes:** SAP (701) · CUN (699) · BOG (696) · BCN (696) · HAV (693)

**Distribución de pasajeros por género:** Masculino 49.12% · Femenino 46.98% ·
Otro/Prefiere no decir 3.46% · No binario 0.44%

**Ingreso total (USD) por clase de cabina:** Economy $499,766.74 (boleto
promedio $63.54) · Business $137,327.10 ($143.65) · Premium Economy
$87,062.70 ($89.39) · First $45,868.17 ($224.84)

*(el resto de las 12 consultas — top rutas, aerolíneas con más retrasos,
tendencia mensual, canal de venta vs. método de pago, nacionalidades y
equipaje promedio por aerolínea — se encuentran documentadas con su
resultado completo en el archivo de evidencia enlazado arriba).*

## 5. Despliegue / ejecución en local

### 5.1 Requisitos previos
- Python 3.10 o superior.
- Para conectar a **SQL Server**: una instancia accesible y el driver ODBC
  de Microsoft instalado en el sistema operativo (*Microsoft ODBC Driver 17
  o 18 for SQL Server*).
- Sin SQL Server disponible, el proyecto corre igualmente contra **SQLite**
  de forma local (no requiere instalar nada adicional) — ideal para probar
  la lógica del ETL antes de apuntar a SQL Server.

### 5.2 Pasos para ejecutar

```bash
cd SS22S2026_14G/Practica1

# 1. Crear y activar entorno virtual
python -m venv venv
# Windows
venv\Scripts\activate
# macOS / Linux
source venv/bin/activate

# 2. Instalar dependencias
pip install -r requirements.txt

# 3. (Opcional) crear el esquema en SQL Server ejecutando el script DDL
#    sql/01_create_schema_sqlserver.sql desde SSMS / Azure Data Studio,
#    apuntando a tu base de datos DW_Vuelos.

# 4. Configurar la conexion (ver .env.example)
#    Por defecto usa SQLite si no defines DB_URL.
export DB_URL="mssql+pyodbc://usuario:password@servidor/DW_Vuelos?driver=ODBC+Driver+17+for+SQL+Server"
#    En Windows (PowerShell): $env:DB_URL="mssql+pyodbc://..."

# 5. Ejecutar el ETL
cd etl
python etl_vuelos.py
```

Al finalizar, el script:
- Imprime en consola y guarda en `docs/evidencia_ejecucion_etl.txt` el log
  completo de las tres fases (extracción, transformación, carga).
- Crea (si no existen) todas las tablas del modelo dimensional en la base
  de datos indicada por `DB_URL`.
- Carga los 10,000 registros transformados en `fact_vuelos` y sus
  dimensiones asociadas.

Después, las consultas analíticas de
[`sql/02_consultas_analiticas.sql`](./sql/02_consultas_analiticas.sql)
pueden ejecutarse directamente desde SSMS / Azure Data Studio (si se usó
SQL Server) o adaptarse a `sqlite3` (si se usó el modo de prueba local).

### 5.3 Regenerar el diagrama del modelo (opcional)

```bash
cd diagrams
python generar_diagrama.py
```

Requiere tener instalado el binario `dot` de Graphviz en el sistema
(no solo el paquete de Python).

## 6. Requerimientos (`requirements.txt`)

```
pandas>=2.0
numpy>=1.24
SQLAlchemy>=2.0
pyodbc>=5.0        # solo necesario para conectar a SQL Server
graphviz>=0.20      # solo necesario para regenerar el diagrama
```

## 7. Estructura del repositorio

```
Practica1/
├── etl/
│   ├── etl_vuelos.py              # Script principal: extraccion, transformacion, carga
│   └── schema.py                  # Definicion del modelo (SQLAlchemy Core, agnostico de motor)
├── sql/
│   ├── 01_create_schema_sqlserver.sql   # DDL oficial del modelo dimensional (T-SQL)
│   └── 02_consultas_analiticas.sql      # 12 consultas de validacion e indicadores
├── diagrams/
│   ├── modelo_dimensional.png     # Diagrama del esquema estrella
│   └── generar_diagrama.py        # Script que genera el diagrama (graphviz)
├── data/
│   └── dataset_vuelos_crudo.csv   # Dataset original proporcionado
├── docs/
│   ├── evidencia_ejecucion_etl.txt          # Log real de una ejecucion completa del ETL
│   └── evidencia_consultas_analiticas.txt   # Resultado real de las 12 consultas analiticas
├── vuelos_dw.db                   # Base SQLite generada localmente (modo de prueba)
├── requirements.txt
├── .env.example
└── README.md                      # Este archivo
```
