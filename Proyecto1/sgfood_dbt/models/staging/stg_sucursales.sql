with source as (
    select * from {{ source('raw', 'sucursal') }}
),

renamed_and_cleaned as (
    select
        cast(id_sucursal as integer) as id_sucursal,
        trim(nombre) as nombre_sucursal,
        trim(ciudad) as ciudad,
        trim(departamento) as departamento,
        cast(_extracted_at as timestamp) as extracted_at
    from source
    where id_sucursal is not null
)

select * from renamed_and_cleaned
