-- ============================================================
-- Actualización v44: la reserva online reconoce al cliente por RUT
--
-- En el link de reservas, el cliente escribe su RUT:
--  * Si ya es cliente: se le saluda por su primer nombre y elige cuál de sus vehículos
--    trae (o agrega otro). No se muestran teléfono, correo, dirección ni la patente completa.
--  * Si no lo es: se le piden nombre, teléfono y, si quiere, los datos de su vehículo.
-- La cita queda asociada al cliente y al vehículo correctos (y con su RUT), así en la
-- Agenda el taller ve de inmediato quién es y su historial.
--
-- Funciones nuevas (públicas, solo devuelven lo mínimo):
--   reservar_reconocer(p_rut)  -> { encontrado, nombre (solo el primero), vehiculos[] }
--                                  con límite de consultas por IP (anti-adivinación de RUT).
--   reservar_cita_v4(...)      -> reservar_cita_v3 + RUT, vehículo elegido y datos del vehículo.
-- reservar_cita_v3 / v2 siguen existiendo (páginas en caché).
--
-- Requiere v35 (reserva con "Otro") y v31 (horarios). Seguro de correr más de una vez.
-- ============================================================

alter table citas add column if not exists rut_contacto text;

-- Registro de consultas por IP (solo lo usa la función; nadie lo lee desde la app)
create table if not exists reservar_consultas_rut (
  id bigserial primary key,
  ip text not null,
  creado_en timestamptz not null default now()
);
create index if not exists idx_reservar_consultas_rut on reservar_consultas_rut (ip, creado_en);
alter table reservar_consultas_rut enable row level security;
revoke all on reservar_consultas_rut from anon, authenticated;

-- RUT válido (dígito verificador) -> "12.345.678-5"; si no es válido, null
create or replace function autonova_rut_formato(p text) returns text
language plpgsql immutable as $$
declare v text; cuerpo text; dv text; suma int := 0; mul int := 2; i int; r int; esperado text;
begin
  if p is null then return null; end if;
  v := upper(regexp_replace(p, '[^0-9kK]', '', 'g'));
  if v !~ '^[0-9]{6,8}[0-9K]$' then return null; end if;
  cuerpo := left(v, length(v) - 1);
  dv := right(v, 1);
  for i in reverse length(cuerpo)..1 loop
    suma := suma + substr(cuerpo, i, 1)::int * mul;
    mul := case when mul = 7 then 2 else mul + 1 end;
  end loop;
  r := 11 - (suma % 11);
  esperado := case when r = 11 then '0' when r = 10 then 'K' else r::text end;
  if dv <> esperado then return null; end if;
  return replace(to_char(cuerpo::bigint, 'FM999,999,999'), ',', '.') || '-' || dv;
end $$;

-- ¿Quién es? Devuelve lo mínimo para que el cliente elija su vehículo
create or replace function reservar_reconocer(p_rut text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_norm text := upper(regexp_replace(coalesce(p_rut, ''), '[^0-9kK]', '', 'g'));
  v_h jsonb; v_ip text; v_n int; v_cli record; v_vehs jsonb;
begin
  if autonova_rut_formato(p_rut) is null then
    return jsonb_build_object('encontrado', false, 'invalido', true);
  end if;

  -- Límite de consultas por IP: evita recorrer RUT al azar
  begin
    v_h := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then v_h := null;
  end;
  v_ip := coalesce(nullif(trim(split_part(coalesce(v_h ->> 'x-forwarded-for', v_h ->> 'cf-connecting-ip', ''), ',', 1)), ''), 'desconocido');
  delete from reservar_consultas_rut where creado_en < now() - interval '1 hour';
  select count(*) into v_n from reservar_consultas_rut where ip = v_ip and creado_en > now() - interval '10 minutes';
  if v_n >= 20 then
    return jsonb_build_object('encontrado', false, 'limite', true);
  end if;
  insert into reservar_consultas_rut (ip) values (v_ip);

  select id, nombre into v_cli
  from clientes
  where activo and upper(regexp_replace(coalesce(rut, ''), '[^0-9kK]', '', 'g')) = v_norm
  limit 1;
  if v_cli.id is null then
    return jsonb_build_object('encontrado', false);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', v.id,
      'patente', case when length(v.patente) >= 5 then left(v.patente, 2) || '••' || right(v.patente, 2) else '••••' end,
      'marca', v.marca, 'modelo', v.modelo, 'anio', v.anio
    ) order by v.creado_en), '[]'::jsonb)
  into v_vehs
  from vehiculos v
  where v.cliente_id = v_cli.id and v.activo;

  return jsonb_build_object(
    'encontrado', true,
    'nombre', split_part(trim(v_cli.nombre), ' ', 1),
    'vehiculos', v_vehs
  );
end $$;

grant execute on function reservar_reconocer(text) to anon;

-- Reserva con RUT: asocia la cita al cliente (por RUT) y a su vehículo
create or replace function reservar_cita_v4(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha date, p_hora text, p_trabajo_id uuid, p_servicio_otro text, p_notas text,
  p_rut text, p_vehiculo_id uuid, p_marca text, p_modelo text, p_anio integer
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_fecha_hora timestamptz;
  v_cliente uuid; v_vehiculo uuid; v_trab_nombre text; v_num bigint;
  v_otro text := nullif(left(trim(coalesce(p_servicio_otro, '')), 500), '');
  v_rut text := autonova_rut_formato(p_rut);
  v_norm text := upper(regexp_replace(coalesce(p_rut, ''), '[^0-9kK]', '', 'g'));
  v_patente text := nullif(upper(replace(trim(coalesce(p_patente, '')), ' ', '')), '');
  v_nombre text := left(trim(coalesce(p_nombre, '')), 100);
  v_cli_nombre text;
begin
  if length(v_nombre) = 0 or p_telefono is null or length(trim(p_telefono)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Faltan datos de contacto.');
  end if;
  if p_rut is not null and length(trim(p_rut)) > 0 and v_rut is null then
    return jsonb_build_object('ok', false, 'error', 'El RUT no es válido.');
  end if;
  if p_trabajo_id is null and v_otro is null then
    return jsonb_build_object('ok', false, 'error', 'Cuéntanos qué servicio necesitas.');
  end if;
  if p_fecha is null or p_hora is null or p_hora !~ '^[0-2][0-9]:[0-5][0-9]$' then
    return jsonb_build_object('ok', false, 'error', 'Día u hora inválidos.');
  end if;
  if p_fecha < v_hoy or p_fecha > v_hoy + 90 then
    return jsonb_build_object('ok', false, 'error', 'Ese día no está disponible para reservar.');
  end if;
  if not (p_hora = any (agenda_slots_libres(p_fecha))) then
    return jsonb_build_object('ok', false, 'error', 'Ese horario ya no está disponible (tomado o cerrado). Elige otro.');
  end if;

  v_fecha_hora := ((p_fecha::text || ' ' || p_hora)::timestamp) at time zone 'America/Santiago';
  if exists (select 1 from citas where estado <> 'cancelado' and fecha_hora = v_fecha_hora) then
    return jsonb_build_object('ok', false, 'error', 'Ese horario acaba de ser tomado. Elige otro.');
  end if;

  -- Cliente: por RUT; si no, por teléfono (como antes); si no, uno nuevo
  if v_rut is not null then
    select id, nombre into v_cliente, v_cli_nombre
    from clientes
    where upper(regexp_replace(coalesce(rut, ''), '[^0-9kK]', '', 'g')) = v_norm
    order by activo desc, creado_en
    limit 1;
  end if;
  if v_cliente is null then
    select id into v_cliente from clientes where telefono = p_telefono limit 1;
    if v_cliente is not null and v_rut is not null then
      -- el cliente existía solo por teléfono: se le completa el RUT si no tenía
      update clientes set rut = v_rut where id = v_cliente and (rut is null or btrim(rut) = '');
    end if;
  end if;
  if v_cliente is null then
    insert into clientes (nombre, rut, telefono) values (v_nombre, v_rut, p_telefono) returning id into v_cliente;
  end if;

  -- Vehículo: el elegido (si es de ese cliente), o por patente, o uno nuevo con los datos entregados
  if p_vehiculo_id is not null then
    select id into v_vehiculo from vehiculos where id = p_vehiculo_id and cliente_id = v_cliente;
  end if;
  if v_vehiculo is null and v_patente is not null then
    select id into v_vehiculo from vehiculos where upper(replace(patente, ' ', '')) = v_patente limit 1;
    if v_vehiculo is null then
      insert into vehiculos (cliente_id, patente, marca, modelo, anio)
      values (v_cliente, v_patente,
              nullif(left(trim(coalesce(p_marca, '')), 40), ''),
              nullif(left(trim(coalesce(p_modelo, '')), 60), ''),
              case when p_anio between 1950 and 2100 then p_anio else null end)
      returning id into v_vehiculo;
    end if;
  end if;
  if v_patente is null and v_vehiculo is not null then
    select patente into v_patente from vehiculos where id = v_vehiculo;
  end if;

  if p_trabajo_id is not null then
    select nombre into v_trab_nombre from trabajos where id = p_trabajo_id;
  end if;
  if v_trab_nombre is null and v_otro is null then
    return jsonb_build_object('ok', false, 'error', 'Ese servicio ya no está disponible. Elige otro o cuéntanos qué necesitas en «Otro».');
  end if;

  insert into citas (cliente_id, vehiculo_id, trabajo_id, fecha_hora, duracion_min, estado, origen,
                     nombre_contacto, telefono_contacto, patente_contacto, rut_contacto, descripcion, notas)
  values (v_cliente, v_vehiculo,
          case when v_trab_nombre is not null then p_trabajo_id else null end,
          v_fecha_hora,
          coalesce((select slot_min from taller_config where id = 1), 60),
          'pendiente', 'online', coalesce(v_cli_nombre, v_nombre), p_telefono, v_patente, v_rut,
          coalesce(v_trab_nombre, 'Otro: ' || v_otro), left(p_notas, 500))
  returning numero into v_num;

  return jsonb_build_object('ok', true, 'numero', v_num);
end $$;

grant execute on function reservar_cita_v4(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer) to anon;

select 'v44 reserva online reconoce al cliente por RUT aplicada' as estado;
