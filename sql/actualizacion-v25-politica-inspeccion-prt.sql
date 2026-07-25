-- ============================================================
-- Actualización v25: Políticas específicas de Inspección y PRT
--
-- Se agregan como texto en taller_config (dos cláusulas separadas,
-- cada una se imprime solo si la cotización/OT incluye un trabajo de
-- esa categoría). Se crea la categoría "Revisión Técnica" si no existe,
-- para poder asociarle el trabajo de traslado/gestión de PRT.
-- ============================================================

insert into categorias_trabajos (nombre, orden)
values ('Revisión Técnica', 12)
on conflict (nombre) do nothing;

ALTER TABLE taller_config
ADD COLUMN IF NOT EXISTS politica_inspeccion_texto text,
ADD COLUMN IF NOT EXISTS politica_revision_tecnica_texto text;

update taller_config set
  politica_inspeccion_texto = 'INSPECCIÓN
Este servicio corresponde a una evaluación visual y diagnóstica según los puntos revisados en esa fecha. No garantiza la detección de la totalidad de fallas posibles, especialmente aquellas no visibles o intermitentes. No incluye reparación; cualquier trabajo adicional será cotizado por separado.',
  politica_revision_tecnica_texto = 'REVISIÓN TÉCNICA (PRT) Y SERVICIO DE TRASLADO
Autonova no controla ni garantiza el resultado de la revisión técnica, el cual depende exclusivamente de los criterios de la Planta de Revisión Técnica. Si el vehículo no aprueba, los trabajos necesarios para una nueva revisión serán cotizados aparte, si así el cliente lo acepta. Los tiempos de traslado y trámite dependen de la disponibilidad de la planta externa y pueden variar por causas ajenas a Autonova. En caso de rechazo instrumental u otro que no sea visual, el cliente deberá pagar las reparaciones y $10.000 adicionales por concepto de traslado para una nueva evaluación en planta. Si el rechazo es por causas visuales (ej. luces o tuercas faltantes), Autonova se hará cargo de las reparaciones y de la nueva inspección.'
where id = 1;

-- El link público también debe poder mostrar estas cláusulas cuando
-- corresponda, y necesita la categoría de cada ítem para saberlo.
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

select 'v25 politica inspeccion y prt aplicada' as estado;
