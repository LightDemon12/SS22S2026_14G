# SG-Food: Pipeline ELT & Data Warehouse Moderno

## 👥 Integrantes del Grupo
* **Integrante 1:** Daniel Abraham Gálvez Solorzano - 202203361
* **Integrante 2:** [Nombre y Carné / Identificación]

---

## 📌 1. Descripción General y Arquitectura

El presente proyecto implementa un flujo de datos moderno bajo el paradigma **ELT (Extract, Load, Transform)** para la empresa de consumo masivo **SG-Food**. 

El objetivo es consolidar y transformar fuentes de datos heterogéneas (una base transaccional OLTP en PostgreSQL y múltiples archivos planos CSV externos) en un **Data Warehouse analítico centralizado con un Modelo Dimensional de Estrella**, totalmente orquestado mediante **Apache Airflow** y modelado con **dbt Core** a través de 4 capas estructuradas: **RAW**, **STAGING**, **INTERMEDIATE** y **MARTS**.

```
+----------------------------------------------------------------------------------------------------+
|                                      FUENTES DE DATOS                                              |
|  - PostgreSQL OLTP (oltp_sgfood): sucursal, categoria, marca, producto, cliente, venta, detalle   |
|  - Archivos CSV externos: inventario_bodega, proveedores_precios, promociones, metas, devoluciones  |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                                                  | 1. EXTRACT & LOAD (Python: Pandas + SQLAlchemy)
                                                  v
+-------------------------------------------------+--------------------------------------------------+
|                                    CAPA RAW / LANDING                                              |
|  - Esquema PostgreSQL: raw.* (Tablas persistentes)                                                 |
|  - Ingesta fiel a fuentes originales + Timestamp de auditoría (_extracted_at)                      |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                                                  | 2. CLEANSE & CAST (dbt Core - Staging)
                                                  v
+-------------------------------------------------+--------------------------------------------------+
|                                      CAPA STAGING (Vistas)                                         |
|  - Esquema PostgreSQL: staging.*                                                                   |
|  - Tipado estricto, estandarización snake_case, eliminación de espacios y filtros de nulos         |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                                                  | 3. BUSINESS LOGIC & JOINS (dbt Core - Intermediate)
                                                  v
+-------------------------------------------------+--------------------------------------------------+
|                                   CAPA INTERMEDIATE (Vistas)                                       |
|  - Esquema PostgreSQL: intermediate.*                                                              |
|  - Enriquecimiento de productos (int_productos_enriquecidos) y cruce ventas (int_ventas_detalladas) |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                                                  | 4. MODELO DE ESTRELLA (dbt Core - Marts)
                                                  v
+-------------------------------------------------+--------------------------------------------------+
|                                   CAPA ANALYTICS (Tablas Físicas)                                  |
|  - Esquema PostgreSQL: analytics.*                                                                 |
|  - Dimensiones: dim_clientes, dim_productos, dim_sucursales                                        |
|  - Hechos: fct_ventas (Métricas de venta bruta, descuentos, venta neta y márgenes)                |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                                                  | 5. DATA QUALITY TESTING (dbt test)
                                                  v
+-------------------------------------------------+--------------------------------------------------+
|  - Pruebas de unicidad (unique), no nulidad (not_null) e integridad referencial (relationships)   |
+----------------------------------------------------------------------------------------------------+
```

---

## 🗂️ 2. Estructura Completa del Repositorio

```text
Proyecto1/
├── docker-compose.yml              # Orquestación de contenedores (Airflow + PostgreSQL DW)
├── .env                            # Variables de entorno y credenciales
├── .env.example                    # Plantilla de variables de entorno
├── dw_ddl.sql                      # Script DDL completo (Schemas, Raw, Dimensiones, Hechos y PK/FKs)
├── init_raw_schema.sql             # Script DDL inicial montado en Docker
├── MANUAL_ELT.md                   # Manual detallado de metodología y convenciones del ELT
├── requirements.txt                # Dependencias de Python
├── data/                           # Datos fuente (OLTP .sql y CSVs externos)
│   ├── sgfood_oltp.sql
│   ├── catalogo_insumos_sgfood.xlsx
│   └── *.csv
├── dags/                           # Orquestación en Airflow
│   ├── sgfood_elt_pipeline.py      # DAG principal (BashOperator: Extract >> dbt run >> dbt test)
│   └── extract_load_raw.py         # Script Python de ingesta a la capa RAW
├── sgfood_dbt/                     # Proyecto de modelado dimensional con dbt Core
│   ├── dbt_project.yml             # Configuración de materializaciones (staging, intermediate, marts)
│   ├── profiles.yml                # Conexión a PostgreSQL (con soporte Docker y local)
│   └── models/
│       ├── staging/                # Vistas de limpieza básica (stg_*) y sources.yml
│       ├── intermediate/           # Vistas intermedias de negocio (int_*)
│       └── marts/                  # Tablas analíticas dimensionales (dim_*, fct_*) y marts.yml
└── sql/
    └── validation/                 # Scripts SQL dedicados para validación analítica y de calidad
        ├── 01_validate_raw_ingestion.sql
        ├── 02_validate_dimensional_model.sql
        ├── 03_business_analytical_queries.sql
        └── 04_data_quality_checks.sql
```

---

## 🛠️ 3. Desglose de las 4 Capas del Data Warehouse

| Capa | Esquema | Materialización dbt | Propósito y Modelos |
| :--- | :--- | :--- | :--- |
| **RAW** | `raw` | Tablas persistentes (Python) | Réplica 1:1 inmutable de las fuentes con columna `_extracted_at`. Ingesta idempotente con `TRUNCATE + INSERT`. |
| **STAGING** | `staging` | `view` (Vistas) | Limpieza inicial, casteo de tipos, `TRIM` en strings y filtrado de llaves nulas (`stg_clientes`, `stg_productos`, `stg_categorias`, `stg_marcas`, `stg_sucursales`, `stg_ventas`, `stg_ventas_detalle`). |
| **INTERMEDIATE** | `intermediate` | `view` (Vistas) | Transformaciones y joins intermedios de negocio:<br>• `int_productos_enriquecidos`: Une productos con categoría/marca y calcula margen unitario.<br>• `int_ventas_detalladas`: Cruza cabecera y detalle de ventas y calcula importes brutos, descuentos y neto. |
| **MARTS** | `analytics` | `table` (Tablas Físicas) | **Modelo de Estrella (Kimball)** optimizado para consultas de BI:<br>• `dim_clientes`, `dim_productos`, `dim_sucursales`<br>• `fct_ventas` |

---

## 🏛️ 4. Modelo Dimensional de Estrella (Marts)

```
                       +-------------------+
                       |   dim_clientes    |
                       +-------------------+
                       | PK id_cliente     |
                       |    nombre_cliente |
                       |    tipo_cliente   |
                       |    municipio      |
                       |    departamento   |
                       |    fecha_alta     |
                       +---------+---------+
                                 |
                                 | 1:N
                                 v
+-------------------+  N:1  +-----------------------+  1:N  +-------------------+
|  dim_sucursales   |<------+       fct_ventas      +------>|   dim_productos   |
+-------------------+       +-----------------------+       +-------------------+
| PK id_sucursal    |       | PK id_detalle         |       | PK id_producto    |
|    nombre_sucursal|       | FK id_venta           |       |    sku            |
|    ciudad         |       | FK id_cliente         |       |    nombre_producto|
|    departamento   |       | FK id_producto        |       |    categoria      |
+-------------------+       | FK id_sucursal        |       |    marca          |
                            |    fecha_venta        |       |    unidad_medida  |
                            |    canal_venta        |       |    costo_base     |
                            |    metodo_pago        |       |    precio_lista   |
                            |    cantidad           |       |    margen_unitario|
                            |    precio_unitario    |       +-------------------+
                            |    porcentaje_descto  |
                            |    monto_bruto        |
                            |    monto_descuento    |
                            |    monto_neto         |
                            +-----------------------+
```

---

## ⚙️ 5. Orquestación con Apache Airflow

El DAG [`sgfood_elt_pipeline`](file:///c:/Users/engel/Documents/GitHub/SS22S2026_14G/Proyecto1/dags/sgfood_elt_pipeline.py) conecta todo el flujo de extremo a extremo mediante 3 tareas estrictamente secuenciales con `BashOperator`:

```
[ extract_and_load_raw ]  --->  [ dbt_transformation_run ]  --->  [ dbt_quality_tests ]
```

1. **`extract_and_load_raw`:** Ejecuta `python /opt/airflow/dags/extract_load_raw.py` para extraer del OLTP y CSVs hacia `raw.*`.
2. **`dbt_transformation_run`:** Ejecuta `cd /opt/airflow/sgfood_dbt && python -m dbt.cli.main run --profiles-dir .` construyendo `staging`, `intermediate` y `analytics`.
3. **`dbt_quality_tests`:** Ejecuta `cd /opt/airflow/sgfood_dbt && python -m dbt.cli.main test --profiles-dir .` validando pruebas de unicidad, no nulidad y llaves foráneas.

---

## 🚀 6. Manual de Implementación y Ejecución Paso a Paso

### Prerrequisitos
* **Docker Desktop** activo.
* Puertos libres: `5432` (PostgreSQL) y `8080` (Airflow).

---

### Paso 1: Levantar los Contenedores
Abre tu terminal en la carpeta `Proyecto1`:
```bash
docker-compose up -d
```
> **Nota:** La primera vez, Airflow descargará las dependencias de `_PIP_ADDITIONAL_REQUIREMENTS` (`pandas`, `sqlalchemy`, `dbt-postgres`). Esto toma alrededor de 1-2 minutos.

### Paso 2: Verificar el Estado de los Servicios
```bash
docker-compose ps
```
Los 5 contenedores deben estar en estado `Up` o `Healthy`.

---

### Paso 3: Ejecutar el DAG en la Interfaz Web de Airflow
1. Ingresa a: **[http://localhost:8080](http://localhost:8080)**
2. Credenciales: **Usuario:** `admin` | **Contraseña:** `admin`
3. En la lista de DAGs, busca **`sgfood_elt_pipeline`**.
4. Enciende el interruptor (**Toggle ON**) y presiona el botón **Trigger DAG** (▶️).
5. Observa en la vista **Grid** o **Graph** cómo las 3 tareas finalizan en verde (`success`).

---

### Paso 4: Validación y Consultas Analíticas en PostgreSQL
Conéctate a PostgreSQL con cualquier cliente (DBeaver, DataGrip, pgAdmin o terminal):
* **Host:** `localhost` | **Port:** `5432` | **Database:** `sgfood_db` | **User:** `admin` | **Password:** `admin`

Ejecuta los scripts ubicados en `sql/validation/`:
* [`sql/validation/01_validate_raw_ingestion.sql`](file:///c:/Users/engel/Documents/GitHub/SS22S2026_14G/Proyecto1/sql/validation/01_validate_raw_ingestion.sql): Verifica el conteo de filas de todas las tablas cargadas en `raw`.
* [`sql/validation/02_validate_dimensional_model.sql`](file:///c:/Users/engel/Documents/GitHub/SS22S2026_14G/Proyecto1/sql/validation/02_validate_dimensional_model.sql): Valida conteos de dimensiones/hechos y comprueba que no existan registros huérfanos.
* [`sql/validation/03_business_analytical_queries.sql`](file:///c:/Users/engel/Documents/GitHub/SS22S2026_14G/Proyecto1/sql/validation/03_business_analytical_queries.sql): Consultas de negocio (Ventas por categoría, por sucursal y Top 10 clientes).
* [`sql/validation/04_data_quality_checks.sql`](file:///c:/Users/engel/Documents/GitHub/SS22S2026_14G/Proyecto1/sql/validation/04_data_quality_checks.sql): Chequeos de consistencia matemática y unicidad de llaves primarias.

---

## 🧹 7. Detener y Reiniciar el Entorno
```bash
# Detener contenedores
docker-compose down

# Reiniciar desde cero limpiando volúmenes
docker-compose down -v
docker-compose up -d
```
