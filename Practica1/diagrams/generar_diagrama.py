import graphviz

g = graphviz.Digraph("modelo_dimensional", format="png")
g.attr(rankdir="TB", splines="ortho", bgcolor="white", fontname="Helvetica")
g.attr("node", shape="none", fontname="Helvetica")

def tabla_html(nombre, columnas, color_header):
    filas = "".join(
        f'<TR><TD ALIGN="LEFT"><FONT POINT-SIZE="11">{c}</FONT></TD></TR>'
        for c in columnas
    )
    return f'''<
    <TABLE BORDER="1" CELLBORDER="0" CELLSPACING="0" CELLPADDING="6">
      <TR><TD BGCOLOR="{color_header}"><FONT COLOR="white"><B>{nombre}</B></FONT></TD></TR>
      {filas}
    </TABLE>
    >'''

FACT_COLOR = "#2C3E50"
DIM_COLOR = "#2E86C1"
SCD_COLOR = "#C0392B"

g.node("fact_vuelos", tabla_html(
    "fact_vuelos (HECHO)",
    ["fact_key (PK)", "record_id", "flight_number",
     "fecha_salida_key (FK)", "aerolinea_key (FK)",
     "origen_key (FK)", "destino_key (FK)",
     "aeronave_key (FK)", "clase_key (FK)",
     "canal_key (FK)", "metodo_pago_key (FK)",
     "estado_key (FK)", "pasajero_key (FK)",
     "fecha_hora_salida/llegada/reserva",
     "seat, duration_min, delay_min",
     "ticket_price_usd, bags_total, bags_checked"],
    FACT_COLOR
))

g.node("dim_fecha", tabla_html(
    "dim_fecha", ["fecha_key (PK)", "fecha", "anio", "mes",
                  "nombre_mes", "trimestre", "dia",
                  "dia_semana", "es_fin_semana"], DIM_COLOR))

g.node("dim_aerolinea", tabla_html(
    "dim_aerolinea", ["aerolinea_key (PK)", "airline_code", "airline_name"], DIM_COLOR))

g.node("dim_aeropuerto", tabla_html(
    "dim_aeropuerto\n(dimension de ROL)", ["aeropuerto_key (PK)", "codigo_iata"], DIM_COLOR))

g.node("dim_aeronave", tabla_html(
    "dim_aeronave", ["aeronave_key (PK)", "aircraft_type"], DIM_COLOR))

g.node("dim_clase_cabina", tabla_html(
    "dim_clase_cabina", ["clase_key (PK)", "cabin_class"], DIM_COLOR))

g.node("dim_canal_venta", tabla_html(
    "dim_canal_venta", ["canal_key (PK)", "sales_channel"], DIM_COLOR))

g.node("dim_metodo_pago", tabla_html(
    "dim_metodo_pago", ["metodo_pago_key (PK)", "payment_method"], DIM_COLOR))

g.node("dim_estado_vuelo", tabla_html(
    "dim_estado_vuelo", ["estado_key (PK)", "status"], DIM_COLOR))

g.node("dim_pasajero", tabla_html(
    "dim_pasajero (SCD TIPO 2)",
    ["pasajero_key (PK)", "passenger_id (clave negocio)",
     "genero", "edad", "nacionalidad", "version",
     "fecha_inicio_validez", "fecha_fin_validez", "es_actual"],
    SCD_COLOR
))

# Relaciones (fact -> dimensiones)
g.edge("fact_vuelos", "dim_fecha", label="fecha_salida_key", color="#7f8c8d")
g.edge("fact_vuelos", "dim_aerolinea", label="aerolinea_key", color="#7f8c8d")
g.edge("fact_vuelos", "dim_aeropuerto", label="origen_key", color="#7f8c8d")
g.edge("fact_vuelos", "dim_aeropuerto", label="destino_key", color="#7f8c8d")
g.edge("fact_vuelos", "dim_aeronave", label="aeronave_key", color="#7f8c8d")
g.edge("fact_vuelos", "dim_clase_cabina", label="clase_key", color="#7f8c8d")
g.edge("fact_vuelos", "dim_canal_venta", label="canal_key", color="#7f8c8d")
g.edge("fact_vuelos", "dim_metodo_pago", label="metodo_pago_key", color="#7f8c8d")
g.edge("fact_vuelos", "dim_estado_vuelo", label="estado_key", color="#7f8c8d")
g.edge("fact_vuelos", "dim_pasajero", label="pasajero_key", color="#7f8c8d")

g.render("modelo_dimensional", cleanup=True)
print("Diagrama generado: modelo_dimensional.png")
