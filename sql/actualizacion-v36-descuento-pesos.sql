-- ============================================================
-- Actualización v36: descuentos en % o en pesos
--
-- Cotizaciones, órdenes de trabajo y diagnósticos pasan a poder llevar el
-- descuento de dos formas, a elección de quien lo ingresa:
--   · descuento_tipo = 'pct'   -> un porcentaje (descuento_pct). El monto
--                                 en pesos se recalcula si cambian los ítems.
--   · descuento_tipo = 'monto' -> un valor fijo en pesos (descuento_monto).
--                                 Queda igual aunque cambien los ítems; el %
--                                 equivalente se muestra como referencia.
-- En ambos casos el cliente ve el porcentaje y los pesos.
--
-- Todo lo existente queda como estaba (tipo 'pct', con su porcentaje).
-- Las tres funciones públicas (links de cotización, seguimiento de OT e
-- informe de diagnóstico) devuelven el descuento ya con su tipo y monto.
-- Siguen la regla de siempre: el documento más avanzado manda
-- (OT -> cotización -> diagnóstico).
--
-- Requiere v30 (descuento en OT), v32/v34 (diagnósticos). Seguro de correr
-- más de una vez.
-- ============================================================

alter table cotizaciones
  add column if not exists descuento_tipo text not null default 'pct',
  add column if not exists descuento_monto numeric(12,2) not null default 0;
alter table ordenes
  add column if not exists descuento_tipo text not null default 'pct',
  add column if not exists descuento_monto numeric(12,2) not null default 0;
alter table diagnosticos
  add column if not exists descuento_tipo text not null default 'pct',
  add column if not exists descuento_monto numeric(12,2) not null default 0;

do $$
declare t text;
begin
  foreach t in array array['cotizaciones', 'ordenes', 'diagnosticos'] loop
    if not exists (select 1 from pg_constraint where conname = t || '_descuento_tipo_check') then
      execute format('alter table %I add constraint %I check (descuento_tipo in (''pct'', ''monto''))', t, t || '_descuento_tipo_check');
    end if;
  end loop;
end $$;

comment on column cotizaciones.descuento_tipo is 'pct = porcentaje (descuento_pct); monto = valor fijo en pesos (descuento_monto)';
comment on column ordenes.descuento_tipo is 'pct = porcentaje (descuento_pct); monto = valor fijo en pesos (descuento_monto)';
comment on column diagnosticos.descuento_tipo is 'pct = porcentaje (descuento_pct); monto = valor fijo en pesos (descuento_monto)';

-- ------------------------------------------------------------
-- Link público de cotización
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

-- ------------------------------------------------------------
-- Seguimiento de la OT por el cliente (patente + número)
-- ------------------------------------------------------------
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
    'descuento_tipo', o.descuento_tipo,
    'descuento_pct', o.descuento_pct,
    'descuento_monto', o.descuento_monto,
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
    'diagnostico', jsonb_build_object(
      'horas', d.horas_diagnostico,
      'valor_hora', d.valor_hora_diagnostico,
      'monto', d.horas_diagnostico * d.valor_hora_diagnostico
    ),
    'descuento_tipo', coalesce(o.descuento_tipo, c.descuento_tipo, d.descuento_tipo),
    'descuento_pct', coalesce(o.descuento_pct, c.descuento_pct, d.descuento_pct),
    'descuento_monto', coalesce(o.descuento_monto, c.descuento_monto, d.descuento_monto),
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
          'precio_unitario', oi.precio_unitario, 'tipo', oi.tipo, 'tipo_otro', oi.tipo_otro
        ) order by oi.orden), '[]'::jsonb)
        from orden_items oi where oi.orden_id = o.id
      )
      when c.id is not null then (
        select coalesce(jsonb_agg(jsonb_build_object(
          'descripcion', ci.descripcion, 'cantidad', ci.cantidad,
          'precio_unitario', ci.precio_unitario, 'tipo', ci.tipo, 'tipo_otro', ci.tipo_otro
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
            'es_diagnostico', true
          ) as linea
          where d.horas_diagnostico > 0 and d.valor_hora_diagnostico > 0
          union all
          select 1, di.orden, jsonb_build_object(
            'descripcion', di.descripcion, 'cantidad', di.cantidad,
            'precio_unitario', di.precio_unitario, 'tipo', di.tipo, 'tipo_otro', di.tipo_otro
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

select 'v36 descuentos en % o pesos aplicado' as estado;
