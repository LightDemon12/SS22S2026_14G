"""
Tarea #1 - Limpieza y analisis inicial de datos con Python y Pandas
Seminario de Sistemas 2 - Facultad de Ingenieria, USAC

Script equivalente al notebook tarea1_limpieza_datos.ipynb.
Ejecuta todo el proceso de limpieza, genera las tablas pivote de comparacion
antes/despues, produce las visualizaciones (.png) y exporta el dataset limpio
(.csv y .parquet).

Uso:
    python tarea1_limpieza_datos.py
"""

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")  # backend sin ventanas, ideal para correr desde terminal
import matplotlib.pyplot as plt
import seaborn as sns

pd.set_option('display.max_columns', None)
pd.set_option('display.width', 120)
sns.set_theme(style="whitegrid")
plt.rcParams['figure.figsize'] = (8, 5)


def linea(titulo):
    print("\n" + "=" * 70)
    print(titulo)
    print("=" * 70)


# 1. Carga del dataset
linea("1. CARGA DEL DATASET")
df = pd.read_csv("dataset_sucio.csv")
print(f"Dimensiones: {df.shape[0]} filas x {df.shape[1]} columnas")
print(df.head(10))
df.info()


# 2. Exploracion inicial - Estado ANTES de la limpieza

linea("2. ESTADO ANTES DE LA LIMPIEZA")
df_original = df.copy()

print("Valores nulos por columna (ANTES):")
print(df_original.isnull().sum())
print(f"\nFilas duplicadas (ANTES): {df_original.duplicated().sum()}")
print(f"IDs de cliente duplicados (ANTES): {df_original['id_cliente'].duplicated().sum()}")
print("\nValores unicos en 'genero' (ANTES):", sorted(df_original['genero'].dropna().unique().tolist()))
print("Valores unicos en 'categoria' (ANTES):", sorted(df_original['categoria'].dropna().unique().tolist()))
print("Cantidad de variantes unicas en 'ciudad' (ANTES):", df_original['ciudad'].nunique(dropna=True))

pivot_antes = pd.pivot_table(
    df_original, index='ciudad', columns='categoria',
    values='id_cliente', aggfunc='count', fill_value=0
)
print("\nTabla pivote ANTES (conteo de registros por ciudad/categoria):")
print(pivot_antes)

# 3. Proceso de limpieza
linea("3. PROCESO DE LIMPIEZA")

# 3.1 Eliminacion de duplicados
df = df.drop_duplicates()
print(f"Filas despues de eliminar duplicados: {df.shape[0]} "
      f"(se eliminaron {df_original.shape[0] - df.shape[0]} filas)")

# 3.2 Estandarizacion de 'nombre'
df['nombre'] = df['nombre'].str.strip().str.title()
df['nombre'] = df['nombre'].str.replace(r'\s+', ' ', regex=True)

# 3.3 Estandarizacion de 'genero'
df['genero'] = df['genero'].str.strip().str.upper()
df['genero'] = df['genero'].replace({'': np.nan})
df['genero'] = df['genero'].where(df['genero'].isin(['M', 'F']), np.nan)
df['genero'] = df['genero'].fillna('No especificado')

# 3.4 Estandarizacion de 'ciudad'
df['ciudad'] = df['ciudad'].str.strip().str.title()
df['ciudad'] = df['ciudad'].str.replace(r'\s+', ' ', regex=True)
df['ciudad'] = df['ciudad'].replace({'': np.nan})
df['ciudad'] = df['ciudad'].fillna('Sin Dato')

# 3.5 Estandarizacion de 'categoria'
df['categoria'] = df['categoria'].str.strip().str.title()


# 3.6 Estandarizacion de 'fecha_registro' (dos formatos mixtos)
def parse_fecha(valor):
    valor = str(valor).strip()
    if '/' in valor:
        return pd.to_datetime(valor, format='%d/%m/%Y', errors='coerce')
    return pd.to_datetime(valor, format='%Y-%m-%d', errors='coerce')


df['fecha_registro'] = df['fecha_registro'].apply(parse_fecha)
print(f"Fechas no convertibles (NaT): {df['fecha_registro'].isnull().sum()}")

# 3.7 Estandarizacion y tratamiento de 'gasto_q'
df['gasto_q'] = df['gasto_q'].astype(str).str.replace(',', '.', regex=False)
df['gasto_q'] = pd.to_numeric(df['gasto_q'], errors='coerce')
print(f"Valores nulos en gasto_q antes de imputar: {df['gasto_q'].isnull().sum()}")

df['gasto_q'] = df.groupby('categoria')['gasto_q'].transform(lambda s: s.fillna(s.median()))
df['gasto_q'] = df['gasto_q'].fillna(df['gasto_q'].median())  # respaldo
df['gasto_q'] = df['gasto_q'].round(2)
print(f"Valores nulos en gasto_q despues de imputar: {df['gasto_q'].isnull().sum()}")

# 3.8 Revision final
linea("3.8 REVISION FINAL DE NULOS Y DUPLICADOS")
print("Valores nulos por columna (DESPUES):")
print(df.isnull().sum())
print(f"\nFilas duplicadas (DESPUES): {df.duplicated().sum()}")
df.info()


# 4. Tablas pivote - Estado DESPUES de la limpieza
linea("4. TABLAS PIVOTE - ESTADO DESPUES")
pivot_despues = pd.pivot_table(
    df, index='ciudad', columns='categoria',
    values='gasto_q', aggfunc='mean', fill_value=0
).round(2)
print("Gasto promedio (Q) por ciudad y categoria:")
print(pivot_despues)

pivot_conteo_despues = pd.pivot_table(
    df, index='ciudad', columns='categoria',
    values='id_cliente', aggfunc='count', fill_value=0
)
print("\nConteo de registros por ciudad y categoria:")
print(pivot_conteo_despues)

# 5. Visualizaciones
linea("5. GENERANDO VISUALIZACIONES (.png)")

# 5.1 Distribucion del gasto
fig, ax = plt.subplots()
sns.histplot(df['gasto_q'], bins=30, kde=True, color='#4C72B0', ax=ax)
ax.set_title('Distribucion del gasto (Q) - dataset limpio')
ax.set_xlabel('Gasto (Q)')
ax.set_ylabel('Frecuencia')
plt.tight_layout()
plt.savefig('viz_distribucion_gasto.png', dpi=120)
plt.close(fig)

# 5.2 Gasto por categoria
fig, ax = plt.subplots()
sns.boxplot(data=df, x='categoria', y='gasto_q', hue='categoria', palette='Set2', legend=False, ax=ax)
ax.set_title('Gasto por categoria')
ax.set_xlabel('Categoria')
ax.set_ylabel('Gasto (Q)')
plt.tight_layout()
plt.savefig('viz_gasto_por_categoria.png', dpi=120)
plt.close(fig)

# 5.3 Gasto promedio por ciudad
gasto_ciudad = df.groupby('ciudad')['gasto_q'].mean().sort_values(ascending=False)
fig, ax = plt.subplots()
gasto_ciudad.plot(kind='bar', color='#55A868', ax=ax)
ax.set_title('Gasto promedio por ciudad')
ax.set_xlabel('Ciudad')
ax.set_ylabel('Gasto promedio (Q)')
plt.xticks(rotation=45, ha='right')
plt.tight_layout()
plt.savefig('viz_gasto_por_ciudad.png', dpi=120)
plt.close(fig)

# 5.4 Distribucion por genero
fig, ax = plt.subplots()
df['genero'].value_counts().plot(kind='bar', color='#C44E52', ax=ax)
ax.set_title('Distribucion de clientes por genero')
ax.set_xlabel('Genero')
ax.set_ylabel('Cantidad de clientes')
plt.xticks(rotation=0)
plt.tight_layout()
plt.savefig('viz_distribucion_genero.png', dpi=120)
plt.close(fig)

# 5.5 Registros a lo largo del tiempo
registros_semana = df.set_index('fecha_registro').resample('W')['id_cliente'].count()
fig, ax = plt.subplots()
registros_semana.plot(kind='line', marker='o', color='#8172B2', ax=ax)
ax.set_title('Registros de clientes por semana')
ax.set_xlabel('Semana')
ax.set_ylabel('Cantidad de registros')
plt.tight_layout()
plt.savefig('viz_registros_tiempo.png', dpi=120)
plt.close(fig)

# 5.6 Heatmap gasto promedio por ciudad y categoria
fig, ax = plt.subplots(figsize=(9, 6))
sns.heatmap(pivot_despues, annot=True, fmt='.1f', cmap='YlGnBu', ax=ax)
ax.set_title('Gasto promedio (Q) por ciudad y categoria')
plt.tight_layout()
plt.savefig('viz_heatmap_ciudad_categoria.png', dpi=120)
plt.close(fig)

print("Visualizaciones guardadas: viz_distribucion_gasto.png, viz_gasto_por_categoria.png, "
      "viz_gasto_por_ciudad.png, viz_distribucion_genero.png, viz_registros_tiempo.png, "
      "viz_heatmap_ciudad_categoria.png")

# 6. Exportacion del dataset limpio
linea("6. EXPORTACION DEL DATASET LIMPIO")
df.to_csv('dataset_limpio.csv', index=False)
df.to_parquet('dataset_limpio.parquet', index=False)
print("Archivos exportados: dataset_limpio.csv, dataset_limpio.parquet")
print("\nProceso finalizado correctamente.")
