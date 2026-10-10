-- ============================================================
-- Actualización v37: respuesta del cliente al diagnóstico (aceptar / rechazar)
--
-- En el link del informe, el cliente decide si realiza los trabajos
-- recomendados:
--   · aceptado  -> quiere los trabajos (diagnóstico + trabajos).
--   · rechazado -> no por ahora: solo se cobra el valor del diagnóstico.
-- El taller también puede registrar la respuesta (cuando el cliente
-- contesta por teléfono o WhatsApp): respuesta_origen = 'taller'.
--
-- Aceptar NO crea nada solo: el diagnóstico queda "Aceptado" y el taller
-- genera la cotización + OT con un clic, cuando quiera.
--
-- · portal_responder_diagnostico(p_id, p_respuesta): la llama el cliente
--   desde su link. Solo responde si aún está pendiente; la IP se toma del
--   servidor (headers), no la envía el cliente.
-- · portal_consultar_diagnostico ahora informa respuesta y fecha.
--
-- Requiere v32, v34 y v36. Seguro de correr más de una vez.
-- ============================================================

alter table diagnosticos
  add column if not exists respuesta text not null default 'pendiente',
  add column if not exists respuesta_fecha timestamptz,
  add column if not exists respuesta_origen text,
  add column if not exists respuesta_ip text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'diagnosticos_respuesta_check') then
    alter table diagnosticos add constraint diagnosticos_respuesta_check
      check (respuesta in ('pendiente', 'aceptado', 'rechazado'));
  end if;
end $$;

comment on column diagnosticos.respuesta is 'Respuesta del cliente a los trabajos recomendados: pendiente | aceptado | rechazado (rechazado = solo se cobra el diagnóstico)';
comment on column diagnosticos.respuesta_origen is 'cliente (desde el link) o taller (la registró el taller)';
comment on column diagnosticos.respuesta_ip is 'IP del cliente al responder desde el link, capturada en el servidor';

-- El cliente responde desde su link
create or replace function portal_responder_diagnostico(p_id uuid, p_respuesta text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actual text;
  v_ip text;
begin
  if p_respuesta is null or p_respuesta not in ('aceptado', 'rechazado') then
    return 'invalido';
  end if;
  select respuesta into v_actual from diagnosticos where id = p_id;
  if not found then
    return 'no_encontrado';
  end if;
  if v_actual <> 'pendiente' then
    return 'ya_respondido';
  end if;
  v_ip := nullif(split_part(coalesce((current_setting('request.headers', true)::json ->> 'x-forwarded-for'), ''), ',', 1), '');
  update diagnosticos
  set respuesta = p_respuesta,
      respuesta_fecha = now(),
      respuesta_origen = 'cliente',
      respuesta_ip = v_ip
  where id = p_id;
  return 'ok';
end $$;

grant execute on function portal_responder_diagnostico(uuid, text) to anon;

-- Informe público: ahora también informa la respuesta
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

select 'v37 respuesta del cliente al diagnóstico aplicado' as estado;
