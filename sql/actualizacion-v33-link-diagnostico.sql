-- ============================================================
-- Actualización v33: link público del informe de diagnóstico
--
-- Igual que la cotización (portal_consultar_cotizacion): el cliente abre
-- /diagnostico.html?id=<uuid> y ve el informe completo -revisión con
-- notas y fotos, conclusión, trabajos recomendados y total estimado-
-- sin necesidad de iniciar sesión. El uuid del diagnóstico hace de
-- llave: la función solo devuelve ese diagnóstico.
--
-- Mismas reglas de sincronización que el resto: las líneas, el descuento
-- y el IVA salen del documento más avanzado (OT -> cotización ->
-- diagnóstico), así el cliente siempre ve los valores vigentes.
--
-- No cambia tablas. Requiere v32 (diagnosticos). Seguro de correr más
-- de una vez.
-- ============================================================

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
        select coalesce(jsonb_agg(jsonb_build_object(
          'descripcion', di.descripcion, 'cantidad', di.cantidad,
          'precio_unitario', di.precio_unitario, 'tipo', di.tipo, 'tipo_otro', di.tipo_otro
        ) order by di.orden), '[]'::jsonb)
        from diagnostico_items di where di.diagnostico_id = d.id
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

select 'v33 link de diagnóstico aplicado' as estado;
