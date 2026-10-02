with source as (
    select * from {{ source('raw', 'cliente') }}
),

renamed_and_cleaned as (
    select
        cast(id_cliente as integer) as id_cliente,
        trim(nit) as nit,
        trim(nombre) as nombre_cliente,
        trim(tipo_cliente) as tipo_cliente,
        trim(municipio) as municipio,
        trim(departamento) as departamento,
        cast(fecha_alta as date) as fecha_alta,
        cast(_extracted_at as timestamp) as extracted_at
    from source
    where id_cliente is not null
)

select * from renamed_and_cleaned
