with ventas_detalladas as (
    select * from {{ ref('int_ventas_detalladas') }}
)

select
    id_detalle,
    id_venta,
    id_cliente,
    id_producto,
    id_sucursal,
    fecha_venta,
    canal_venta,
    metodo_pago,
    estado_venta,
    cantidad,
    precio_unitario,
    porcentaje_descuento,
    monto_bruto,
    monto_descuento,
    monto_neto
from ventas_detalladas
