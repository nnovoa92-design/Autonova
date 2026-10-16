-- ============================================================
-- Actualización v50: autocompletar el vehículo por patente en el link de reservas
--
-- En la página pública de reservas el cliente escribe su patente y se completan solos marca,
-- modelo y año (datos públicos del registro de vehículos, vía boostr.cl).
--
-- La clave de boostr NUNCA sale de tu base: la consulta la hace el servidor (extensión `http` de
-- Postgres) usando la clave guardada en Configuración. La página pública solo recibe marca,
-- modelo, año y tipo; nunca el propietario, el número de motor ni el kilometraje.
--
-- Cuidado del cupo (el plan gratis son 5 consultas al día):
--   * Cada patente se consulta UNA sola vez: el resultado queda guardado (patentes_cache).
--   * Máximo 3 consultas nuevas al servicio por día desde las reservas web (te quedan 2 para el
--     sistema interno), y 10 patentes por hora por conexión.
--   * Si no queda cupo, la clave falló o el servicio no responde, el cliente escribe los datos a mano.
--
-- Requiere v47 (reservar_ip, reservar_limites) y v41 (clave en Configuración).
-- Seguro de correr más de una vez.
-- ============================================================

create extension if not exists http with schema extensions;

-- Resultados ya consultados (solo los usa la función; nadie los lee desde la app)
create table if not exists patentes_cache (
  patente text primary key,
  encontrado boolean not null,
  datos jsonb not null default '{}'::jsonb,
  creado_en timestamptz not null default now()
);
alter table patentes_cache enable row level security;
revoke all on patentes_cache from anon, authenticated;

create or replace function reservar_patente(p_patente text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_p text := upper(regexp_replace(coalesce(p_patente, ''), '[^A-Za-z0-9]', '', 'g'));
  v_ip text := reservar_ip();
  v_n int;
  v_c patentes_cache%rowtype;
  v_key text;
  v_resp extensions.http_response;
  v_j jsonb;
  v_d jsonb;
begin
  if v_p !~ '^([A-Z]{4}[0-9]{2}|[A-Z]{2}[0-9]{4}|[A-Z]{3}[0-9]{2}|[A-Z]{2}[0-9]{3})$' then
    return jsonb_build_object('estado', 'invalida');
  end if;

  -- 1) Ya consultada antes: no gasta cupo
  select * into v_c from patentes_cache where patente = v_p;
  if found then
    return jsonb_build_object('estado', case when v_c.encontrado then 'ok' else 'no_encontrado' end, 'datos', v_c.datos);
  end if;

  -- 2) Límites: por conexión y presupuesto diario de las reservas web
  delete from reservar_limites where creado_en < now() - interval '2 days';
  select count(*) into v_n from reservar_limites where ip = v_ip and tipo = 'patente_ip' and creado_en > now() - interval '1 hour';
  if v_n >= 10 then return jsonb_build_object('estado', 'limite'); end if;
  select count(*) into v_n from reservar_limites where tipo = 'patente_api' and creado_en > now() - interval '24 hours';
  if v_n >= 3 then return jsonb_build_object('estado', 'limite'); end if;

  -- 3) Clave guardada en Configuración (no se devuelve nunca)
  select api_patentes_key into v_key from taller_config where id = 1;
  if v_key is null or btrim(v_key) = '' then
    return jsonb_build_object('estado', 'sin_clave');
  end if;

  insert into reservar_limites (ip, tipo) values (v_ip, 'patente_ip');
  insert into reservar_limites (ip, tipo) values (v_ip, 'patente_api');

  -- 4) Consulta al registro (boostr.cl)
  begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '8');
    v_resp := extensions.http((
      'GET',
      'https://api.boostr.cl/vehicle/' || v_p || '.json',
      array[extensions.http_header('X-API-KEY', btrim(v_key))],
      null,
      null
    )::extensions.http_request);
  exception when others then
    return jsonb_build_object('estado', 'error');
  end;

  begin
    v_j := v_resp.content::jsonb;
  exception when others then
    return jsonb_build_object('estado', 'error');
  end;

  if v_resp.status = 200 and v_j ->> 'status' = 'success' and jsonb_typeof(v_j -> 'data') = 'object' then
    v_d := jsonb_build_object(
      'marca', v_j -> 'data' ->> 'make',
      'modelo', v_j -> 'data' ->> 'model',
      'anio', v_j -> 'data' -> 'year',
      'tipo', v_j -> 'data' ->> 'type'
    );
    insert into patentes_cache (patente, encontrado, datos) values (v_p, true, v_d)
    on conflict (patente) do nothing;
    return jsonb_build_object('estado', 'ok', 'datos', v_d);
  end if;

  if v_resp.status = 404 or v_j ->> 'code' = 'V-02' then
    insert into patentes_cache (patente, encontrado, datos) values (v_p, false, '{}'::jsonb)
    on conflict (patente) do nothing;
    return jsonb_build_object('estado', 'no_encontrado');
  end if;

  return jsonb_build_object('estado', 'error');
end $$;

grant execute on function reservar_patente(text) to anon;

select 'v50 patente en la reserva aplicado' as estado,
       exists (select 1 from pg_extension where extname = 'http') as extension_http;
