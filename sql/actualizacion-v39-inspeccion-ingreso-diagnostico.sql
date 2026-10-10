-- ============================================================
-- Actualización v39: inspección de ingreso dentro del diagnóstico
--
-- El diagnóstico lleva la misma "Inspección de ingreso" que la OT: checklist
-- del estado visual del vehículo (Óptimo / Observación, nota y fotos por
-- ítem) y la firma de conformidad del cliente a distancia, con el mismo
-- registro de respaldo (fecha y hora, ubicación, dispositivo, IP del servidor,
-- nombre y RUT que declara).
--
-- Las columnas se llaman igual que en `ordenes` (checklist_recepcion,
-- checklist_firma_*), así al crear la OT desde el diagnóstico la misma
-- revisión, con su firma, pasa tal cual a la OT.
--
-- · portal_consultar_inspeccion_ingreso / portal_firmar_inspeccion_ingreso
--   ahora sirven tanto a OT como a diagnóstico (el id identifica cuál es):
--   es la misma página pública /inspeccion-ingreso.html?id=...
-- · portal_consultar_diagnostico informa si hay inspección y si está firmada,
--   para que el cliente la vea desde su informe.
-- · La firma del cliente en un diagnóstico genera su aviso en la campanita.
--
-- Requiere v27/v28/v29 (firma en OT), v37 y v38. Seguro de correr más de una vez.
-- ============================================================

alter table diagnosticos
  add column if not exists checklist_recepcion jsonb not null default '[]'::jsonb,
  add column if not exists checklist_firma_png text,
  add column if not exists checklist_firma_fecha timestamptz,
  add column if not exists checklist_firma_lat double precision,
  add column if not exists checklist_firma_lng double precision,
  add column if not exists checklist_firma_dispositivo text,
  add column if not exists checklist_firma_ip text,
  add column if not exists checklist_firma_nombre_declarado text,
  add column if not exists checklist_firma_rut_declarado text;

comment on column diagnosticos.checklist_recepcion is 'Array [{item, estado, nota, fotos}] con el estado visual del vehículo al recibirlo (pasa a la OT al crearla)';

-- ------------------------------------------------------------
-- Página pública de la inspección: sirve a una OT o a un diagnóstico
-- ------------------------------------------------------------
create or replace function portal_consultar_inspeccion_ingreso(p_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'tipo', 'ot',
        'numero', o.numero,
        'fecha_ingreso', o.fecha_ingreso,
        'checklist_recepcion', o.checklist_recepcion,
        'checklist_firma_png', o.checklist_firma_png,
        'checklist_firma_fecha', o.checklist_firma_fecha,
        'checklist_firma_lat', o.checklist_firma_lat,
        'checklist_firma_lng', o.checklist_firma_lng,
        'checklist_firma_dispositivo', o.checklist_firma_dispositivo,
        'checklist_firma_ip', o.checklist_firma_ip,
        'checklist_firma_nombre_declarado', o.checklist_firma_nombre_declarado,
        'checklist_firma_rut_declarado', o.checklist_firma_rut_declarado,
        'cliente', jsonb_build_object('nombre', cl.nombre),
        'vehiculo', case when v.id is null then null
          else jsonb_build_object('patente', v.patente, 'marca', v.marca, 'modelo', v.modelo) end,
        'taller', (
          select jsonb_build_object('nombre', nombre, 'telefono', telefono, 'direccion', direccion)
          from taller_config where id = 1
        )
      )
      from ordenes o
      join clientes cl on cl.id = o.cliente_id
      left join vehiculos v on v.id = o.vehiculo_id
      where o.id = p_id
    ),
    (
      select jsonb_build_object(
        'tipo', 'diagnostico',
        'numero', d.numero,
        'fecha_ingreso', d.fecha,
        'checklist_recepcion', d.checklist_recepcion,
        'checklist_firma_png', d.checklist_firma_png,
        'checklist_firma_fecha', d.checklist_firma_fecha,
        'checklist_firma_lat', d.checklist_firma_lat,
        'checklist_firma_lng', d.checklist_firma_lng,
        'checklist_firma_dispositivo', d.checklist_firma_dispositivo,
        'checklist_firma_ip', d.checklist_firma_ip,
        'checklist_firma_nombre_declarado', d.checklist_firma_nombre_declarado,
        'checklist_firma_rut_declarado', d.checklist_firma_rut_declarado,
        'cliente', jsonb_build_object('nombre', cl.nombre),
        'vehiculo', case when v.id is null then null
          else jsonb_build_object('patente', v.patente, 'marca', v.marca, 'modelo', v.modelo) end,
        'taller', (
          select jsonb_build_object('nombre', nombre, 'telefono', telefono, 'direccion', direccion)
          from taller_config where id = 1
        )
      )
      from diagnosticos d
      join clientes cl on cl.id = d.cliente_id
      left join vehiculos v on v.id = d.vehiculo_id
      where d.id = p_id
    )
  );
$$;

grant execute on function portal_consultar_inspeccion_ingreso(uuid) to anon;

-- ------------------------------------------------------------
-- Firma del cliente (misma firma de la v29; ahora también para diagnósticos)
-- La IP se lee de los headers que reenvía PostgREST, no del cliente.
-- ------------------------------------------------------------
create or replace function portal_firmar_inspeccion_ingreso(
  p_id uuid,
  p_firma_png text,
  p_lat double precision default null,
  p_lng double precision default null,
  p_dispositivo text default null,
  p_nombre_declarado text default null,
  p_rut_declarado text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip text;
begin
  v_ip := nullif(split_part(coalesce((current_setting('request.headers', true)::json ->> 'x-forwarded-for'), ''), ',', 1), '');

  update ordenes
  set checklist_firma_png = p_firma_png,
      checklist_firma_fecha = now(),
      checklist_firma_lat = p_lat,
      checklist_firma_lng = p_lng,
      checklist_firma_dispositivo = p_dispositivo,
      checklist_firma_ip = v_ip,
      checklist_firma_nombre_declarado = p_nombre_declarado,
      checklist_firma_rut_declarado = p_rut_declarado
  where id = p_id;
  if found then
    return 'ok';
  end if;

  update diagnosticos
  set checklist_firma_png = p_firma_png,
      checklist_firma_fecha = now(),
      checklist_firma_lat = p_lat,
      checklist_firma_lng = p_lng,
      checklist_firma_dispositivo = p_dispositivo,
      checklist_firma_ip = v_ip,
      checklist_firma_nombre_declarado = p_nombre_declarado,
      checklist_firma_rut_declarado = p_rut_declarado
  where id = p_id;
  if found then
    return 'ok';
  end if;

  return 'no_encontrada';
end $$;

grant execute on function portal_firmar_inspeccion_ingreso(uuid, text, double precision, double precision, text, text, text) to anon;

-- ------------------------------------------------------------
-- Aviso en la campanita cuando el cliente firma la inspección de un diagnóstico
-- ------------------------------------------------------------
create or replace function notif_inspeccion_diagnostico_firmada()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cli text;
  v_pat text;
begin
  begin
    if notif_es_taller() then
      return new;
    end if;
    select nombre into v_cli from clientes where id = new.cliente_id;
    select patente into v_pat from vehiculos where id = new.vehiculo_id;
    insert into notificaciones (tipo, titulo, detalle, url)
    values (
      'inspeccion_firmada',
      'Inspección de ingreso firmada · DIAG-' || lpad(new.numero::text, 4, '0'),
      coalesce(v_cli, 'Cliente') || case when v_pat is not null then ' · ' || v_pat else '' end,
      'diagnosticos.html?id=' || new.id::text
    );
  exception when others then
    null;
  end;
  return new;
end $$;

drop trigger if exists trg_notif_inspeccion_diagnostico_firmada on diagnosticos;
create trigger trg_notif_inspeccion_diagnostico_firmada
  after update of checklist_firma_fecha on diagnosticos
  for each row when (
    new.checklist_firma_fecha is not null
    and new.checklist_firma_fecha is distinct from old.checklist_firma_fecha
  )
  execute function notif_inspeccion_diagnostico_firmada();

-- ------------------------------------------------------------
-- Informe público del diagnóstico: ahora informa la inspección de ingreso
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

select 'v39 inspección de ingreso en diagnósticos aplicado' as estado;
