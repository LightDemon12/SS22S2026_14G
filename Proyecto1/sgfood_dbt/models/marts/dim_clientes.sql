with clientes as (
    select * from {{ ref('stg_clientes') }}
)

select
    id_cliente,
    nit,
    nombre_cliente,
    tipo_cliente,
    municipio,
    departamento,
    fecha_alta
from clientes
