# Diccionario de Datos: Proyecto 2 - BigQuery & BigQuery ML
**Seminario de Sistemas 2 — Segundo Semestre 2026**  
**Facultad de Ingeniería — Universidad de San Carlos de Guatemala**  
**Grupo / Pareja 14**  

---

## 1. Introducción y Alcance del Diccionario

El presente documento constituye el catálogo y diccionario técnico de datos utilizado en el pipeline analítico del Proyecto 2. Detalla la estructura original del dataset público de la Comisión de Taxis y Limosinas de Nueva York (**NYC TLC Yellow Trips 2022**), los tipos de datos físicos en Google BigQuery, las transformaciones y reglas de tipado aplicadas en la capa de hechos limpia (`fact_trips_std` / `fact_trips_opt` en el proyecto `ss2-2026-pareja14-v2`), las variables calculadas durante la fase de **Ingeniería de Características** (`vw_ml_features`), y las tablas agregadas de soporte analítico y visualización.

---

## 2. Dataset Fuente: TLC Yellow Trips 2022
* **Tabla fuente pública:** `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`
* **Volumen:** 36,256,539 registros
* **Tamaño lógico:** ~6.97 GB
* **Granularidad original:** 1 registro por viaje individual completado

| Columna Original | Tipo Original (GCP) | Tipo Destino (`fact_trips_std`) | ¿Conservada? | Descripción y Reglas de Transformación |
| :--- | :--- | :--- | :---: | :--- |
| `vendor_id` | `STRING` | `INT64` | Sí | Código del proveedor del taxímetro (1 = Creative Mobile Technologies, 2 = VeriFone Inc.). Viene en formato cadena flotante (`'1.0'`, `'2.0'`), por lo que requiere doble casting `SAFE_CAST(SAFE_CAST(vendor_id AS FLOAT64) AS INT64)`. |
| `pickup_datetime` | `TIMESTAMP` | `TIMESTAMP` | Sí | Fecha y hora exacta de inicio del viaje (abordaje del pasajero). Campo base de orden temporal. |
| `dropoff_datetime` | `TIMESTAMP` | `TIMESTAMP` | Sí | Fecha y hora exacta de finalización del viaje (descenso del pasajero). Se valida que sea estrictamente posterior a `pickup_datetime`. |
| `passenger_count` | `INTEGER` | `INT64` | Sí | Número de pasajeros reportado por el conductor. Se filtran registros inválidos fuera del rango $[1, 9]$. |
| `trip_distance` | `NUMERIC` | `FLOAT64` | Sí | Distancia recorrida reportada por el taxímetro en millas. Se convierte a `FLOAT64` para compatibilidad con BQML. Filtrada entre 0.1 y 100 millas. |
| `rate_code` | `STRING` | `INT64` | Sí | Código de tarifa aplicable al viaje (1 = Estándar por taxímetro, 2 = JFK, 3 = Newark, 4 = Nassau/Westchester, 5 = Tarifa negociada, 6 = Viaje grupal). Viene como `STRING` (`'1.0'`). |
| `store_and_fwd_flag` | `STRING` | — | No | Bandera que indica si el registro se almacenó en la memoria del vehículo antes de enviarse al servidor (`Y`/`N`). Se excluye de la tabla de hechos por ser de uso de auditoría telemática y no aportar al modelado. |
| `payment_type` | `STRING` | `INT64` | Sí | Método de pago del pasajero (1 = Tarjeta de crédito, 2 = Efectivo, 3 = Sin cargo, 4 = Disputa, 5 = Desconocido, 6 = Anulado). Viene como `STRING` (`'1.0'`). |
| `fare_amount` | `NUMERIC` | `FLOAT64` | Sí | Tarifa base calculada por tiempo y distancia según el taxímetro (USD). Se acota entre \$2.50 (tarifa mínima legal en NYC) y \$500.00. |
| `extra` | `NUMERIC` | `FLOAT64` | Sí | Recargos misceláneos vigentes (USD), incluyendo el cargo por hora pico (\$1.00) y recargo nocturno (\$0.50). |
| `mta_tax` | `NUMERIC` | — | No | Impuesto gubernamental de la Autoridad Metropolitana de Transporte (\$0.50 USD). Se descarta en la tabla de hechos por varianza cero (constante fija). |
| `tip_amount` | `NUMERIC` | `FLOAT64` | Sí | Monto de propina pagado en dólares (USD). **Nota crítica:** Solo se registra automáticamente en pagos con tarjeta de crédito (`payment_type = 1`). En efectivo se registra \$0.00. |
| `tolls_amount` | `NUMERIC` | `FLOAT64` | Sí | Total de peajes de puentes y túneles pagados durante el trayecto (USD). |
| `improvement_surcharge` | `NUMERIC` | — | No | Recargo de mejora implementado en 2015 (\$0.30 USD). Se descarta por varianza cero. |
| `total_amount` | `NUMERIC` | `FLOAT64` | Sí | Monto total cobrado al pasajero (USD). Incluye tarifa, recargos, peajes y propina. Se valida que sea $\ge fare\_amount$ y acotado entre \$2.50 y \$1,000.00. |
| `congestion_surcharge` | `NUMERIC` | `FLOAT64` | Sí | Recargo por congestión (\$2.50 USD para taxis amarillos al circular al sur de la calle 96 en Manhattan). |
| `airport_fee` | `NUMERIC` | — | No | Recargo aeroportuario (\$1.25 USD). Se descarta por redundancia con las variables derivadas de aeropuerto. |
| `pickup_location_id` | `STRING` | `INT64` | Sí | Identificador numérico de la zona TLC donde inició el viaje (1 a 265). Viene como `STRING` y se sanea a `INT64`. |
| `dropoff_location_id` | `STRING` | `INT64` | Sí | Identificador numérico de la zona TLC donde finalizó el viaje (1 a 265). |

---

## 3. Variables Derivadas en la Capa de Hechos (`fact_trips_std` / `fact_trips_opt`)

Estas variables se calculan durante el proceso de extracción y limpieza ejecutado en [04_metricas.sql](file:///C:/Users/engel/Documents/GitHub/SS22S2026_14G/Proyecto_2/sql/02_transformaciones/04_metricas.sql) para optimizar consultas posteriores y servir de base para el análisis exploratorio:

| Variable | Tipo de Dato | Fórmula / Expresión SQL | Justificación Técnica y de Negocio |
| :--- | :---: | :--- | :--- |
| `pickup_date` | `DATE` | `DATE(pickup_datetime)` | Permite el particionamiento físico diario en la tabla optimizada `fact_trips_opt`. Evita evaluar funciones en cláusulas `WHERE`. |
| `trip_duration_minutes` | `INT64` | `TIMESTAMP_DIFF(dropoff_datetime, pickup_datetime, MINUTE)` | Mide la duración neta del viaje en minutos. Se valida estrictamente en el intervalo $[1, 240]$ minutos. |
| `tip_ratio` | `FLOAT64` | `SAFE_DIVIDE(tip_amount, NULLIF(fare_amount, 0))` | Proporción entre la propina y la tarifa base del taxímetro. Base fundamental para catalogar viajes con propina alta. |

---

## 4. Diccionario de Características para Machine Learning (`vw_ml_features`)

Generadas en la vista [08_features.sql](file:///C:/Users/engel/Documents/GitHub/SS22S2026_14G/Proyecto_2/sql/04_ml/08_features.sql). Todas las variables representan información **disponible al inicio o antes del viaje**, evitando cualquier filtración temporal o de la etiqueta (*Data Leakage*):

### 4.1. Variables Temporales y Calendario
| Variable | Tipo | Expresión / Lógica | Justificación Analítica |
| :--- | :---: | :--- | :--- |
| `pickup_hour` | `INT64` | `EXTRACT(HOUR FROM pickup_datetime)` | Hora del día (0-23). Modela patrones circadianos y congestión vehicular. |
| `pickup_dow` | `INT64` | `EXTRACT(DAYOFWEEK FROM pickup_datetime)` | Día de la semana (1 = Domingo, ..., 7 = Sábado). Captura variabilidad semanal. |
| `pickup_month` | `INT64` | `EXTRACT(MONTH FROM pickup_datetime)` | Mes del año (1-12). Refleja estacionalidad anual y turismo. |
| `is_weekend` | `INT64` | `IF(pickup_dow IN (1, 7), 1, 0)` | Bandera binaria: 1 si es fin de semana (sábado/domingo), 0 entre semana. |
| `is_rush_am` | `INT64` | `IF(pickup_hour BETWEEN 6 AND 9, 1, 0)` | Hora pico matutina laboral (6:00 a 9:59 hrs). Mayor congestión y menor velocidad. |
| `is_rush_pm` | `INT64` | `IF(pickup_hour BETWEEN 16 AND 19, 1, 0)` | Hora pico vespertina laboral (16:00 a 19:59 hrs). |
| `is_night` | `INT64` | `IF(pickup_hour >= 22 OR pickup_hour < 5, 1, 0)` | Horario nocturno (22:00 a 4:59 hrs). Se asocia a tarifas con recargo nocturno y menor tráfico. |
| `is_holiday` | `INT64` | Bandera contra calendario de 12 días festivos oficiales de EE.UU. en 2022 | Los feriados alteran completamente el volumen habitual de transporte corporativo. |

### 4.2. Variables Físicas y Cinemáticas
| Variable | Tipo | Expresión / Lógica | Justificación Analítica |
| :--- | :---: | :--- | :--- |
| `trip_distance` | `FLOAT64` | Distancia en millas ($0.1$ a $100$) | Predictor lineal primario del costo y esfuerzo del servicio. |
| `trip_duration_minutes` | `INT64` | Duración del servicio ($1$ a $240$ min) | Predictor directo del componente de tiempo del taxímetro. |
| `avg_speed_mph` | `FLOAT64` | `ROUND(SAFE_DIVIDE(trip_distance, trip_duration_minutes / 60), 2)` | Velocidad media estimada en millas por hora. Indicador sintético de fluidez o congestión del tráfico. |
| `passenger_count` | `INT64` | Pasajeros ($1$ a $9$) | Permite inferir el tipo de servicio o requerimiento de vehículo grande (SUV/minivan). |
| `distance_bucket` | `STRING` | Rangos: `'0-1 mi'`, `'1-3 mi'`, `'3-6 mi'`, `'6-12 mi'`, `'12+ mi'` | Segmentación categórica no lineal para ayudar a modelos lineales a capturar cambios de régimen por distancia. |

### 4.3. Variables Geográficas y Espaciales
| Variable | Tipo | Expresión / Lógica | Justificación Analítica |
| :--- | :---: | :--- | :--- |
| `pickup_borough` | `STRING` | Distrito municipal de origen (`Manhattan`, `Queens`, `Brooklyn`, `Bronx`, `Staten Island`, `EWR`) | Macro-zona de origen vinculada a perfiles socioeconómicos y distancias base. |
| `dropoff_borough` | `STRING` | Distrito municipal de destino | Permite capturar viajes inter-borough (cruces de ríos/puentes). |
| `is_airport_pickup` | `INT64` | `IF(pickup_location_id IN (132, 138), 1, 0)` | 1 si el viaje se originó en el Aeropuerto JFK (132) o LaGuardia (138). |
| `is_airport_dropoff` | `INT64` | `IF(dropoff_location_id IN (132, 138), 1, 0)` | 1 si el destino final fue JFK o LaGuardia. |
| `is_hot_zone` | `INT64` | `IF(pickup_location_id IN (top 14 zonas más densas), 1, 0)` | Zonas de altísima demanda en Midtown y Lower Manhattan (Midtown Center, Times Square, Upper East Side, etc.). |

### 4.4. Variables Contextuales y Económicas al Abordar
| Variable | Tipo | Expresión / Lógica | Justificación Analítica |
| :--- | :---: | :--- | :--- |
| `extra` | `FLOAT64` | Recargos misceláneos oficiales (\$0.50, \$1.00, etc.) | Reglas tarifarias mandatorias conocidas antes de rodar. |
| `tolls_amount` | `FLOAT64` | Costo de peajes conocidos en la ruta | Monto transferible directamente al costo del viaje. |
| `congestion_surcharge`| `FLOAT64` | Recargo fijo (\$2.50) si el origen/destino está en zona protegida de Manhattan | Regulación obligatoria en zona de congestión. |
| `vendor_id_str` | `STRING` | `'1'` o `'2'` | Permite al modelo aislar cualquier sesgo sistemático de calibración de hardware entre VeriFone y CMT. |

### 4.5. Variables Objetivo / Etiquetas (Targets)
| Variable | Tipo | Modelo en el que se utiliza | Definición y Regla |
| :--- | :---: | :--- | :--- |
| `fare_amount` | `FLOAT64` | Modelos de Regresión (M1 y M2) | Tarifa base del taxímetro en dólares. Variable continua positiva. |
| `high_tip` | `INT64` | Modelos de Clasificación (M3 y M4) | Variable binaria: $1$ si $\frac{tip\_amount}{fare\_amount} \ge 0.20$ (propina generosa $\ge 20\%$), $0$ en caso contrario. Evaluada únicamente en transacciones con tarjeta de crédito (`payment_type = 1`). |

### 4.6. Variable de Control y Particionamiento
| Variable | Tipo | Valores Posibles | Propósito y Regla Anti Data-Leakage |
| :--- | :---: | :--- | :--- |
| `split_set` | `STRING` | `'TRAIN'`, `'EVAL'`, `'TEST'` | **Partición temporal obligatoria:**<br>• `TRAIN`: viajes antes del 16 de septiembre de 2022 (~78%).<br>• `EVAL`: viajes entre el 16 de septiembre y el 31 de octubre de 2022 (~13%).<br>• `TEST`: viajes a partir del 1 de noviembre de 2022 (~9%).<br>**NUNCA entra como feature de entrenamiento.** |

---

## 5. Tablas Agregadas y Capas de Soporte (`14_capas_dashboard.sql`)

Para optimizar el rendimiento y garantizar tiempos de carga instantáneos en Looker Studio, se precalculan 17 tablas agregadas que no superan las 1,000 filas:

1. **`dim_zones` (~265 filas):** Catálogo de zonas TLC (`location_id`, `borough`, `zone`, `service_zone`).
2. **`agg_daily` (365 filas):** Métricas diarias consolidadas (`trip_count`, `revenue_fare`, `revenue_tips`, `revenue_total`, `avg_trip_distance`, `avg_fare_amount`).
3. **`agg_hourly_profile` (168 filas):** Matriz 24 horas x 7 días (`pickup_hour`, `pickup_dow`, `nombre_dia`, `n_viajes`, `velocidad_promedio`, `fare_promedio`).
4. **`agg_zones` (~265 filas):** Demanda y ranking de zonas de origen y destino (`rank_origen`, `rank_destino`).
5. **`dash_kpis` (1 fila):** Resumen global con totales anuales, picos de demanda y recaudación neta.
6. **`dash_monthly` (12 filas):** Tendencia de volumen y recaudación mes a mes.
7. **`dash_zones_top` (15 filas):** Top 15 zonas de mayor concentración de viajes.
8. **`dash_scatter_fare` (~40 filas):** Dispersión agregada distancia vs tarifa real vs predicha en bloques de 0.5 millas.
9. **`ml_confusion_matrices` (10 filas):** Matrices de confusión persistidas para los clasificadores M3 y M4.
10. **`ml_feature_importance` (30 filas):** Atribución de importancia global extraída con `ML.GLOBAL_EXPLAIN` (top 15 variables de M2 y M4).
11. **`forecast_rolling` (122 filas):** Predicciones de demanda diaria del Rolling Forecast (`ARIMA_PLUS`) de septiembre a diciembre con intervalos de confianza al 95%.
12. **`forecast_rolling_metrics` (4 filas):** Métricas de desempeño de las 4 ventanas mensuales (RMSE, MAE, MAPE y cobertura de intervalo).
13. **`dash_anomalies` (335 filas):** Puntos de demanda detectados como atípicos o estacionales por `ML.DETECT_ANOMALIES`.
