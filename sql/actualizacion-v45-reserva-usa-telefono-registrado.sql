-- ============================================================
-- Actualización v45: la reserva online no vuelve a pedir el teléfono a un cliente conocido
--
-- Si el RUT corresponde a un cliente que ya tiene teléfono registrado, el link de reservas
-- ya no se lo pide: la cita usa el número que está en su ficha. El cliente solo ve que
-- «termina en 5678» (nunca el número completo) y puede indicar otro si cambió.
--
-- Cambia dos funciones de v44 (create or replace; seguro de correr más de una vez):
--   reservar_reconocer(p_rut)  -> además informa los 4 últimos dígitos del teléfono registrado.
--   reservar_cita_v4(...)      -> si no llega teléfono, usa el del cliente reconocido por RUT.
-- Requiere v44.
-- ============================================================

create or replace function reservar_reconocer(p_rut text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_norm text := upper(regexp_replace(coalesce(p_rut, ''), '[^0-9kK]', '', 'g'));
  v_h jsonb; v_ip text; v_n int; v_cli record; v_vehs jsonb; v_digitos text;
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

  select id, nombre, telefono into v_cli
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

  v_digitos := regexp_replace(coalesce(v_cli.telefono, ''), '\D', '', 'g');

  return jsonb_build_object(
    'encontrado', true,
    'nombre', split_part(trim(v_cli.nombre), ' ', 1),
    'telefono_final', case when length(v_digitos) >= 4 then right(v_digitos, 4) else null end,
    'vehiculos', v_vehs
  );
end $$;

grant execute on function reservar_reconocer(text) to anon;

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
  v_tel text := nullif(trim(coalesce(p_telefono, '')), '');
  v_cli_nombre text; v_cli_tel text;
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
  if exists (select 1 from citas where estado <> 'cancelado' and fecha_hora = v_fecha_hora) then
    return jsonb_build_object('ok', false, 'error', 'Ese horario acaba de ser tomado. Elige otro.');
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

  if v_cliente is null then
    select id into v_cliente from clientes where telefono = v_tel limit 1;
    if v_cliente is not null and v_rut is not null then
      -- el cliente existía solo por teléfono: se le completa el RUT si no tenía
      update clientes set rut = v_rut where id = v_cliente and (rut is null or btrim(rut) = '');
    end if;
  end if;
  if v_cliente is null then
    insert into clientes (nombre, rut, telefono) values (v_nombre, v_rut, v_tel) returning id into v_cliente;
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
          'pendiente', 'online', coalesce(v_cli_nombre, v_nombre), v_tel, v_patente, v_rut,
          coalesce(v_trab_nombre, 'Otro: ' || v_otro), left(p_notas, 500))
  returning numero into v_num;

  return jsonb_build_object('ok', true, 'numero', v_num);
end $$;

grant execute on function reservar_cita_v4(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer) to anon;

select 'v45 la reserva usa el teléfono registrado del cliente aplicada' as estado;
