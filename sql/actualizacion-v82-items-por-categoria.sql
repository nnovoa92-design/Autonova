-- ============================================================
-- v82 — Cotizaciones (y OT / diagnósticos) con los ítems agrupados por categoría y en orden
--
--  * Cada línea guarda su categoría (categoria_id): la de su trabajo del catálogo, y los repuestos e
--    insumos la del trabajo con que se agregaron (o la que elijas). Viaja de diagnóstico a cotización y a OT.
--  * Las categorías se ordenan en Catálogo (↑ ↓) y en ese orden salen en la cotización, su PDF,
--    el link del cliente y los mensajes, con subtotal por categoría.
--  * Se completa la categoría de las líneas ya existentes que vienen de un trabajo del catálogo.
--  * OT: desde ahora sin «Trabajos realizados / avances» (las OT ya existentes lo conservan); los comentarios y
--    fotos van en el avance por categoría y al final hay una «Observación general» (ordenes.observacion_general).
--
-- Requiere v81. Seguro de correr más de una vez.
-- ============================================================

alter table cotizacion_items add column if not exists categoria_id uuid references categorias_trabajos(id) on delete set null;
alter table orden_items add column if not exists categoria_id uuid references categorias_trabajos(id) on delete set null;
alter table diagnostico_items add column if not exists categoria_id uuid references categorias_trabajos(id) on delete set null;

-- Líneas ya existentes: la categoría de su trabajo
update cotizacion_items i set categoria_id = t.categoria_id from trabajos t
 where i.trabajo_id = t.id and i.categoria_id is null and t.categoria_id is not null;
update orden_items i set categoria_id = t.categoria_id from trabajos t
 where i.trabajo_id = t.id and i.categoria_id is null and t.categoria_id is not null;
update diagnostico_items i set categoria_id = t.categoria_id from trabajos t
 where i.trabajo_id = t.id and i.categoria_id is null and t.categoria_id is not null;

-- OT: «Trabajos realizados / avances» solo en las OT que ya existían (no retroactivo). Las nuevas usan el
-- avance por categoría y una observación general al final.
alter table ordenes add column if not exists avances_libres boolean;
update ordenes set avances_libres = true where avances_libres is null;
alter table ordenes alter column avances_libres set default false;
alter table ordenes add column if not exists observacion_general text;

-- Orden de las categorías sin huecos ni repetidos (el que ya tenían manda)
with o as (select id, row_number() over (order by orden, nombre) as n from categorias_trabajos)
update categorias_trabajos c set orden = o.n from o where o.id = c.id and c.orden is distinct from o.n;

-- Link público de la cotización: igual que v66 + la categoría de cada línea y su orden
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
    'enviada_en', c.enviada_en,
    'rechazo_motivo', c.rechazo_motivo,
    'rechazada_en', c.rechazada_en,
    'descuento_tipo', coalesce(o.descuento_tipo, c.descuento_tipo),
    'descuento_pct', coalesce(o.descuento_pct, c.descuento_pct),
    'descuento_monto', coalesce(o.descuento_monto, c.descuento_monto),
    'descuento_base', coalesce(o.descuento_base, c.descuento_base),
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
          'horas', oi.horas,
          'por_hora', oi.por_hora,
          'categoria', ct.nombre,
          'categoria_orden', ct.orden
        ) order by oi.orden), '[]'::jsonb)
        from orden_items oi
        left join trabajos tr on tr.id = oi.trabajo_id
        left join categorias_trabajos ct on ct.id = coalesce(oi.categoria_id, tr.categoria_id)
        where oi.orden_id = o.id
      ) else (
        select coalesce(jsonb_agg(jsonb_build_object(
          'descripcion', ci.descripcion,
          'cantidad', ci.cantidad,
          'precio_unitario', ci.precio_unitario,
          'tipo', ci.tipo,
          'tipo_otro', ci.tipo_otro,
          'horas', ci.horas,
          'por_hora', ci.por_hora,
          'categoria', ct.nombre,
          'categoria_orden', ct.orden
        ) order by ci.orden), '[]'::jsonb)
        from cotizacion_items ci
        left join trabajos tr on tr.id = ci.trabajo_id
        left join categorias_trabajos ct on ct.id = coalesce(ci.categoria_id, tr.categoria_id)
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

-- Seguimiento del cliente: igual que v81 + la observación general
create or replace function portal_consultar_orden(p_patente text, p_numero bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip text := reservar_ip();
  v_n int;
  v_res jsonb;
begin
  delete from reservar_limites where creado_en < now() - interval '2 days';
  select count(*) into v_n from reservar_limites
  where ip = v_ip and tipo = 'portal' and creado_en > now() - interval '10 minutes';
  if v_n >= 30 then
    return null;
  end if;
  insert into reservar_limites (ip, tipo) values (v_ip, 'portal');

  select jsonb_build_object(
    'orden_id', o.id,
    'numero', o.numero,
    'estado', o.estado,
    'fecha_ingreso', o.fecha_ingreso,
    'fecha_entrega', o.fecha_entrega,
    'diagnostico', o.diagnostico,
    'avances', o.avances,
    'observacion_general', o.observacion_general,
    'progreso', case when o.progreso is null then null else jsonb_build_object(
                  'pct', o.progreso -> 'pct', 'categorias', o.progreso -> 'categorias', 'actualizado', o.progreso -> 'actualizado') end,
    'con_iva', o.con_iva,
    'descuento_tipo', o.descuento_tipo,
    'descuento_pct', o.descuento_pct,
    'descuento_monto', o.descuento_monto,
    'descuento_base', o.descuento_base,
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
        'precio_unitario', i.precio_unitario,
        'tipo', i.tipo,
        'tipo_otro', i.tipo_otro,
        'horas', i.horas,
        'por_hora', i.por_hora,
        'categoria', ct.nombre,
        'categoria_orden', ct.orden
      ) order by i.orden), '[]'::jsonb)
      from orden_items i
      left join trabajos tr on tr.id = i.trabajo_id
      left join categorias_trabajos ct on ct.id = coalesce(i.categoria_id, tr.categoria_id)
      where i.orden_id = o.id
    )
  )
  into v_res
  from ordenes o
  join vehiculos v on v.id = o.vehiculo_id
  where upper(replace(v.patente, ' ', '')) = upper(replace(p_patente, ' ', ''))
    and o.numero = p_numero
  limit 1;

  return v_res;
end $$;
grant execute on function portal_consultar_orden(text, bigint) to anon;

-- Verificación: debe decir «ok»
select case when exists (select 1 from information_schema.columns where table_name = 'ordenes' and column_name = 'observacion_general')
             and exists (select 1 from information_schema.columns where table_name = 'cotizacion_items' and column_name = 'categoria_id')
             and exists (select 1 from information_schema.columns where table_name = 'orden_items' and column_name = 'categoria_id')
             and exists (select 1 from information_schema.columns where table_name = 'diagnostico_items' and column_name = 'categoria_id')
            then 'ok' else 'revisar' end as v82;
