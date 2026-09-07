# Práctica 2: Diseño de Dashboard y KPIs con Power BI

## 1. Diseño del Modelo Tabular
El modelo de datos se construyó conectando Power BI a la base de datos `DW_Vuelos` alojada en SQL Server mediante un contenedor Docker. Se implementó un esquema de estrella donde la tabla central, `Fact_Vuelos`, almacena las métricas transaccionales (duración, retraso, precio del ticket) y se relaciona mediante llaves subrogadas con las siguientes dimensiones:
*   `Dim_Aerolinea`, `Dim_Estado_Vuelo`, `Dim_Canal_Venta`, `Dim_Metodo_Pago`, `Dim_Vuelo`
*   `Dim_Aeropuerto`: Actúa como una dimensión de rol (Role-Playing Dimension), manejando tanto el origen como el destino mediante relaciones activas e inactivas.
*   `Dim_Tiempo`: Se creó una jerarquía funcional (`Anio` > `Trimestre` > `Mes` > `Dia`) para permitir el análisis temporal escalonado (Drill-down).
*   `Dim_Pasajero`: Configurada con una relación de varios a uno (*:1) hacia la tabla de hechos, respetando el diseño para una dimensión de cambio lento (SCD Tipo 2).

## 2. Medidas DAX Implementadas
Para soportar el análisis del dashboard, se desarrollaron las siguientes medidas utilizando Expresiones de Análisis de Datos (DAX):

1.  **Total Vuelos:** Cuantifica el volumen de operaciones registradas.
    `Total Vuelos = COUNTROWS(Fact_Vuelos)`
2.  **Ingresos Totales USD:** Calcula el impacto financiero bruto.
    `Ingresos Totales USD = SUM(Fact_Vuelos[Ticket_Price_USD_Est])`
3.  **Promedio Retraso Min:** Evalúa la calidad del servicio operativo.
    `Promedio Retraso Min = AVERAGE(Fact_Vuelos[Delay_Min])`
4.  **Meta Retraso:** Establece el umbral de tolerancia para el KPI.
    `Meta Retraso = 15`

## 3. Justificación y Relevancia Estratégica de los KPIs
El dashboard fue diseñado para proporcionar una vista integral de la eficiencia operativa y el desempeño comercial:

*   **KPI de Retraso Promedio (Semáforo):** Es el indicador central de la salud operativa. Al establecer una meta de 15 minutos y utilizar una codificación por color ("El valor más bajo es bueno"), permite a la gerencia identificar inmediatamente si la puntualidad general está en un estado crítico (rojo) o dentro de los márgenes aceptables (verde).
*   **Ingresos por Aerolínea:** Permite visualizar qué aerolíneas generan mayor rentabilidad, apoyando decisiones sobre asociaciones comerciales o enfoques de venta.
*   **Top Destinos por Retraso:** Identifica cuellos de botella geográficos. Si un aeropuerto específico (como BOG o CUN) muestra retrasos promedio altos consistentemente, la gerencia puede investigar problemas de logística o infraestructura en esas rutas.
*   **Tendencia Temporal:** Facilita la identificación de patrones de estacionalidad en el volumen de vuelos a lo largo de los días y meses, información vital para la planificación de recursos.

## 4. Notas sobre Integridad de Datos
Durante la visualización, se filtró intencionalmente el valor `(En Blanco)` de la jerarquía de años. Este valor representaba vuelos con estado `CANCELLED`, los cuales carecían de fecha de llegada (`arrival_datetime = NULL`) y de tiempo de retraso. Este comportamiento valida la correcta aplicación de reglas de negocio en la fase ETL previa, asegurando que los vuelos cancelados no sesguen el promedio de retraso.

## 5. Pasos para ejecutar el proyecto

Para replicar y visualizar correctamente este proyecto en un entorno local, sigue los pasos a continuación:

**Requisitos previos:**
*   Tener **Docker Desktop** (o el demonio de Docker) instalado y en ejecución.
*   Tener **Python 3.10+** instalado.
*   Tener **Microsoft Power BI Desktop** instalado.
*   Tener el controlador **ODBC Driver 18 for SQL Server** instalado en el sistema.

**Paso 1: Configuración del entorno (Fase ETL)**
1. Abre una terminal y navega a la carpeta del proyecto (Práctica 2).
2. Crea un entorno virtual y actívalo:
    ```bash
    python -m venv .venv
    .\.venv\Scripts\Activate.ps1
    ```
3. Instala las dependencias necesarias:
    ```bash
    pip install pandas sqlalchemy pyodbc python-dotenv
    ```
4. Crea un archivo llamado .env en la raíz del proyecto basándote en el archivo .env.example, y define tu contraseña segura para la base de datos (DB_PASSWORD).

**Paso 2: Ejecución del pipeline ETL**
1. Ejecuta el script principal de orquestación:
    ```bash
    python .\app\main.py
    ```
2. El script se encargará automáticamente de:
- Eliminar contenedores previos conflictivos.
- Descargar e iniciar un nuevo contenedor de SQL Server 2022.
- Crear la base de datos DW_Vuelos y el esquema multidimensional.
- Limpiar los datos crudos del archivo CSV.
- Cargar la información limpia en las tablas de hechos y dimensiones.

**Paso 3: Visualización en Power BI**
- Una vez que el script de Python haya finalizado con éxito, dirígete a la carpeta Practica2.
- Abre el archivo dashboard.pbix con Power BI Desktop.
- En la cinta de opciones superior (pestaña Inicio), haz clic en el botón Actualizar.
- (Opcional) Si Power BI solicita credenciales para conectarse a la base de datos por primera vez, selecciona la opción de "Base de datos", ingresa el usuario (sa) y la contraseña que definiste en tu archivo .env.
- El dashboard se poblará automáticamente con los datos procesados en el contenedor local, permitiendo la interacción con los filtros y la visualización de los KPIs.