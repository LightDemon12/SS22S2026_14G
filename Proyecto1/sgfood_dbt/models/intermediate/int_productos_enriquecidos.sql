with productos as (
    select * from {{ ref('stg_productos') }}
),

categorias as (
    select * from {{ ref('stg_categorias') }}
),

marcas as (
    select * from {{ ref('stg_marcas') }}
)

select
    p.id_producto,
    p.sku,
    p.nombre_producto,
    p.id_categoria,
    coalesce(c.nombre_categoria, 'Sin Categoría') as categoria,
    p.id_marca,
    coalesce(m.nombre_marca, 'Sin Marca') as marca,
    p.unidad_medida,
    p.costo_base,
    p.precio_lista,
    cast((p.precio_lista - p.costo_base) as numeric(12, 2)) as margen_unitario_teorico,
    p.es_activo
from productos p
left join categorias c on p.id_categoria = c.id_categoria
left join marcas m on p.id_marca = m.id_marca
