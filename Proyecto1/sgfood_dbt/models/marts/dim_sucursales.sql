with sucursales as (
    select * from {{ ref('stg_sucursales') }}
)

select
    id_sucursal,
    nombre_sucursal,
    ciudad,
    departamento
from sucursales
