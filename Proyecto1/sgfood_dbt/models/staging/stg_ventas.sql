with source as (
    select * from {{ source('raw', 'venta') }}
),

renamed_and_cleaned as (
    select
        cast(id_venta as bigint) as id_venta,
        cast(fecha as date) as fecha_venta,
        cast(id_cliente as integer) as id_cliente,
        cast(id_sucursal as integer) as id_sucursal,
        trim(canal) as canal_venta,
        trim(metodo_pago) as metodo_pago,
        trim(estado) as estado_venta,
        cast(_extracted_at as timestamp) as extracted_at
    from source
    where id_venta is not null
)

select * from renamed_and_cleaned
