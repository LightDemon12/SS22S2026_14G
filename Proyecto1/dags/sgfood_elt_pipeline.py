"""
=============================================================================
PROYECTO 1 - DATA WAREHOUSE & ELT (FASE 3: ORQUESTACIÓN CON APACHE AIRFLOW)
=============================================================================
DAG: sgfood_elt_pipeline
Descripción: Orquestador end-to-end del flujo ELT para SG-Food:
1. Ingesta a Capa Raw (Python: OLTP + CSVs)
2. Transformación y Modelado Dimensional (dbt run)
3. Validación y Pruebas de Calidad (dbt test)
=============================================================================
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator

default_args = {
    "owner": "data_engineering_team",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
}

with DAG(
    dag_id="sgfood_elt_pipeline",
    default_args=default_args,
    description="Pipeline ELT completo de SG-Food: Ingesta RAW, Modelado Dimensional y Testing con dbt",
    schedule_interval=None,  # Ejecución manual o programada según requerimiento (@daily)
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["sgfood", "elt", "dbt", "postgres", "raw", "marts"],
) as dag:


    # Tarea 1: Extracción y Carga a la Capa RAW (Python)

    task_extract_load_raw = BashOperator(
        task_id="extract_and_load_raw",
        bash_command="python /opt/airflow/dags/extract_load_raw.py",
        execution_timeout=timedelta(minutes=10),
    )


    # Tarea 2: Transformación y Modelado Dimensional (dbt run)

    task_dbt_run = BashOperator(
        task_id="dbt_transformation_run",
        bash_command="cd /opt/airflow/sgfood_dbt && python -m dbt.cli.main run --profiles-dir .",
        execution_timeout=timedelta(minutes=15),
    )


    # Tarea 3: Pruebas de Calidad de Datos (dbt test)

    task_dbt_test = BashOperator(
        task_id="dbt_quality_tests",
        bash_command="cd /opt/airflow/sgfood_dbt && python -m dbt.cli.main test --profiles-dir .",
        execution_timeout=timedelta(minutes=10),
    )

    #  Flujo de Ejecución Estrictamente Secuencial
    
    task_extract_load_raw >> task_dbt_run >> task_dbt_test
