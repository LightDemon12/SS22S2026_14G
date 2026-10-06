with ventas as (
    select * from {{ ref('stg_ventas') }}
),

ventas_detalle as (
    select * from {{ ref('stg_ventas_detalle') }}
)

select
    vd.id_detalle,
    vd.id_venta,
    v.id_cliente,
    vd.id_producto,
    v.id_sucursal,
    v.fecha_venta,
    v.canal_venta,
    v.metodo_pago,
    v.estado_venta,
    vd.cantidad,
    vd.precio_unitario,
    vd.porcentaje_descuento,
    cast(vd.cantidad * vd.precio_unitario as numeric(14, 2)) as monto_bruto,
    cast(round((vd.cantidad * vd.precio_unitario) * vd.porcentaje_descuento, 2) as numeric(14, 2)) as monto_descuento,
    vd.subtotal as monto_neto
from ventas_detalle vd
inner join ventas v on vd.id_venta = v.id_venta
