-- ============================================================
-- Actualización v51: más datos del vehículo (kilometraje, combustible, tipo, N° de motor, color, transmisión)
--
-- El registro público (boostr.cl) entrega, además de marca/modelo/año: tipo de vehículo, N° de motor,
-- combustible y kilometraje (de la última revisión técnica). En planes de pago también color, chasis,
-- cilindrada, transmisión, etc. Esos datos ahora tienen su propio campo en la ficha del vehículo
-- (antes se guardaban como texto en Notas).
--
--  * vehiculos: combustible, tipo_vehiculo, numero_motor, color, transmision (kilometraje, motor y vin ya existían).
--  * Reserva online: el cliente puede indicar kilometraje, cilindrada/motor y combustible de su vehículo.
--  * Esos textos también se limpian de marcado (< >) como el resto de los datos públicos (v46).
--
-- Requiere v47/v48 (reservar_cita_v4) y v46. Seguro de correr más de una vez.
-- ============================================================

alter table vehiculos
  add column if not exists combustible text,
  add column if not exists tipo_vehiculo text,
  add column if not exists numero_motor text,
  add column if not exists color text,
  add column if not exists transmision text;

comment on column vehiculos.motor is 'Motor / cilindrada, ej. 1.6 16v';
comment on column vehiculos.numero_motor is 'Número de motor (registro de vehículos)';
comment on column vehiculos.tipo_vehiculo is 'Automóvil, camioneta, SUV, furgón…';

-- Limpieza de marcado también en los campos nuevos
create or replace function trg_limpiar_vehiculo() returns trigger language plpgsql as $$
begin
  new.patente := limpiar_marcado(new.patente);
  new.marca := limpiar_marcado(new.marca);
  new.modelo := limpiar_marcado(new.modelo);
  new.motor := limpiar_marcado(new.motor);
  new.combustible := limpiar_marcado(new.combustible);
  new.tipo_vehiculo := limpiar_marcado(new.tipo_vehiculo);
  new.numero_motor := limpiar_marcado(new.numero_motor);
  new.color := limpiar_marcado(new.color);
  new.transmision := limpiar_marcado(new.transmision);
  return new;
end $$;

-- Se reemplaza la firma anterior de la reserva (13 parámetros) por una con tres datos más, opcionales:
-- las llamadas antiguas siguen funcionando.
drop function if exists reservar_cita_v4(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer);

create or replace function reservar_cita_v4(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha date, p_hora text, p_trabajo_id uuid, p_servicio_otro text, p_notas text,
  p_rut text, p_vehiculo_id uuid, p_marca text, p_modelo text, p_anio integer,
  p_km integer default null, p_motor text default null, p_combustible text default null
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
  v_tel text := nullif(trim(coalesce(p_telefono, '')), '');
  v_cli_nombre text; v_cli_tel text;
  v_ip text := reservar_ip();
  v_n int;
begin
  if length(v_nombre) = 0 then
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
  if exists (select 1 from citas where estado <> 'cancelado' and bloquea and fecha_hora = v_fecha_hora) then
    return jsonb_build_object('ok', false, 'error', 'Ese horario acaba de ser tomado. Elige otro.');
  end if;

  -- Límite por conexión: 5 reservas por hora y 12 por día
  delete from reservar_limites where creado_en < now() - interval '2 days';
  select count(*) into v_n from reservar_limites where ip = v_ip and tipo = 'cita' and creado_en > now() - interval '1 hour';
  if v_n >= 5 then
    return jsonb_build_object('ok', false, 'error', 'Has hecho varias reservas seguidas. Espera un momento o llama al taller.');
  end if;
  select count(*) into v_n from reservar_limites where ip = v_ip and tipo = 'cita' and creado_en > now() - interval '1 day';
  if v_n >= 12 then
    return jsonb_build_object('ok', false, 'error', 'Alcanzaste el máximo de reservas por hoy. Llama al taller para agendar más.');
  end if;

  -- Cliente: por RUT; si no, por teléfono (como antes); si no, uno nuevo
  if v_rut is not null then
    select id, nombre, telefono into v_cliente, v_cli_nombre, v_cli_tel
    from clientes
    where upper(regexp_replace(coalesce(rut, ''), '[^0-9kK]', '', 'g')) = v_norm
    order by activo desc, creado_en
    limit 1;
  end if;

  -- Si no llegó teléfono, se usa el que ya tiene registrado el cliente reconocido
  if v_tel is null then
    v_tel := nullif(trim(coalesce(v_cli_tel, '')), '');
  end if;
  if v_tel is null then
    return jsonb_build_object('ok', false, 'error', 'Faltan datos de contacto.');
  end if;

  -- Máximo 3 reservas web pendientes a la vez por teléfono / cliente
  select count(*) into v_n from citas
  where origen = 'online' and estado in ('pendiente', 'confirmado') and fecha_hora > now()
    and (telefono_contacto = v_tel or (v_cliente is not null and cliente_id = v_cliente));
  if v_n >= 3 then
    return jsonb_build_object('ok', false, 'error', 'Ya tienes 3 reservas pendientes. Para agendar otra, espera a que se realicen o llama al taller.');
  end if;

  if v_cliente is null then
    select id into v_cliente from clientes where telefono = v_tel limit 1;
    if v_cliente is not null and v_rut is not null then
      -- el cliente existía solo por teléfono: se le completa el RUT si no tenía
      update clientes set rut = v_rut where id = v_cliente and (rut is null or btrim(rut) = '');
    end if;
  end if;
  if v_cliente is null then
    insert into clientes (nombre, rut, telefono, por_revisar) values (v_nombre, v_rut, v_tel, true) returning id into v_cliente;
  end if;

  -- Vehículo: el elegido (si es de ese cliente), o por patente, o uno nuevo con los datos entregados
  if p_vehiculo_id is not null then
    select id into v_vehiculo from vehiculos where id = p_vehiculo_id and cliente_id = v_cliente;
  end if;
  if v_vehiculo is null and v_patente is not null then
    select id into v_vehiculo from vehiculos where upper(replace(patente, ' ', '')) = v_patente limit 1;
    if v_vehiculo is null then
      insert into vehiculos (cliente_id, patente, marca, modelo, anio, kilometraje, motor, combustible)
      values (v_cliente, v_patente,
              nullif(left(trim(coalesce(p_marca, '')), 40), ''),
              nullif(left(trim(coalesce(p_modelo, '')), 60), ''),
              case when p_anio between 1950 and 2100 then p_anio else null end,
              case when p_km between 0 and 2000000 then p_km else null end,
              nullif(left(trim(coalesce(p_motor, '')), 40), ''),
              nullif(left(trim(coalesce(p_combustible, '')), 20), ''))
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

  insert into reservar_limites (ip, tipo) values (v_ip, 'cita');

  insert into citas (cliente_id, vehiculo_id, trabajo_id, fecha_hora, duracion_min, estado, origen,
                     nombre_contacto, telefono_contacto, patente_contacto, rut_contacto, descripcion, notas)
  values (v_cliente, v_vehiculo,
          case when v_trab_nombre is not null then p_trabajo_id else null end,
          v_fecha_hora,
          coalesce((select slot_min from taller_config where id = 1), 60),
          'pendiente', 'online', coalesce(v_cli_nombre, v_nombre), v_tel, v_patente, v_rut,
          coalesce(v_trab_nombre, 'Otro: ' || v_otro), left(p_notas, 500))
  returning numero into v_num;

  return jsonb_build_object('ok', true, 'numero', v_num);
end $$;

grant execute on function reservar_cita_v4(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer, integer, text, text) to anon;

select 'v51 datos del vehiculo aplicado' as estado;
