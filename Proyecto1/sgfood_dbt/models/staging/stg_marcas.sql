with source as (
    select * from {{ source('raw', 'marca') }}
),

renamed_and_cleaned as (
    select
        cast(id_marca as integer) as id_marca,
        trim(nombre) as nombre_marca,
        cast(_extracted_at as timestamp) as extracted_at
    from source
    where id_marca is not null
)

select * from renamed_and_cleaned
