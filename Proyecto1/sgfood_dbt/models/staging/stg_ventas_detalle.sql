with source as (
    select * from {{ source('raw', 'venta_detalle') }}
),

renamed_and_cleaned as (
    select
        cast(id_detalle as bigint) as id_detalle,
        cast(id_venta as bigint) as id_venta,
        cast(id_producto as integer) as id_producto,
        cast(cantidad as integer) as cantidad,
        cast(precio_unitario as numeric(12, 2)) as precio_unitario,
        cast(descuento as numeric(5, 4)) as porcentaje_descuento,
        cast(subtotal as numeric(14, 2)) as subtotal,
        cast(_extracted_at as timestamp) as extracted_at
    from source
    where id_detalle is not null
)

select * from renamed_and_cleaned
