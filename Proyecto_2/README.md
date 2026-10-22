# Proyecto 2: Procesamiento y Análisis Exploratorio de Datos Masivos en BigQuery

**Seminario de Sistemas 2 — Segundo Semestre 2026**  
**Facultad de Ingeniería — Universidad de San Carlos de Guatemala**  
**Grupo / Pareja 14**  

### Integrantes:
* **Daniel Gálvez** — Carné: `202203361`
* **Engel Coc** — Carné: `202200314`

---

## 1. Descripción del Proyecto y Objetivos

El presente proyecto implementa un pipeline integral de ingeniería, optimización y analítica avanzada sobre datos masivos (*Big Data*) en la nube de **Google Cloud Platform (GCP)** utilizando **Google BigQuery**, **BigQuery ML (BQML)** y **Looker Studio**.

### 1.1. Objetivo General (SMART)
Diseñar, implementar y evaluar un flujo analítico escalable sobre el dataset público de viajes en taxi de la Ciudad de Nueva York (**NYC TLC Yellow Trips 2022**), aplicando técnicas formales de limpieza, tipado de datos, optimización física mediante **particionado diario** y **clustering geográfico**, entrenamiento de modelos predictivos de Machine Learning y Forecasting temporal con prevención rigurosa de *Data Leakage*, y comunicando los hallazgos a través de un panel interactivo en Looker Studio.

### 1.2. Descripción y Cobertura del Dataset
* **Fuente Oficial:** `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`
* **Volumen Total:** 36,256,539 registros de viajes individuales (supera ampliamente el requisito de 1 millón de registros de la rúbrica 9.1).
* **Tamaño Lógico:** ~6.97 GB sin procesar.
* **Cobertura Temporal:** 365 días del año 2022 (del 1 de enero al 31 de diciembre de 2022).
* **Entorno de Trabajo:** GCP Project ID: `ss2-2026-pareja14-v2`, Dataset: `taxi_ss2_2026` (Región: `US`).

---

## 2. Exploración y Diagnóstico de Calidad Inicial

Antes de aplicar cualquier transformación, se documentó el esquema real del dataset y se ejecutó un perfilado de calidad en una sola pasada para cuantificar anomalías.

![Esquema y Columnas en BigQuery](evidencias/evidencia_01_schema.png)
*Figura 1: Estructura de columnas y tipos de datos del dataset público.*

![Volumen de Registros](evidencias/evidencia_02_volumen.png)
*Figura 2: Conteo de 36,256,539 registros con 0 bytes leídos vía metadatos.*

![Cobertura Temporal](evidencias/evidencia_02_cobertura.png)
*Figura 3: Ventana temporal del 01/01/2022 al 31/12/2022 cubriendo los 365 días.*

![Perfil de Calidad de Datos](evidencias/evidencia_03_perfil_row_view.png)
*Figura 4: Perfilado de calidad integral: nulos, duraciones anómalas y códigos fuera de catálogo.*

---

## 3. Limpieza y Transformaciones: Reglas de Negocio (L1 a L6)

En el script [sql/02_transformaciones/04_metricas.sql](file:///C:/Users/engel/Documents/GitHub/SS22S2026_14G/Proyecto_2/sql/02_transformaciones/04_metricas.sql) se materializó la tabla de hechos limpia baseline (`fact_trips_std`), aplicando 6 reglas de filtrado y saneamiento fundamentadas en la regulación de la TLC en NYC:

1. **L1 — Coherencia Temporal del Servicio:**  
   `dropoff_datetime > pickup_datetime` y duración neta entre 1 y 240 minutos ($1 \le \text{minutos} \le 240$). Se eliminan viajes con reloj desincronizado (duración negativa o cero) y viajes de más de 4 horas por taxímetros olvidados.
2. **L2 — Límites Físicos y de Distancia Plausible:**  
   `trip_distance BETWEEN 0.1 AND 100` (en millas). Filtra servicios sin desplazamiento GPS (< 0.1 mi) que representan cancelaciones, y valores extremos físicamente imposibles (> 100 mi).
3. **L3 — Capacidad Real de Pasajeros:**  
   `passenger_count BETWEEN 1 AND 9`. Remueve registros con 0 pasajeros y anomalías superiores a 9 pasajeros.
4. **L4 — Consistencia Económica y Tarifa Mínima Legal:**  
   `fare_amount BETWEEN 2.5 AND 500` y `total_amount BETWEEN 2.5 AND 1000`. La tarifa mínima legal al subir la bandera en NYC es de \$2.50 USD.
5. **L5 — Coherencia Contable Aditiva:**  
   `total_amount >= fare_amount`. El cobro final jamás puede ser menor a la tarifa base del taxímetro.
6. **L6 — Integridad Geográfica y Saneamiento de Tipos (Doble Casting):**  
   `pickup_location_id BETWEEN 1 AND 265`, `dropoff_location_id BETWEEN 1 AND 265`.  
   *Casting Crítico:* Columnas como `vendor_id`, `rate_code` y `payment_type` se publican como texto decimal (`'1.0'`). Se aplicó doble casting seguro:
   $$\text{SAFE\_CAST}(\text{SAFE\_CAST}(\text{columna} \text{ AS FLOAT64}) \text{ AS INT64})$$

### 3.1. Tasa de Retención de Datos
![Tasa de Retención de Datos](evidencias/evidencia_04_retencion.png)
*Figura 5: Validación de retención: 33,377,653 filas limpias conservadas (92.06% de retención).*

* **Registros Públicos Iniciales:** 36,256,539
* **Registros Limpios Finales:** 33,377,653
* **Registros Descartados:** 2,878,886 (7.94% depurado)
* **Tasa de Retención:** **92.06%**

### 3.2. Métricas Descriptivas Globales
![Métricas Descriptivas Globales](evidencias/evidencia_04_metricas_globales.png)
*Figura 6: Estadísticos descriptivos del universo limpio de viajes.*

* **Tarifa Promedio:** \$14.31 USD (Desviación: \$12.84, Mediana p50: \$10.00)
* **Distancia Promedio:** 3.52 millas (Mediana p50: 1.90 mi, p95: 15.25 mi)
* **Duración Promedio:** 15.13 minutos (p95: 39 minutos)
* **Velocidad Promedio:** 12.79 mph (refleja el tráfico denso de Manhattan)
* **Ratio de Propina Promedio:** 20.89%
* **Importe Total Promedio:** \$21.13 USD

---

## 4. Arquitectura y Optimización Física en BigQuery

Se compararon dos arquitecturas físicas sobre el mismo universo de datos limpios:

### 4.1. Tabla Estándar Baseline (`fact_trips_std`)
* Tabla plana sin particiones (`PARTITIONS = 1` anónima) y sin clustering. Requiere *Full Table Scan* en cada consulta.

![Estado Físico Tabla Estándar](evidencias/evidencia_05_std_sin_particiones.png)
*Figura 7: Certificación de tabla estándar plana (1 partición anónima).*

### 4.2. Tabla Optimizada (`fact_trips_opt`)
* Materializada en [sql/03_optimizacion/06_tabla_opt.sql](file:///C:/Users/engel/Documents/GitHub/SS22S2026_14G/Proyecto_2/sql/03_optimizacion/06_tabla_opt.sql).
* **Particionamiento:** `PARTITION BY pickup_date` (Granularidad diaria: 365 particiones).
  * Permite el podado exacto de particiones (*partition pruning*) en filtros de fechas.
* **Clustering:** `CLUSTER BY pickup_location_id, dropoff_location_id`.
  * Agrupa físicamente bloques por zonas de origen y destino, permitiendo el salto de bloques (*block pruning*).

![Detalles de Clustering en Consola](evidencias/evidencia_06_details_clustering.png)
*Figura 8: Propiedades de la tabla fact_trips_opt mostrando partición diaria y clustering geográfico.*

![Verificación de Particiones Diarias](evidencias/evidencia_06_particiones.png)
*Figura 9: 365 particiones generadas exitosamente (una por cada día del año).*

---

## 5. Comparativa de Rendimiento: Benchmark Real (Estándar vs. Optimizada)

En el script [sql/03_optimizacion/07_benchmark.sql](file:///C:/Users/engel/Documents/GitHub/SS22S2026_14G/Proyecto_2/sql/03_optimizacion/07_benchmark.sql) se ejecutó el protocolo de benchmark auditando directamente el historial de jobs en `region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`:

![Benchmark Completo](evidencias/evidencia_07_benchmark_completo.png)
*Figura 10: Resultados auditaibles del benchmark extraídos del historial de jobs de BigQuery.*

### Tabla Comparativa de Resultados del Benchmark:

| Prueba | Operación Analítica | Bytes Estándar | Bytes Optimizada | MB Estándar | MB Optimizada | **Reducción de Bytes (%)** | Tiempo Estándar |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **B1** | Filtro Temporal (Marzo 2022) | 534,042,448 | 53,651,408 | 509.3 MB | 51.2 MB | **89.95 %** | 376 ms |
| **B2** | Rango Temporal (3 meses) + 10 Zonas | 1,068,084,896 | 289,961,024 | 1,018.6 MB | 276.5 MB | **72.85 %** | 299 ms |
| **B3** | Ruta Aeropuerto JFK (Zona 132) | 1,068,084,896 | 84,479,584 | 1,018.6 MB | 80.6 MB | **92.09 %** | 388 ms |
| **B4** | Agregación Semanal (Ene-Feb) | 801,063,672 | 120,791,424 | 764.0 MB | 115.2 MB | **84.92 %** | 310 ms |
| **B5** | Column Pruning (SELECT * vs 2 cols) | 13,963,528 | 1,642,768 | 13.3 MB | 1.6 MB | **88.24 %** | 224 ms |

> **Conclusión de Optimización:** El particionamiento diario y el clustering lograron reducciones de entre **72.85% y 92.09%** de bytes procesados, optimizando directamente los costos en la nube.

---

## 6. Machine Learning en BigQuery ML (BQML)

### 6.1. Prevención Rigurosa de Data Leakage
* **Split Temporal:** En datos de movilidad, el split aleatorio (*random split*) provoca que el modelo entrene con el futuro (diciembre) y evalúe con el pasado (marzo). Se estableció un split temporal estricto:
  * **TRAIN (78%):** Viajes previos al 16-Sep-2022 (~26.04 M filas).
  * **EVAL (13%):** Viajes del 16-Sep al 31-Oct-2022 (~4.48 M filas).
  * **TEST Holdout (9%):** Viajes del 01-Nov al 31-Dic-2022 (~2.85 M filas).
* **Exclusión de Variables Fuga:** Se excluyó `total_amount` (suma aditiva que contiene la tarifa a predecir), `tip_amount` y `tip_ratio`.

![Balance del Split Temporal](evidencias/evidencia_08_split_balance.png)
*Figura 11: Balance de los conjuntos TRAIN, EVAL y TEST sin desplazamiento de medias.*

![Sin Solapamiento](evidencias/evidencia_08_sin_solapamiento.png)
*Figura 12: Certificación de cero solapamiento temporal entre conjuntos.*

### 6.2. Modelos de Regresión: Tarifa Base (`fare_amount`)
* **M1 — Regresión Lineal (`LINEAR_REG`):** Baseline con regularización Ridge (`l2_reg = 0.05`).
* **M2 — Boosted Trees (`BOOSTED_TREE_REGRESSOR`):** Árboles potenciados con optimización bayesiana automática (**VIZIER**, 8 ensayos).

![Evaluación de Modelos de Regresión](evidencias/evidencia_11_eval_regresion.png)
*Figura 13: Evaluación de M1 vs M2 sobre el split EVAL.*

| Modelo | MSE | MAE (USD) | **RMSE (USD)** | **R² Score** |
| :--- | :---: | :---: | :---: | :---: |
| **M1: Regresión Lineal** | 1.0977 | \$0.5035 | **\$1.0477** | **0.9865** |
| **M2: Boosted Trees (Mejor Ensayo)** | 1.6325 | \$0.6533 | **\$1.2777** | **0.9799** |

### 6.3. Modelos de Clasificación: Propina Alta (`high_tip` $\ge$ 20%)
* **M3 — Regresión Logística (`LOGISTIC_REG`):** Con `auto_class_weights = TRUE` para contrarrestar el desbalance de clases.
* **M4 — Random Forest (`RANDOM_FOREST_CLASSIFIER`):** Ensamble con auto-tuning VIZIER (4 ensayos).

![Evaluación de Clasificadores](evidencias/evidencia_11_eval_clasif.png)
*Figura 14: Métricas de clasificación de M3 vs M4.*

| Modelo | Accuracy | **Precision** | Recall | F1-Score | **ROC-AUC** | Log-Loss |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **M3: Regresión Logística** | 0.6322 | 82.23 % | 68.33 % | 0.7464 | 0.5946 | 0.6928 |
| **M4: Random Forest (Vizier)** | 0.5633 | **85.18 %** | 54.32 % | 0.6634 | **0.6206** | 0.6801 |

* **Matriz de Confusión:** Persistida en `ml_confusion_matrices` para evaluación en el informe visual.
* **Importancia de Variables:** `ML.GLOBAL_EXPLAIN` identificó a `trip_distance`, `trip_duration_minutes` y las horas pico (`is_rush_pm`) como los mayores predictores.

![Importancia de Variables](evidencias/evidencia_11_explain_btree.png)
*Figura 15: Atribución de características del modelo de árboles.*

### 6.4. Predicciones sobre Holdout TEST y Casos Sintéticos
Se ejecutaron predicciones sobre **2,847,110 viajes** del conjunto `TEST` (noviembre y diciembre) que los modelos nunca vieron durante el entrenamiento ni la evaluación:

![Predicción Holdout Test](evidencias/evidencia_12_pred_test.png)
*Figura 16: Desempeño en producción real del modelo M2 sobre el conjunto TEST.*

* **Total de Viajes Evaluados:** 2,847,110
* **RMSE en Test:** **\$1.1660 USD**
* **MAE en Test:** **\$0.6235 USD**
* **MAPE en Test:** **4.70 %** (Error porcentual medio menor al 5%)

---

## 7. Series Temporales: Rolling Forecast (`ARIMA_PLUS`)

En [sql/05_forecast/13_arima_rolling.sql](file:///C:/Users/engel/Documents/GitHub/SS22S2026_14G/Proyecto_2/sql/05_forecast/13_arima_rolling.sql) se implementó la técnica de **Rolling Forecast** encadenando 4 modelos mensuales consecutivos:

```
R1: Entrena Ene-Ago  -> Pronostica Septiembre (30 días)
R2: Entrena Ene-Sep  -> Pronostica Octubre (31 días)
R3: Entrena Ene-Oct  -> Pronostica Noviembre (30 días)
R4: Entrena Ene-Nov  -> Pronostica Diciembre (31 días)
```

![Modelos ARIMA Creados](evidencias/evidencia_13_modelos_creados.png)
*Figura 17: Creación de los 4 modelos ARIMA_PLUS en BigQuery.*

![Evaluación de ARIMA](evidencias/evidencia_13_arima_evaluate.png)
*Figura 18: Orden estacional (1,1,1) y periodicidad semanal detectada automáticamente.*

![Tabla de Rolling Forecast](evidencias/evidencia_13_rolling_tabla.png)
*Figura 19: Proyecciones encadenadas con intervalos de confianza al 95%.*

---

## 8. Capas de Datos y Enlace a Looker Studio

En [sql/06_visualizacion/14_capas_dashboard.sql](file:///C:/Users/engel/Documents/GitHub/SS22S2026_14G/Proyecto_2/sql/06_visualizacion/14_capas_dashboard.sql) se materializaron 17 tablas agregadas livianas (< 1,000 filas cada una) para que el tablero cargue al instante sin consultar los 33 millones de filas:

![Verificación de Tablas del Dashboard](evidencias/14.6.png)
*Figura 20: Conteo y verificación de las 17 tablas agregadas creadas para Looker Studio.*

* **Enlace Público al Tablero de Looker Studio:**  
  [Ver Tablero Interactivo en Looker Studio](https://datastudio.google.com/reporting/acf359c0-d5f1-4cb7-9de6-704da4d044a9) (`https://datastudio.google.com/reporting/acf359c0-d5f1-4cb7-9de6-704da4d044a9`)

### Vistas del Tablero Construido en Looker Studio:

![Dashboard Página 1: Exploración y KPIs](evidencias/evidencia_14_dashboard_p1.png)
*Figura 21: Tablero interactivo (Página 1) - Análisis exploratorio, KPIs globales, mapa de calor de demanda y distribución geográfica.*

![Dashboard Página 2: Modelos Predictivos y Forecast](evidencias/evidencia_14_dashboard_p2.png)
*Figura 22: Tablero interactivo (Página 2) - Evaluación de modelos predictivos, matrices de confusión, curvas ROC, importancia de variables y Rolling Forecast con ARIMA.*

### Contenido de las Páginas del Tablero:
1. **Página 1 — Exploración y KPIs:** Volumen total anual (33.38M), facturación neta (\$477.47M en tarifas base), horas pico de demanda (18:00 hrs martes), mapa de calor semanal y top zonas (JFK Airport y Manhattan).
2. **Página 2 — Modelos Predictivos y Forecast:** Comparativa de rendimiento de modelos (F1, ROC-AUC, RMSE, R²), matrices de confusión persistidas, importancia de características, curvas ROC y serie temporal de Rolling Forecast (ARIMA) con bandas de confianza.

---

## 9. Estructura del Repositorio

```text
Proyecto_2/
├── README.md                      # Documento técnico principal con evidencias
├── docs/                          # Documentación formal de soporte
│   ├── diccionario_datos.md       # Catálogo exhaustivo de campos y variables
│   └── informe_tecnico.md         # Informe metodológico y sustentación técnica
├── evidencias/                    # 66 capturas de pantalla de BigQuery y modelos
└── sql/                           # 14 scripts SQL organizados por fases
    ├── 01_exploracion/            # Scripts 01, 02, 03
    ├── 02_transformaciones/       # Script 04
    ├── 03_optimizacion/           # Scripts 05, 06, 07
    ├── 04_ml/                     # Scripts 08, 09, 10, 11, 12
    ├── 05_forecast/               # Script 13
    └── 06_visualizacion/          # Script 14
```
