with productos_enriquecidos as (
    select * from {{ ref('int_productos_enriquecidos') }}
)

select
    id_producto,
    sku,
    nombre_producto,
    id_categoria,
    categoria,
    id_marca,
    marca,
    unidad_medida,
    costo_base,
    precio_lista,
    margen_unitario_teorico,
    es_activo
from productos_enriquecidos
