-- ============================================================
-- Actualización v48: confirmar la reserva desde la campanita, con duración del trabajo y control de choques
--
-- Al llegar una reserva online, en la campanita aparece «Confirmar agenda»: abre la Agenda con la reserva
-- para dimensionar las horas del trabajo (30 min, 1 h, 3 h…). Esas horas pasan a ocupar la agenda: nadie
-- más puede reservar encima (ni desde el link público), salvo que tú lo permitas o sobreagendes.
--
--  * citas.bloquea (true por defecto): false = «permitir otros vehículos al mismo tiempo»; esa cita no
--    ocupa horas ni para el link público.
--  * notificaciones.ref_id: la reserva a la que apunta cada aviso (para abrirla desde la campanita).
--  * El aviso de «Nueva reserva online» ahora lleva su ref_id.
--  * agenda_slots_libres y reservar_cita_v4 respetan citas.bloquea.
--
-- Requiere v31, v38 y v47. Seguro de correr más de una vez.
-- ============================================================

alter table citas add column if not exists bloquea boolean not null default true;
comment on column citas.bloquea is 'false = esta cita no ocupa las horas de la agenda (se permite otro vehículo al mismo tiempo)';

alter table notificaciones add column if not exists ref_id uuid;
create index if not exists idx_notificaciones_ref on notificaciones (ref_id);

-- Aviso de reserva online nueva, ahora con la referencia a la cita
create or replace function notif_cita_online()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    insert into notificaciones (tipo, titulo, detalle, url, ref_id)
    values (
      'reserva_online',
      'Nueva reserva online',
      coalesce(nullif(new.nombre_contacto, ''), 'Cliente')
        || ' · ' || coalesce(nullif(new.descripcion, ''), 'Servicio')
        || ' · ' || to_char(new.fecha_hora at time zone 'America/Santiago', 'DD-MM HH24:MI')
        || case when coalesce(new.patente_contacto, '') <> '' then ' · ' || upper(new.patente_contacto) else '' end,
      'agenda.html',
      new.id
    );
  exception when others then
    null;   -- un fallo al avisar nunca debe impedir la reserva
  end;
  return new;
end $$;

-- ------------------------------------------------------------
-- Horas libres para reservar: las citas con bloquea = false no ocupan horas
-- ------------------------------------------------------------
create or replace function agenda_slots_libres(p_fecha date)
returns text[]
language plpgsql stable security definer set search_path = public as $$
declare
  v_h horario_atencion%rowtype;
  v_slot int;
  v_m int;
  v_ini int;
  v_fin int;
  v_ahora timestamp := (now() at time zone 'America/Santiago');
  v_res text[] := '{}';
begin
  select * into v_h from horario_atencion where dow = extract(dow from p_fecha)::int;
  if not found or not v_h.abierto then return v_res; end if;

  if exists (select 1 from bloqueos_agenda b
             where p_fecha between b.fecha_desde and b.fecha_hasta and b.hora_desde is null) then
    return v_res;
  end if;

  v_slot := greatest(coalesce((select slot_min from taller_config where id = 1), 60), 5);
  v_ini := hhmm_a_min(v_h.apertura);
  v_fin := hhmm_a_min(v_h.cierre);
  v_m := v_ini;

  while v_m < v_fin loop
    if (p_fecha::timestamp + make_interval(mins => v_m)) > v_ahora
       -- pausa (colación): el bloque no puede cruzarse con ella
       and not (v_h.pausa_desde is not null and v_h.pausa_hasta is not null
                and v_m < hhmm_a_min(v_h.pausa_hasta) and hhmm_a_min(v_h.pausa_desde) < v_m + v_slot)
       -- bloqueos por horas
       and not exists (select 1 from bloqueos_agenda b
                       where p_fecha between b.fecha_desde and b.fecha_hasta
                         and b.hora_desde is not null
                         and v_m < hhmm_a_min(b.hora_hasta) and hhmm_a_min(b.hora_desde) < v_m + v_slot)
       -- citas ya tomadas (cada una ocupa su duración)
       and not exists (select 1 from citas c
                       where c.estado <> 'cancelado' and c.bloquea
                         and (c.fecha_hora at time zone 'America/Santiago')::date = p_fecha
                         and v_m < (extract(hour from c.fecha_hora at time zone 'America/Santiago')::int * 60
                                    + extract(minute from c.fecha_hora at time zone 'America/Santiago')::int + c.duracion_min)
                         and (extract(hour from c.fecha_hora at time zone 'America/Santiago')::int * 60
                              + extract(minute from c.fecha_hora at time zone 'America/Santiago')::int) < v_m + v_slot)
    then
      v_res := v_res || (lpad((v_m / 60)::text, 2, '0') || ':' || lpad((v_m % 60)::text, 2, '0'));
    end if;
    v_m := v_m + v_slot;
  end loop;

  return v_res;
end $$;

grant execute on function agenda_slots_libres(date) to anon, authenticated;

-- ------------------------------------------------------------
-- Reserva con RUT (v4): igual que v47, pero una cita que no bloquea no cuenta como «hora tomada»
-- ------------------------------------------------------------
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

grant execute on function reservar_cita_v4(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer) to anon;

select 'v48 confirmar reserva con duración aplicado' as estado;
