-- ============================================================
-- Actualización v30: descuento en la OT (una sola fuente de verdad)
--
-- La cotización guardaba descuento_pct, pero la OT no tenía dónde
-- guardarlo: al convertir se perdía, y la cotización ya convertida
-- seguía aplicando su propio descuento sobre los ítems de la OT, así
-- que ambos documentos podían mostrar totales distintos.
--
-- Desde ahora, cuando existe la OT, ella manda: ítems, descuento e IVA
-- se leen de la OT y la cotización solo los muestra.
-- ============================================================

ALTER TABLE ordenes
ADD COLUMN IF NOT EXISTS descuento_pct numeric(5,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN ordenes.descuento_pct IS 'Descuento % sobre el subtotal de la OT (se copia de la cotización al convertir y desde ahí se edita en la OT)';

-- OT ya convertidas: heredan el descuento de su cotización
update ordenes o
set descuento_pct = c.descuento_pct
from cotizaciones c
where o.cotizacion_id = c.id
  and o.descuento_pct = 0
  and c.descuento_pct > 0;

-- Link público de cotización: si ya existe la OT, descuento e IVA salen de ella
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
    'descuento_pct', coalesce(o.descuento_pct, c.descuento_pct),
    'con_iva', coalesce(o.con_iva, c.con_iva),
    'notas', c.notas,
    'cliente', jsonb_build_object('nombre', cl.nombre),
    'vehiculo', case when v.id is null then null
      else jsonb_build_object('patente', v.patente, 'marca', v.marca, 'modelo', v.modelo) end,
    'taller', (
      select jsonb_build_object(
        'nombre', nombre, 'telefono', telefono,
        'direccion', direccion, 'iva_pct', iva_pct,
        'politicas_generales_texto', politicas_generales_texto,
        'politica_inspeccion_texto', politica_inspeccion_texto,
        'politica_revision_tecnica_texto', politica_revision_tecnica_texto
      ) from taller_config where id = 1
    ),
    'orden_numero', o.numero,
    'garantia_especial', o.garantia_especial,
    'items', case when o.id is not null then (
        select coalesce(jsonb_agg(jsonb_build_object(
          'descripcion', oi.descripcion,
          'cantidad', oi.cantidad,
          'precio_unitario', oi.precio_unitario,
          'tipo', oi.tipo,
          'tipo_otro', oi.tipo_otro,
          'categoria', ct.nombre
        ) order by oi.orden), '[]'::jsonb)
        from orden_items oi
        left join trabajos tr on tr.id = oi.trabajo_id
        left join categorias_trabajos ct on ct.id = tr.categoria_id
        where oi.orden_id = o.id
      ) else (
        select coalesce(jsonb_agg(jsonb_build_object(
          'descripcion', ci.descripcion,
          'cantidad', ci.cantidad,
          'precio_unitario', ci.precio_unitario,
          'tipo', ci.tipo,
          'tipo_otro', ci.tipo_otro,
          'categoria', ct.nombre
        ) order by ci.orden), '[]'::jsonb)
        from cotizacion_items ci
        left join trabajos tr on tr.id = ci.trabajo_id
        left join categorias_trabajos ct on ct.id = tr.categoria_id
        where ci.cotizacion_id = c.id
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

-- Portal del cliente (estado de su vehículo): ahora también informa el descuento
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
    'descuento_pct', o.descuento_pct,
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

grant execute on function portal_consultar_orden(text, bigint) to anon;

select 'v30 descuento en OT aplicado' as estado;
