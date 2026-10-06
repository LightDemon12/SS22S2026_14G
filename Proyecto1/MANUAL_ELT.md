# Manual de Metodología, Convenciones y Diseño del Pipeline ELT (SG-Food)

Este documento detalla los estándares de ingeniería de datos, convenciones de nomenclatura, arquitectura dimensional y decisiones técnicas adoptadas en la implementación del flujo **ELT (Extract, Load, Transform)** de **SG-Food**.

---

## 1. Convenciones de Nomenclatura y Estándares de Código

### 1.1 Estándares Generales
* **Formato de identificadores:** Todo identificador de base de datos (esquemas, tablas, columnas) y archivos `.sql` debe estar en `snake_case` estricto, minúsculas, sin tildes ni caracteres especiales.
* **Prefijos por Capa de Modelado:**
  * `raw.<tabla>`: Tablas crudas de ingesta directa.
  * `stg_<fuente>_<entidad>` o `stg_<entidad>`: Vistas de la capa **Staging**.
  * `int_<entidad>_<accion>`: Vistas de la capa **Intermediate**.
  * `dim_<entidad>`: Tablas de **Dimensiones** en la capa Marts (`analytics`).
  * `fct_<proceso>`: Tablas de **Hechos (Facts)** en la capa Marts (`analytics`).

### 1.2 Reglas para Columnas y Tipos de Datos
* **Llaves Primarias (PK):** Nombradas con el prefijo `id_` seguido de la entidad (ej. `id_cliente`, `id_producto`, `id_detalle`).
* **Llaves Foráneas (FK):** Deben coincidir exactamente con el nombre de la llave primaria a la que referencian en la dimensión correspondiente (ej. `id_cliente` en `fct_ventas` referencia a `id_cliente` en `dim_clientes`).
* **Campos Booleanos:** Prefijados con `es_` o `tiene_` (ej. `es_activo`).
* **Campos Monetarios y Métricas:** Nombradas explícitamente con prefijo `monto_`, `precio_`, `costo_` o `porcentaje_` y tipados como `NUMERIC(12, 2)` o `NUMERIC(14, 2)`.
* **Metadatos de Auditoría:** Toda tabla en la capa `raw` debe incluir `_extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP` para conocer con precisión el instante de ingesta.

---

## 2. Arquitectura de Modelado por Capas (dbt Core)

```
[ Fuentes: OLTP + CSVs ] 
           │
           ▼ (Python: Pandas + SQLAlchemy)
   ┌───────────────┐
   │   Capa RAW    │  -> Esquema 'raw' (Tablas Físicas)
   └───────┬───────┘
           │
           ▼ (dbt: {{ source() }})
   ┌───────────────┐
   │ Capa STAGING  │  -> Esquema 'staging' (Vistas)
   └───────┬───────┘
           │
           ▼ (dbt: {{ ref() }})
   ┌───────────────┐
   │ Capa INTERMED │  -> Esquema 'intermediate' (Vistas)
   └───────┬───────┘
           │
           ▼ (dbt: {{ ref() }})
   ┌───────────────┐
   │  Capa MARTS   │  -> Esquema 'analytics' (Tablas Físicas)
   └───────────────┘
```

### Detalle de Responsabilidades por Capa:

1. **Capa RAW (`raw.*`):**
   * Almacena réplicas 1:1 de los orígenes de datos.
   * Sin validaciones destructivas ni restricciones de llaves foráneas estrictas, para evitar caídas del pipeline de ingesta ante datos mal formateados.
   * La extracción es **idempotente** (aplica `TRUNCATE TABLE` antes de insertar).

2. **Capa STAGING (`staging.*`):**
   * Declarada como vistas (`materialized: view`) para no duplicar espacio en disco.
   * **Objetivo:** Limpieza básica de tipos de datos, casteo explícito (`CAST`), eliminación de espacios en blanco (`TRIM`), manejo de nulos (`COALESCE`) y filtrado de registros corruptos (sin PK).

3. **Capa INTERMEDIATE (`intermediate.*`):**
   * Declarada como vistas (`materialized: view`).
   * **Objetivo:** Resolver transformaciones y cruces lógicos complejos entre múltiples tablas de staging antes de exponerlas a negocio.
   * *Ejemplo 1:* `int_productos_enriquecidos.sql` une `stg_productos` con `stg_categorias` y `stg_marcas`, y calcula el `margen_unitario_teorico`.
   * *Ejemplo 2:* `int_ventas_detalladas.sql` une la cabecera `stg_ventas` con el detalle `stg_ventas_detalle`, computando `monto_bruto`, `monto_descuento` y `monto_neto`.

4. **Capa MARTS / Analytics (`analytics.*`):**
   * Declarada como tablas físicas (`materialized: table`) para máxima velocidad de consulta y soporte a dashboards de BI.
   * Implementa el **Modelo Dimensional de Estrella (Kimball)**:
     * `dim_clientes`: Atributos descriptivos de clientes y segmentación geográfica.
     * `dim_productos`: Catálogo consolidado con categoría y marca.
     * `dim_sucursales`: Puntos de venta físicos.
     * `fct_ventas`: Grano más fino de transacción (línea de detalle de venta).

---

## 3. Pruebas de Calidad de Datos (Data Quality)

En `models/marts/marts.yml` se definieron pruebas automáticas ejecutadas en cada ciclo de Airflow:

| Prueba dbt | Tipo | Aplicado en | Propósito |
| :--- | :--- | :--- | :--- |
| `unique` | Integridad | Todas las PKs (`id_cliente`, `id_producto`, `id_sucursal`, `id_detalle`) | Garantizar que no existan duplicados. |
| `not_null` | Completitud | PKs y métricas críticas (`monto_neto`, `cantidad`, `fecha_venta`) | Evitar registros vacíos o métricas nulas. |
| `relationships` | Integridad Referencial | `fct_ventas.id_cliente` -> `dim_clientes.id_cliente`<br>`fct_ventas.id_producto` -> `dim_productos.id_producto`<br>`fct_ventas.id_sucursal` -> `dim_sucursales.id_sucursal` | Garantizar que no existan hechos huérfanos. |

---

## 4. Orquestación y Resiliencia con Apache Airflow

* **DAG:** `sgfood_elt_pipeline`
* **Operadores:** `BashOperator`
* **Políticas de Reintento:** `retries=1`, `retry_delay=timedelta(minutes=2)`
* **Secuencia Estricta:**
  $$\text{extract\_and\_load\_raw} \longrightarrow \text{dbt\_transformation\_run} \longrightarrow \text{dbt\_quality\_tests}$$
* **Aislamiento:** Si la extracción en Python falla, dbt no se ejecuta. Si `dbt run` falla, las pruebas no se ejecutan y el DAG se marca en estado `FAILED` con alertas en los logs.
