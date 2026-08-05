-- ============================================================
-- Actualización v27: firma remota del cliente para la inspección
-- de ingreso (checklist de recepción)
--
-- · ordenes.checklist_firma_png / checklist_firma_fecha: firma
--   digital que el cliente registra a distancia, desde el link
--   público inspeccion-ingreso.html (no reemplaza la firma en
--   persona de la recepción, ordenes.firma_cliente_url).
-- · Los ítems de ordenes.checklist_recepcion ahora pueden incluir
--   "fotos": [url, ...] (no requiere cambio de esquema, es jsonb).
-- · portal_consultar_inspeccion_ingreso: lectura pública por id de OT.
-- · portal_firmar_inspeccion_ingreso: guarda la firma del cliente.
-- ============================================================

ALTER TABLE ordenes
ADD COLUMN IF NOT EXISTS checklist_firma_png text,
ADD COLUMN IF NOT EXISTS checklist_firma_fecha timestamptz;

COMMENT ON COLUMN ordenes.checklist_firma_png IS 'Firma digital del cliente (PNG en base64) confirmando la inspección de ingreso, registrada a distancia desde inspeccion-ingreso.html';

create or replace function portal_consultar_inspeccion_ingreso(p_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'numero', o.numero,
    'fecha_ingreso', o.fecha_ingreso,
    'checklist_recepcion', o.checklist_recepcion,
    'checklist_firma_png', o.checklist_firma_png,
    'checklist_firma_fecha', o.checklist_firma_fecha,
    'cliente', jsonb_build_object('nombre', cl.nombre),
    'vehiculo', case when v.id is null then null
      else jsonb_build_object('patente', v.patente, 'marca', v.marca, 'modelo', v.modelo) end,
    'taller', (
      select jsonb_build_object(
        'nombre', nombre, 'telefono', telefono, 'direccion', direccion
      ) from taller_config where id = 1
    )
  )
  from ordenes o
  join clientes cl on cl.id = o.cliente_id
  left join vehiculos v on v.id = o.vehiculo_id
  where o.id = p_id;
$$;

grant execute on function portal_consultar_inspeccion_ingreso(uuid) to anon;

-- El cliente confirma y firma la inspección desde el link público.
create or replace function portal_firmar_inspeccion_ingreso(p_id uuid, p_firma_png text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  update ordenes
  set checklist_firma_png = p_firma_png,
      checklist_firma_fecha = now()
  where id = p_id;
  if not found then
    return 'no_encontrada';
  end if;
  return 'ok';
end $$;

grant execute on function portal_firmar_inspeccion_ingreso(uuid, text) to anon;

select 'v27 firma inspección de ingreso aplicada' as estado;
