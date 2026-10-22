-- ============================================================
-- Actualización v56: tipo, horas de trabajo y cantidad en columnas separadas (cotizaciones, OT y diagnósticos)
--
-- Las líneas de mano de obra del catálogo ahora guardan:
--   horas     = horas de trabajo POR TRABAJO
--   por_hora  = true si precio_unitario es el valor de la HORA (cantidad = horas × veces);
--               false si es el precio de cada trabajo (cantidad = veces)
-- El total sigue siendo cantidad × precio_unitario (no cambia ningún monto). Con esto las pantallas del cliente
-- (link de cotización, seguimiento de OT, informe de diagnóstico) muestran columnas separadas:
-- tipo · horas de trabajo · cantidad · precio unitario · total.
--
-- También se rellenan las líneas antiguas, cuando se puede deducir del catálogo (solo datos descriptivos: no se
-- toca ningún precio ni cantidad). Las líneas libres sin trabajo del catálogo quedan sin horas, como siempre.
--
-- Requiere v43 y v49. Seguro de correr más de una vez.
-- ============================================================

alter table cotizacion_items  add column if not exists horas numeric(8,2), add column if not exists por_hora boolean;
alter table orden_items       add column if not exists horas numeric(8,2), add column if not exists por_hora boolean;
alter table diagnostico_items add column if not exists horas numeric(8,2), add column if not exists por_hora boolean;

comment on column cotizacion_items.horas is 'Mano de obra: horas de trabajo por trabajo (informativo para el cliente).';
comment on column cotizacion_items.por_hora is 'Mano de obra: true = precio_unitario es el valor de la hora; false = es el precio de cada trabajo.';

-- ------------------------------------------------------------
-- Relleno de líneas antiguas de mano de obra con trabajo del catálogo
--   · si el trabajo tiene precio fijo u opciones: precio por trabajo, horas = las del catálogo (o de la opción elegida)
--   · si no: se cobra por hora; veces = (xN) de la descripción (o 1) y horas = cantidad / veces
-- ------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['cotizacion_items', 'orden_items', 'diagnostico_items'] loop
    execute format($f$
      update %1$I i set
        por_hora = x.por_hora,
        horas = x.horas
      from (
        select i2.id,
               (tr.precio_fijo is null and (case when jsonb_typeof(tr.opciones) = 'array' then jsonb_array_length(tr.opciones) else 0 end) = 0) as por_hora,
               case
                 when tr.precio_fijo is null and (case when jsonb_typeof(tr.opciones) = 'array' then jsonb_array_length(tr.opciones) else 0 end) = 0 then
                   round(i2.cantidad / coalesce(nullif((substring(i2.descripcion from '\(x([0-9]+)\)\s*$'))::numeric, 0), 1), 2)
                 else coalesce(
                   (select nullif(nullif(o ->> 'horas', '')::numeric, 0)
                      from jsonb_array_elements(case when jsonb_typeof(tr.opciones) = 'array' then tr.opciones else '[]'::jsonb end) o
                     where i2.descripcion like '%% — ' || (o ->> 'nombre') || '%%' limit 1),
                   nullif(tr.horas_estimadas, 0))
               end as horas
        from %1$I i2
        join trabajos tr on tr.id = i2.trabajo_id
        where i2.tipo = 'mano_obra' and i2.horas is null and i2.por_hora is null
      ) x
      where i.id = x.id
    $f$, t);
  end loop;
end $$;

-- Línea del diagnóstico («Diagnóstico (X h de taller)»): horas × valor hora
update cotizacion_items set por_hora = true, horas = cantidad
  where tipo = 'mano_obra' and trabajo_id is null and horas is null and por_hora is null and descripcion like 'Diagnóstico (%h de taller)%';
update orden_items set por_hora = true, horas = cantidad
  where tipo = 'mano_obra' and trabajo_id is null and horas is null and por_hora is null and descripcion like 'Diagnóstico (%h de taller)%';

-- ------------------------------------------------------------
-- Link público de la cotización
-- ------------------------------------------------------------
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
          'horas', ci.horas,
          'por_hora', ci.por_hora,
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

-- ------------------------------------------------------------
-- Seguimiento de la OT por el cliente (patente + número)
-- ------------------------------------------------------------
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
        'por_hora', i.por_hora
      ) order by i.orden), '[]'::jsonb)
      from orden_items i where i.orden_id = o.id
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

-- ------------------------------------------------------------
-- Informe público del diagnóstico
-- ------------------------------------------------------------
create or replace function portal_consultar_diagnostico(p_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  with d as (
    select * from diagnosticos where id = p_id
  ),
  c as (
    select c.* from cotizaciones c join d on c.id = d.cotizacion_id
  ),
  o as (
    select o.* from ordenes o join c on o.cotizacion_id = c.id
    order by o.creado_en asc limit 1
  )
  select jsonb_build_object(
    'numero', d.numero,
    'fecha', d.fecha,
    'km', d.km,
    'motivo', d.motivo,
    'hallazgos', d.hallazgos,
    'conclusion', d.conclusion,
    'respuesta', d.respuesta,
    'respuesta_fecha', d.respuesta_fecha,
    'inspeccion', case when jsonb_array_length(d.checklist_recepcion) > 0 then jsonb_build_object(
        'items', jsonb_array_length(d.checklist_recepcion),
        'firmada', d.checklist_firma_png is not null,
        'firma_fecha', d.checklist_firma_fecha
      ) else null end,
    'diagnostico', jsonb_build_object(
      'horas', d.horas_diagnostico,
      'valor_hora', d.valor_hora_diagnostico,
      'monto', d.horas_diagnostico * d.valor_hora_diagnostico
    ),
    'descuento_tipo', coalesce(o.descuento_tipo, c.descuento_tipo, d.descuento_tipo),
    'descuento_pct', coalesce(o.descuento_pct, c.descuento_pct, d.descuento_pct),
    'descuento_monto', coalesce(o.descuento_monto, c.descuento_monto, d.descuento_monto),
    'descuento_base', coalesce(o.descuento_base, c.descuento_base, d.descuento_base),
    'con_iva', coalesce(o.con_iva, c.con_iva, d.con_iva),
    'cliente', jsonb_build_object('nombre', cl.nombre),
    'vehiculo', case when v.id is null then null
      else jsonb_build_object('patente', v.patente, 'marca', v.marca, 'modelo', v.modelo, 'anio', v.anio) end,
    'taller', (
      select jsonb_build_object(
        'nombre', nombre, 'telefono', telefono,
        'direccion', direccion, 'iva_pct', iva_pct,
        'politica_inspeccion_texto', politica_inspeccion_texto,
        'politicas_generales_texto', politicas_generales_texto
      ) from taller_config where id = 1
    ),
    'cotizacion', case when c.id is null then null
      else jsonb_build_object('id', c.id, 'numero', c.numero, 'estado', c.estado) end,
    'orden', case when o.id is null then null
      else jsonb_build_object('numero', o.numero, 'estado', o.estado) end,
    'items', case
      when o.id is not null then (
        select coalesce(jsonb_agg(jsonb_build_object(
          'descripcion', oi.descripcion, 'cantidad', oi.cantidad,
          'precio_unitario', oi.precio_unitario, 'tipo', oi.tipo, 'tipo_otro', oi.tipo_otro,
          'horas', oi.horas, 'por_hora', oi.por_hora
        ) order by oi.orden), '[]'::jsonb)
        from orden_items oi where oi.orden_id = o.id
      )
      when c.id is not null then (
        select coalesce(jsonb_agg(jsonb_build_object(
          'descripcion', ci.descripcion, 'cantidad', ci.cantidad,
          'precio_unitario', ci.precio_unitario, 'tipo', ci.tipo, 'tipo_otro', ci.tipo_otro,
          'horas', ci.horas, 'por_hora', ci.por_hora
        ) order by ci.orden), '[]'::jsonb)
        from cotizacion_items ci where ci.cotizacion_id = c.id
      )
      else (
        -- Sin cotización/OT: el diagnóstico (horas x valor hora) va primero, luego los trabajos recomendados
        select coalesce(jsonb_agg(q.linea order by q.ord, q.sub), '[]'::jsonb)
        from (
          select 0 as ord, 0 as sub, jsonb_build_object(
            'descripcion', 'Diagnóstico', 'cantidad', d.horas_diagnostico,
            'precio_unitario', d.valor_hora_diagnostico, 'tipo', 'mano_obra', 'tipo_otro', null,
            'horas', d.horas_diagnostico, 'por_hora', true,
            'es_diagnostico', true
          ) as linea
          where d.horas_diagnostico > 0 and d.valor_hora_diagnostico > 0
          union all
          select 1, di.orden, jsonb_build_object(
            'descripcion', di.descripcion, 'cantidad', di.cantidad,
            'precio_unitario', di.precio_unitario, 'tipo', di.tipo, 'tipo_otro', di.tipo_otro,
            'horas', di.horas, 'por_hora', di.por_hora
          )
          from diagnostico_items di where di.diagnostico_id = d.id
        ) q
      )
    end
  )
  from d
  join clientes cl on cl.id = d.cliente_id
  left join vehiculos v on v.id = d.vehiculo_id
  left join c on true
  left join o on true;
$$;

grant execute on function portal_consultar_diagnostico(uuid) to anon;

select 'v56 tipo, horas y cantidad en columnas aplicado' as estado,
       (select count(*) from cotizacion_items where horas is not null) as cotizacion_con_horas,
       (select count(*) from orden_items where horas is not null) as orden_con_horas,
       (select count(*) from diagnostico_items where horas is not null) as diagnostico_con_horas;
