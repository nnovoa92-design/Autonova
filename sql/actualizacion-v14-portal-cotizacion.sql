-- ============================================================
-- Actualización v14: portal_consultar_cotizacion actualizada
--
-- · Incluye "tipo" por ítem (para desglose por categoría en el link público)
-- · Si la cotización ya fue convertida a OT, muestra los orden_items
--   (datos reales/actualizados) en vez de la cotización congelada
-- · Incluye pagos/abonos de la OT vinculada para mostrar saldo pendiente
-- ============================================================

create or replace function portal_consultar_cotizacion(p_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  with c as (
    select * from cotizaciones where id = p_id
  ),
  o as (
    select * from ordenes where cotizacion_id = p_id order by creado_en asc limit 1
  )
  select jsonb_build_object(
    'numero', c.numero,
    'fecha', c.fecha,
    'estado', c.estado,
    'validez_dias', c.validez_dias,
    'descuento_pct', c.descuento_pct,
    'con_iva', c.con_iva,
    'notas', c.notas,
    'cliente', jsonb_build_object('nombre', cl.nombre),
    'vehiculo', case when v.id is null then null
      else jsonb_build_object('patente', v.patente, 'marca', v.marca, 'modelo', v.modelo) end,
    'taller', (
      select jsonb_build_object(
        'nombre', nombre, 'telefono', telefono,
        'direccion', direccion, 'iva_pct', iva_pct
      ) from taller_config where id = 1
    ),
    'orden_numero', o.numero,
    'items', case when o.id is not null then (
        select coalesce(jsonb_agg(jsonb_build_object(
          'descripcion', oi.descripcion,
          'cantidad', oi.cantidad,
          'precio_unitario', oi.precio_unitario,
          'tipo', oi.tipo
        ) order by oi.orden), '[]'::jsonb)
        from orden_items oi where oi.orden_id = o.id
      ) else (
        select coalesce(jsonb_agg(jsonb_build_object(
          'descripcion', ci.descripcion,
          'cantidad', ci.cantidad,
          'precio_unitario', ci.precio_unitario,
          'tipo', ci.tipo
        ) order by ci.orden), '[]'::jsonb)
        from cotizacion_items ci where ci.cotizacion_id = c.id
      ) end,
    'pagado', case when o.id is not null then coalesce((
        select sum(monto) from (
          select monto from pagos where orden_id = o.id
          union all
          select monto from abonos where orden_id = o.id
        ) p
      ), 0) else 0 end
  )
  from c
  join clientes cl on cl.id = c.cliente_id
  left join vehiculos v on v.id = c.vehiculo_id
  left join o on true;
$$;

grant execute on function portal_consultar_cotizacion(uuid) to anon;

select 'v14 portal_consultar_cotizacion aplicada' as estado;
