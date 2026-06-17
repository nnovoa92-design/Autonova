-- ============================================================
-- Actualización v5: IVA opcional (con/sin IVA) en cotizaciones,
-- órdenes de trabajo y pagos, para poder medir ventas netas.
--
-- · cotizaciones.con_iva / ordenes.con_iva: si false, el total es
--   solo el neto (no se agrega IVA).
-- · pagos.con_iva: si true, el monto incluye IVA (neto = monto/1.19);
--   si false, el monto ya es neto.
--
-- EJECUTAR en el SQL Editor de Supabase. Seguro de correr más de una vez.
-- ============================================================

alter table cotizaciones add column if not exists con_iva boolean not null default true;
alter table ordenes      add column if not exists con_iva boolean not null default true;
alter table pagos        add column if not exists con_iva boolean not null default true;

-- El portal del cliente devuelve también con_iva (para mostrar bien el total)
create or replace function portal_consultar_cotizacion(p_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
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
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'descripcion', i.descripcion,
        'cantidad', i.cantidad,
        'precio_unitario', i.precio_unitario
      ) order by i.orden), '[]'::jsonb)
      from cotizacion_items i where i.cotizacion_id = c.id
    )
  )
  from cotizaciones c
  join clientes cl on cl.id = c.cliente_id
  left join vehiculos v on v.id = c.vehiculo_id
  where c.id = p_id;
$$;

create or replace function portal_consultar_orden(p_patente text, p_numero bigint)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'orden_id', o.id,
    'numero', o.numero,
    'estado', o.estado,
    'fecha_ingreso', o.fecha_ingreso,
    'fecha_entrega', o.fecha_entrega,
    'diagnostico', o.diagnostico,
    'avances', o.avances,
    'con_iva', o.con_iva,
    'vehiculo', jsonb_build_object('patente', v.patente, 'marca', v.marca, 'modelo', v.modelo),
    'taller', (
      select jsonb_build_object(
        'nombre', nombre, 'telefono', telefono,
        'direccion', direccion, 'iva_pct', iva_pct
      ) from taller_config where id = 1
    ),
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'descripcion', i.descripcion,
        'cantidad', i.cantidad,
        'precio_unitario', i.precio_unitario
      ) order by i.orden), '[]'::jsonb)
      from orden_items i where i.orden_id = o.id
    )
  )
  from ordenes o
  join vehiculos v on v.id = o.vehiculo_id
  where upper(replace(v.patente, ' ', '')) = upper(replace(p_patente, ' ', ''))
    and o.numero = p_numero
  limit 1;
$$;

grant execute on function portal_consultar_cotizacion(uuid) to anon;
grant execute on function portal_consultar_orden(text, bigint) to anon;

select 'v5 aplicada' as estado;
