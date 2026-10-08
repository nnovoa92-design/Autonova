-- ============================================================
-- Actualización v34: valor del diagnóstico y pruebas/monitoreos
--
-- · diagnosticos.horas_diagnostico / valor_hora_diagnostico: horas de
--   taller dedicadas a diagnosticar y el valor hora con que se cobran
--   (se guarda el valor hora de ese día, así un cambio posterior en
--   Configuración no altera diagnósticos ya hechos).
--   El valor del diagnóstico = horas x valor hora, y es lo único que se
--   cobra si el cliente no aprueba los trabajos recomendados.
-- · Las pruebas y monitoreos siguen guardándose en diagnosticos.hallazgos
--   ([{item: nombre de la prueba, nota: resultado, fotos}]); no cambia la
--   tabla. Los diagnósticos antiguos (Óptimo/Observación) se siguen leyendo.
-- · portal_consultar_diagnostico (link público) ahora informa el valor del
--   diagnóstico y lo incluye como primera línea mientras el diagnóstico no
--   se haya convertido en cotización/OT (al convertir, esa línea ya viaja
--   dentro de la cotización/OT).
--
-- Requiere v32 y v33. Seguro de correr más de una vez.
-- ============================================================

alter table diagnosticos
  add column if not exists horas_diagnostico numeric(6,2) not null default 0,
  add column if not exists valor_hora_diagnostico numeric(12,2) not null default 0;

comment on column diagnosticos.horas_diagnostico is 'Horas de taller dedicadas al diagnóstico';
comment on column diagnosticos.valor_hora_diagnostico is 'Valor hora (neto) con que se cobra el diagnóstico; valor del diagnóstico = horas x valor hora';

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
    'descuento_pct', coalesce(o.descuento_pct, c.descuento_pct, d.descuento_pct),
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

select 'v34 valor del diagnóstico aplicado' as estado;
