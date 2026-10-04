# SG-Food: Pipeline ELT & Data Warehouse Moderno

##  Integrantes del Grupo
* **Integrante 1:** 202200314 - Engel Emilio Coc Raxjal
* **Integrante 2:** 202203361 - Daniel Abraham Gálvez Solorzano

---

##  1. Descripción General y Arquitectura

El presente proyecto implementa un flujo de datos moderno bajo el paradigma **ELT (Extract, Load, Transform)** para la empresa ficticia de consumo masivo **SG-Food**. 

El objetivo es consolidar y procesar fuentes de datos heterogéneas (una base transaccional OLTP en PostgreSQL y múltiples archivos planos CSV externos) en un **Data Warehouse analítico centralizado con un Modelo Dimensional de Estrella**, totalmente orquestado mediante **Apache Airflow** y modelado/testeado con **dbt Core**.

```
+----------------------------------------------------------------------------------------------------+
|                                      FUENTES DE DATOS                                              |
|  - PostgreSQL OLTP (oltp_sgfood): sucursal, categoria, marca, producto, cliente, venta, detalle   |
|  - Archivos CSV externos: inventario_bodega, proveedores_precios, promociones, metas, devoluciones  |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                                                  | FASE 1: Ingesta RAW (Python + SQLAlchemy)
                                                  v
+-------------------------------------------------+--------------------------------------------------+
|                                    CAPA RAW / LANDING                                              |
|  - Esquema PostgreSQL: raw.*                                                                       |
|  - Ingesta fiel a fuentes originales + Metadatos de auditoría (_extracted_at)                      |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                                                  | FASE 2: dbt Core (Staging)
                                                  v
+-------------------------------------------------+--------------------------------------------------+
|                                      CAPA STAGING (Vistas)                                         |
|  - Esquema PostgreSQL: staging.*                                                                   |
|  - Tipado estricto, estandarización snake_case, limpieza de espacios y filtros de integridad      |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                                                  | FASE 2: dbt Core (Marts - Modelo de Estrella)
                                                  v
+-------------------------------------------------+--------------------------------------------------+
|                                   CAPA ANALYTICS (Tablas Físicas)                                  |
|  - Esquema PostgreSQL: analytics.*                                                                 |
|  - Dimensiones: dim_clientes, dim_productos, dim_sucursales                                        |
|  - Hechos: fct_ventas (Métricas de venta bruta, descuentos, venta neta y márgenes)                |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                                                  | FASE 3: Orquestación & Testing (Apache Airflow)
                                                  v
+-------------------------------------------------+--------------------------------------------------+
|  - DAG: sgfood_elt_pipeline (extract_and_load_raw >> dbt_transformation_run >> dbt_quality_tests) |
+----------------------------------------------------------------------------------------------------+
```

---

##  2. Desglose de las 3 Fases del Proyecto

### 🔹 Fase 1: Infraestructura Base, Capa RAW y Extracción con Python
* **Base de Datos Transaccional (OLTP):**
  * Script inicial `data/sgfood_oltp.sql` montado en `/docker-entrypoint-initdb.d/` para crearse automáticamente al levantar el contenedor de PostgreSQL. Contiene las tablas operacionales: `sucursal`, `categoria`, `marca`, `producto`, `cliente`, `venta` y `venta_detalle`.
* **Fuentes Externas (CSV):**
  * Archivos planos complementarios ubicados en `data/`: `inventario_bodega.csv`, `proveedores_precios.csv`, `promociones.csv`, `metas_ventas.csv`, `devoluciones.csv` y `casos_calidad_opcionales.csv`.
* **DDL de la Capa RAW (`init_raw_schema.sql`):**
  * Crea el esquema `raw` y las tablas receptoras sin restricciones rígidas de integridad referencial (para permitir una ingesta elástica) e incluye una columna técnica `_extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP` para trazabilidad y auditoría.
* **Script de Extracción y Carga (`dags/extract_load_raw.py`):**
  * Desarrollado en Python con `pandas` y `SQLAlchemy`.
  * Extrae todas las tablas transaccionales del esquema `oltp_sgfood` y los archivos CSV de `data/`.
  * Realiza limpieza técnica básica (conversión a `snake_case`, eliminación de espacios en blanco y casteo de fechas).
  * Es **idempotente**: aplica `TRUNCATE TABLE` antes de insertar los registros con `to_sql(method='multi', chunksize=1000)`.

---

### 🔹 Fase 2: Modelado Dimensional y Calidad con dbt Core
Dentro de la carpeta `sgfood_dbt/` se estructuró el proyecto dbt:

1. **Configuración (`dbt_project.yml` y `profiles.yml`):**
   * Configuración de materializaciones: la capa `staging` se materializa como **vistas (`view`)** y la capa `marts` como **tablas físicas (`table`)**.
   * Conexión dinámica a PostgreSQL mediante variables de entorno en `profiles.yml` (`postgres_dw` en Docker o `localhost` en local).
2. **Definición de Fuentes (`models/staging/sources.yml`):**
   * Mapeo formal de todas las tablas del esquema `raw`.
3. **Capa Staging (`models/staging/`):**
   * `stg_clientes.sql`, `stg_productos.sql`, `stg_categorias.sql`, `stg_marcas.sql`, `stg_sucursales.sql`, `stg_ventas.sql` y `stg_ventas_detalle.sql`.
   * Estandarización de tipos, nombres de columnas descriptivos y filtros de nulos en llaves primarias.
4. **Capa Marts / Modelo Dimensional de Estrella (`models/marts/`):**
   * **`dim_clientes.sql`**: Atributos descriptivos y segmentación de clientes.
   * **`dim_productos.sql`**: Dimensión de productos desnormalizada y enriquecida con `categoria` y `marca`, calculando el `margen_unitario_teorico`.
   * **`dim_sucursales.sql`**: Sucursales físicas y ubicación geográfica.
   * **`fct_ventas.sql`**: Tabla de hechos a nivel de detalle de venta (`id_detalle`), vinculada a las 3 dimensiones y calculando métricas como `monto_bruto`, `monto_descuento` y `monto_neto`.
5. **Pruebas de Calidad Automatizadas (`models/marts/marts.yml`):**
   * Pruebas nativas de dbt: `unique`, `not_null` y `relationships` (verificación de integridad referencial entre la tabla de hechos y las tres dimensiones).

---

### 🔹 Fase 3: Orquestación con Apache Airflow y Dockerización Unificada
* **Entorno Docker Unificado (`docker-compose.yml`):**
  * Integra en la misma red (`sgfood_net`) el Data Warehouse (`postgres_dw`), la base de datos de Airflow (`postgres_airflow`), el Webserver y el Scheduler.
  * Inyección de librerías en tiempo de arranque mediante `_PIP_ADDITIONAL_REQUIREMENTS=pandas sqlalchemy psycopg2-binary dbt-postgres`.
  * Gestión centralizada de credenciales mediante el archivo `.env`.
* **DAG de Airflow (`dags/sgfood_elt_pipeline.py`):**
  * Utiliza `BashOperator` para coordinar un flujo secuencial:
    ```
    [ extract_and_load_raw ]  --->  [ dbt_transformation_run ]  --->  [ dbt_quality_tests ]
    ```
  * Tarea 1: Ejecuta `extract_load_raw.py` para poblar el esquema `raw`.
  * Tarea 2: Ejecuta `dbt run` para construir las vistas de `staging` y las tablas de `analytics`.
  * Tarea 3: Ejecuta `dbt test` para certificar la calidad e integridad del modelo.

---

##  4. Modelo Dimensional de Estrella (Marts)

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

##  5. Justificación del Diseño e Ingeniería

1. **Enfoque ELT vs. ETL Tradicional:**
   * Al cargar los datos directamente a la capa `raw` en su formato original, se preserva el histórico completo de los datos fuente. Las transformaciones se delegan a PostgreSQL mediante dbt, lo que permite refactorizar la lógica analítica sin tener que volver a extraer datos del sistema operacional.
2. **dbt Core para la Lógica de Negocio:**
   * Introduce buenas prácticas de ingeniería de software al SQL (control de versiones, linaje automático, documentación y testing continuo).
3. **Optimización de Almacenamiento y Rendimiento:**
   * `staging` usa **vistas** para no duplicar datos intermedios.
   * `marts` (`analytics`) usa **tablas físicas** para garantizar tiempos de respuesta rápidos en dashboards y consultas BI.
4. **Infraestructura Reproducible:**
   * Gracias a Docker Compose y la red compartida, cualquier desarrollador o docente puede clonar el repositorio y ejecutar el pipeline completo con un solo comando.

---

##  6. Manual de Implementación y Ejecución Paso a Paso

### Prerrequisitos
* **Docker Desktop** instalado y en ejecución.
* **Git** instalado.
* Puertos libres en tu máquina: `5432` (PostgreSQL DW) y `8080` (Airflow Web).

---

### Paso 1: Clonar y Ubicarse en la Carpeta del Proyecto
```bash
cd Proyecto1
```

---

### Paso 2: Levantar el Entorno Completo con Docker Compose
Ejecuta:
```bash
docker-compose up -d
```

>  **Nota:** En la primera ejecución, Airflow descargará las imágenes oficiales e instalará automáticamente `dbt-postgres`, `pandas` y `SQLAlchemy`. Esto puede tardar entre 1 y 3 minutos según tu velocidad de internet.

---

### Paso 3: Verificar que los Contenedores Estén Saludables
Ejecuta:
```bash
docker-compose ps
```

Deberás ver activos los 5 servicios:
* `sgfood_postgres_dw` (PostgreSQL 15 - Data Warehouse & Fuentes)
* `sgfood_postgres_airflow` (PostgreSQL 13 - Metadatos de Airflow)
* `sgfood_airflow_init` (Inicializador)
* `sgfood_airflow_webserver` (UI de Airflow)
* `sgfood_airflow_scheduler` (Planificador de tareas)

---

### Paso 4: Acceder a Airflow y Ejecutar el Pipeline
1. Abre tu navegador e ingresa a: **[http://localhost:8080](http://localhost:8080)**
2. Inicia sesión con:
   * **Usuario:** `admin`
   * **Contraseña:** `admin`
3. En la lista principal de DAGs, busca **`sgfood_elt_pipeline`**.
4. Enciende el interruptor (**Toggle ON**) a la izquierda del DAG.
5. Haz clic en el botón **Trigger DAG** (ícono de reproducir ▶️ en la parte derecha) para iniciar la ejecución manual.

---

### Paso 5: Monitoreo y Verificación de Tareas
1. Haz clic sobre el nombre del DAG **`sgfood_elt_pipeline`** y entra a la vista **Grid** o **Graph**.
2. Verás cómo las tres tareas se ejecutan en secuencia y finalizan exitosamente en color verde (`success`):
   * `extract_and_load_raw` 🟩
   * `dbt_transformation_run` 🟩
   * `dbt_quality_tests` 🟩
3. Puedes hacer clic en cualquiera de las tareas y pulsar en **Logs** para auditar el detalle de cada proceso.

---

### Paso 6: Validación de Datos en PostgreSQL DW
Conéctate al motor de base de datos desde DBeaver, pgAdmin o terminal:
* **Host:** `localhost`
* **Puerto:** `5432`
* **Base de datos:** `sgfood_db`
* **Usuario:** `admin`
* **Contraseña:** `admin`

#### Consultas SQL de Validación Sugeridas:

```sql
-- 1. Validar registros cargados en la capa RAW
SELECT count(*) AS total_clientes_raw FROM raw.cliente;
SELECT count(*) AS total_ventas_raw FROM raw.venta;
SELECT count(*) AS total_inventario_raw FROM raw.inventario_bodega;

-- 2. Consultar las dimensiones creadas por dbt
SELECT * FROM analytics.dim_clientes LIMIT 5;
SELECT * FROM analytics.dim_productos LIMIT 5;
SELECT * FROM analytics.dim_sucursales LIMIT 5;

-- 3. Consultar la tabla de hechos con métricas calculadas
SELECT * FROM analytics.fct_ventas LIMIT 10;

-- 4. Consulta Analítica de Negocio: Rendimiento de Ventas por Categoría
SELECT 
    p.categoria,
    COUNT(f.id_detalle) AS transacciones,
    SUM(f.cantidad) AS unidades_vendidas,
    SUM(f.monto_bruto) AS venta_bruta_total,
    SUM(f.monto_descuento) AS total_descuentos_otorgados,
    SUM(f.monto_neto) AS venta_neta_total,
    ROUND(AVG(f.porcentaje_descuento) * 100, 2) AS promedio_descuento_pct
FROM analytics.fct_ventas f
JOIN analytics.dim_productos p ON f.id_producto = p.id_producto
GROUP BY p.categoria
ORDER BY venta_neta_total DESC;
```

---

##  7. Detener y Reiniciar el Entorno

* **Detener los servicios manteniendo los datos:**
  ```bash
  docker-compose down
  ```

* **Detener y reiniciar desde cero limpiando todos los volúmenes:**
  ```bash
  docker-compose down -v
  docker-compose up -d
  ```
