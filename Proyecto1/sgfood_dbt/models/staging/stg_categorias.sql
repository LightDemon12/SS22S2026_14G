with source as (
    select * from {{ source('raw', 'categoria') }}
),

renamed_and_cleaned as (
    select
        cast(id_categoria as integer) as id_categoria,
        trim(nombre) as nombre_categoria,
        cast(_extracted_at as timestamp) as extracted_at
    from source
    where id_categoria is not null
)

select * from renamed_and_cleaned
