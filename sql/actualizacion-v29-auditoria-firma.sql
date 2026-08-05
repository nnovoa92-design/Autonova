-- ============================================================
-- Actualización v29: registro de auditoría de la firma (respaldo
-- legal ante un "yo no firmé"), igual a como se trabajó en aivimed
--
-- Para AMBAS firmas (en sala y remota) se guarda el dispositivo desde
-- donde se firmó. Para la firma remota, además:
--  · IP del firmante: se captura en el servidor (headers de la
--    solicitud a través de PostgREST), nunca la envía el cliente.
--  · Firmante declarado (nombre + RUT): lo tipea la persona al firmar,
--    como declaración propia, además del nombre que ya tiene el taller
--    registrado para ese cliente.
-- ============================================================

ALTER TABLE ordenes
ADD COLUMN IF NOT EXISTS firma_dispositivo text,
ADD COLUMN IF NOT EXISTS checklist_firma_dispositivo text,
ADD COLUMN IF NOT EXISTS checklist_firma_ip text,
ADD COLUMN IF NOT EXISTS checklist_firma_nombre_declarado text,
ADD COLUMN IF NOT EXISTS checklist_firma_rut_declarado text;

COMMENT ON COLUMN ordenes.firma_dispositivo IS 'Dispositivo (SO · navegador) usado para la firma en sala al recibir el vehículo';
COMMENT ON COLUMN ordenes.checklist_firma_dispositivo IS 'Dispositivo (SO · navegador) del cliente al firmar la inspección de ingreso a distancia';
COMMENT ON COLUMN ordenes.checklist_firma_ip IS 'IP del cliente al firmar a distancia, capturada en el servidor (headers de PostgREST), no enviada por el cliente';
COMMENT ON COLUMN ordenes.checklist_firma_nombre_declarado IS 'Nombre que la persona tipeó como declaración propia al firmar a distancia';
COMMENT ON COLUMN ordenes.checklist_firma_rut_declarado IS 'RUT que la persona tipeó como declaración propia al firmar a distancia';

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
    'checklist_firma_dispositivo', o.checklist_firma_dispositivo,
    'checklist_firma_ip', o.checklist_firma_ip,
    'checklist_firma_nombre_declarado', o.checklist_firma_nombre_declarado,
    'checklist_firma_rut_declarado', o.checklist_firma_rut_declarado,
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

-- Se eliminan las firmas anteriores de la función (v27 y v28): "create or
-- replace" no puede agregar parámetros nuevos sin volverse una sobrecarga
-- aparte, y PostgREST no podría elegir cuál usar. Se listan ambas por si
-- esta actualización se corre sin haber aplicado v28 antes.
drop function if exists portal_firmar_inspeccion_ingreso(uuid, text);
drop function if exists portal_firmar_inspeccion_ingreso(uuid, text, double precision, double precision);

-- El cliente confirma y firma la inspección desde el link público.
-- La IP se lee de los headers que reenvía PostgREST, no del cliente.
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
  if not found then
    return 'no_encontrada';
  end if;
  return 'ok';
end $$;

grant execute on function portal_firmar_inspeccion_ingreso(uuid, text, double precision, double precision, text, text, text) to anon;

select 'v29 auditoría de firma aplicada' as estado;
