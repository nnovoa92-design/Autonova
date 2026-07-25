-- ============================================================
-- Actualización v16: Políticas generales del taller + inspección
-- de recepción de vehículo con firma digital
--
-- · taller_config.politicas_generales_texto: cláusulas legales
--   editables (retiro de vehículo, pertenencias, garantía general,
--   legalidades), impresas como letra chica en Cotización y OT
-- · ordenes.garantia_especial: campo libre editable por OT, aparte
--   de las políticas generales, para condiciones especiales de
--   garantía de ese trabajo puntual
-- · ordenes.nivel_combustible / checklist_recepcion /
--   pertenencias_declaradas / firma_cliente_url / firma_fecha:
--   checklist de recepción con firma digital del cliente
-- ============================================================

ALTER TABLE taller_config
ADD COLUMN IF NOT EXISTS politicas_generales_texto text DEFAULT
'RETIRO DEL VEHÍCULO
El vehículo debe ser retirado dentro de 2 días corridos desde que se notifica que está listo. Pasado ese plazo, se cobrará un bodegaje de $3.500 por día. Si transcurren 15 días sin retiro ni respuesta del cliente pese a los intentos de contacto, Autonova se reserva el derecho de proceder según lo establecido en la normativa vigente.

PERTENENCIAS Y OBJETOS PERSONALES
Se recomienda al cliente retirar objetos de valor antes de dejar el vehículo. Autonova no se responsabiliza por objetos personales no declarados expresamente en la recepción. Los objetos visibles al momento del ingreso quedan registrados en el checklist de recepción.

GARANTÍA GENERAL
Los trabajos realizados cuentan con garantía general de 3 meses, sin perjuicio de garantías específicas mayores indicadas para el servicio realizado en esta orden. La garantía no cubre: mal uso, modificaciones no autorizadas, repuestos no instalados por Autonova, desgaste normal, ni fallas por falta de mantenciones posteriores.

LEGALIDADES Y RESPONSABILIDAD
Autonova no responde por daños o fallas preexistentes no declaradas en la recepción del vehículo. La responsabilidad de Autonova se limita al valor del trabajo facturado, salvo dolo o negligencia grave. Se emite boleta o factura por cada servicio, conforme a la Ley N° 19.496 sobre Protección de los Derechos de los Consumidores.

INSPECCIÓN DE RECEPCIÓN
Al ingresar el vehículo se registra kilometraje, nivel de combustible, estado visual de la carrocería y pertenencias visibles. La firma del cliente valida su conformidad con este registro.';

ALTER TABLE ordenes
ADD COLUMN IF NOT EXISTS garantia_especial text,
ADD COLUMN IF NOT EXISTS nivel_combustible text,
ADD COLUMN IF NOT EXISTS checklist_recepcion jsonb DEFAULT '[]'::jsonb,
ADD COLUMN IF NOT EXISTS pertenencias_declaradas text,
ADD COLUMN IF NOT EXISTS firma_cliente_url text,
ADD COLUMN IF NOT EXISTS firma_fecha timestamptz;

COMMENT ON COLUMN ordenes.garantia_especial IS 'Condición de garantía especial para este trabajo puntual, aparte de la política general del taller';
COMMENT ON COLUMN ordenes.checklist_recepcion IS 'Array [{item, marcado, nota}] con el estado visual registrado al recibir el vehículo';

-- El link público de cotización también debe mostrar las políticas generales
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
        'politicas_generales_texto', politicas_generales_texto
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
          'tipo_otro', oi.tipo_otro
        ) order by oi.orden), '[]'::jsonb)
        from orden_items oi where oi.orden_id = o.id
      ) else (
        select coalesce(jsonb_agg(jsonb_build_object(
          'descripcion', ci.descripcion,
          'cantidad', ci.cantidad,
          'precio_unitario', ci.precio_unitario,
          'tipo', ci.tipo,
          'tipo_otro', ci.tipo_otro
        ) order by ci.orden), '[]'::jsonb)
        from cotizacion_items ci where ci.cotizacion_id = c.id
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

select 'v16 politicas + recepcion aplicada' as estado;
