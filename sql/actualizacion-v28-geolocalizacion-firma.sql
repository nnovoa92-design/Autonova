-- ============================================================
-- Actualización v28: geolocalización de la firma remota de la
-- inspección de ingreso
--
-- Cuando el cliente firma a distancia desde inspeccion-ingreso.html,
-- además de la firma se guarda la coordenada del dispositivo (si el
-- cliente autoriza el permiso de ubicación del navegador), como
-- respaldo de desde dónde se firmó.
-- ============================================================

ALTER TABLE ordenes
ADD COLUMN IF NOT EXISTS checklist_firma_lat double precision,
ADD COLUMN IF NOT EXISTS checklist_firma_lng double precision;

COMMENT ON COLUMN ordenes.checklist_firma_lat IS 'Latitud del dispositivo del cliente al firmar la inspección de ingreso a distancia (null si no autorizó ubicación)';
COMMENT ON COLUMN ordenes.checklist_firma_lng IS 'Longitud del dispositivo del cliente al firmar la inspección de ingreso a distancia (null si no autorizó ubicación)';

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
    'checklist_firma_lat', o.checklist_firma_lat,
    'checklist_firma_lng', o.checklist_firma_lng,
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

-- El cliente confirma y firma la inspección desde el link público,
-- opcionalmente con su ubicación (lat/lng nulos si no la autorizó).
-- Se elimina la firma de 2 argumentos de v27: "create or replace" no
-- puede agregar parámetros, crearía una función sobrecargada aparte
-- y PostgREST no podría elegir cuál usar.
drop function if exists portal_firmar_inspeccion_ingreso(uuid, text);

create or replace function portal_firmar_inspeccion_ingreso(p_id uuid, p_firma_png text, p_lat double precision default null, p_lng double precision default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  update ordenes
  set checklist_firma_png = p_firma_png,
      checklist_firma_fecha = now(),
      checklist_firma_lat = p_lat,
      checklist_firma_lng = p_lng
  where id = p_id;
  if not found then
    return 'no_encontrada';
  end if;
  return 'ok';
end $$;

grant execute on function portal_firmar_inspeccion_ingreso(uuid, text, double precision, double precision) to anon;

select 'v28 geolocalización de firma aplicada' as estado;
