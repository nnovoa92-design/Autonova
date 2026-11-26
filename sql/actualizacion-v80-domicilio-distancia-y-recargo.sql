-- ============================================================
-- v80 — A domicilio: dirección con Google Maps y recargo por distancia
--
--  * En la reserva el cliente busca su dirección (sugerencias de Google Maps) o usa su ubicación actual.
--    Se mide la distancia en línea recta («a la redonda») desde el taller.
--  * Hasta el radio sin recargo (6 km por defecto) no se cobra extra. Pasado el radio se cobra cada
--    km extra o fracción ($3.000 por defecto, neto + IVA como el resto de los valores).
--  * La cita guarda la ubicación, los km y el recargo. La agenda lo muestra con un link «Cómo llegar»
--    y al crear la OT se agrega la línea del recargo.
--  * La clave de Google Maps y la ubicación del taller se configuran en
--    Configuración → Atención a domicilio.
--
-- Requiere v79. Seguro de correr más de una vez.
-- ============================================================

alter table taller_config add column if not exists domicilio_km jsonb not null default '{}'::jsonb;
alter table taller_config add column if not exists google_maps_key text;

alter table citas add column if not exists dom_lat double precision;
alter table citas add column if not exists dom_lng double precision;
alter table citas add column if not exists dom_km numeric(7,1);
alter table citas add column if not exists dom_recargo integer;

-- Configuración del recargo: { radio_km, valor_km, lat, lng } (lat/lng = ubicación del taller)
create or replace function _domicilio_km_cfg() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('radio_km', 6, 'valor_km', 3000) || coalesce(domicilio_km, '{}'::jsonb)
    from taller_config where id = 1;
$$;
revoke execute on function _domicilio_km_cfg() from public, anon, authenticated;

-- Distancia en línea recta desde el taller y su recargo (igual que distanciaKm / recargoDistancia en mapsDireccion.js).
-- Devuelve null si el taller no tiene ubicación o las coordenadas no son válidas.
create or replace function _recargo_distancia(p_lat double precision, p_lng double precision) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_cfg jsonb := _domicilio_km_cfg();
  v_olat double precision; v_olng double precision;
  v_radio numeric; v_valor numeric; v_km numeric; v_extra int; v_a double precision;
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then return null; end if;
  if v_cfg ->> 'lat' is null or v_cfg ->> 'lng' is null then return null; end if;
  v_olat := (v_cfg ->> 'lat')::double precision;
  v_olng := (v_cfg ->> 'lng')::double precision;
  v_radio := greatest(0, coalesce((v_cfg ->> 'radio_km')::numeric, 6));
  v_valor := greatest(0, coalesce((v_cfg ->> 'valor_km')::numeric, 0));
  -- Haversine (radio de la Tierra 6371 km)
  v_a := power(sin(radians(p_lat - v_olat) / 2), 2)
       + cos(radians(v_olat)) * cos(radians(p_lat)) * power(sin(radians(p_lng - v_olng) / 2), 2);
  v_km := round((2 * 6371 * asin(least(1, sqrt(v_a))))::numeric, 1);
  v_extra := case when v_km > v_radio then ceil(v_km - v_radio)::int else 0 end;
  return jsonb_build_object('km', v_km, 'radio_km', v_radio, 'valor_km', v_valor,
                            'extra_km', v_extra, 'recargo', round(v_extra * v_valor)::int);
end $$;
revoke execute on function _recargo_distancia(double precision, double precision) from public, anon, authenticated;

-- Para la reserva en línea: valores a domicilio + datos para calcular la distancia (la clave de Google Maps
-- es de navegador: queda restringida a la página del taller en Google Cloud).
create or replace function domicilio_opciones() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'terreno', _valor_trabajo(trabajo_domicilio_id),
    'retiro', _valor_trabajo(trabajo_retiro_id),
    'maps_key', nullif(btrim(coalesce(google_maps_key, '')), ''),
    'distancia', case when (_domicilio_km_cfg() ->> 'lat') is not null then
      jsonb_build_object('radio_km', (_domicilio_km_cfg() ->> 'radio_km')::numeric,
                         'valor_km', (_domicilio_km_cfg() ->> 'valor_km')::numeric,
                         'lat', (_domicilio_km_cfg() ->> 'lat')::double precision,
                         'lng', (_domicilio_km_cfg() ->> 'lng')::double precision) end)
    from taller_config where id = 1;
$$;
grant execute on function domicilio_opciones() to anon, authenticated;

-- Guarda la ubicación de una cita a domicilio y su recargo (uso interno)
create or replace function _cita_guardar_ubicacion(p_cita uuid, p_lat double precision, p_lng double precision) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_r jsonb;
begin
  v_r := _recargo_distancia(p_lat, p_lng);
  update citas set dom_lat = case when v_r is not null then p_lat end,
                   dom_lng = case when v_r is not null then p_lng end,
                   dom_km = (v_r ->> 'km')::numeric,
                   dom_recargo = (v_r ->> 'recargo')::int
   where id = p_cita;
  return v_r;
end $$;
revoke execute on function _cita_guardar_ubicacion(uuid, double precision, double precision) from public, anon, authenticated;

-- Reserva v6 = v5 + ubicación del domicilio (el recargo lo calcula el servidor, no el navegador)
create or replace function reservar_cita_v6(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha date, p_hora text, p_trabajo_id uuid, p_servicio_otro text, p_notas text,
  p_rut text, p_vehiculo_id uuid, p_marca text, p_modelo text, p_anio integer,
  p_km integer default null, p_motor text default null, p_combustible text default null,
  p_email text default null, p_modalidad text default null, p_direccion text default null,
  p_codigo text default null, p_domicilio_tipo text default null,
  p_lat double precision default null, p_lng double precision default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_res jsonb; v_id uuid; v_r jsonb;
begin
  v_res := reservar_cita_v5(p_nombre, p_telefono, p_patente, p_fecha, p_hora, p_trabajo_id, p_servicio_otro, p_notas,
                            p_rut, p_vehiculo_id, p_marca, p_modelo, p_anio, p_km, p_motor, p_combustible,
                            p_email, p_modalidad, p_direccion, p_codigo, p_domicilio_tipo);
  if not coalesce((v_res ->> 'ok')::boolean, false) then return v_res; end if;
  if v_res ->> 'modalidad' in ('terreno', 'retiro') then
    select id into v_id from citas where numero = (v_res ->> 'numero')::bigint;
    v_r := _cita_guardar_ubicacion(v_id, p_lat, p_lng);
    if v_r is not null then v_res := v_res || jsonb_build_object('distancia', v_r); end if;
  end if;
  return v_res;
end $$;
grant execute on function reservar_cita_v6(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer, integer, text, text, text, text, text, text, text, double precision, double precision) to anon;

-- Link del cliente (mi-cita → reagendar): actualiza la ubicación de su cita a domicilio después de reagendar
create or replace function cita_cliente_ubicacion(p_token text, p_lat double precision, p_lng double precision) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c citas%rowtype; v_r jsonb;
begin
  if p_token is null or length(p_token) < 20 then return jsonb_build_object('ok', false, 'error', 'El link no es válido.'); end if;
  select * into c from citas where token_cliente = p_token;
  if not found then return jsonb_build_object('ok', false, 'error', 'No encontramos esta reserva.'); end if;
  if c.modalidad not in ('terreno', 'retiro') or c.estado not in ('pendiente', 'confirmado') then
    return jsonb_build_object('ok', false, 'error', 'Esta reserva no es a domicilio.');
  end if;
  v_r := _cita_guardar_ubicacion(c.id, p_lat, p_lng);
  return jsonb_build_object('ok', true, 'distancia', v_r);
end $$;
grant execute on function cita_cliente_ubicacion(text, double precision, double precision) to anon;

-- Verificación: debe decir «ok»
select case when to_regprocedure('reservar_cita_v6(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer, integer, text, text, text, text, text, text, text, double precision, double precision)') is not null
             and to_regprocedure('cita_cliente_ubicacion(text, double precision, double precision)') is not null
             and exists (select 1 from information_schema.columns where table_name = 'citas' and column_name = 'dom_recargo')
            then 'ok' else 'revisar' end as v80;
