-- ============================================================
-- Actualización v35: reserva online con la opción "Otro"
--
-- El cliente puede reservar aunque su servicio no esté en el listado:
-- elige "Otro" y lo describe con sus palabras. La cita queda sin trabajo
-- del catálogo y con la descripción "Otro: <lo que escribió>", que es lo
-- que se ve en la Agenda, en Inicio y en el aviso por WhatsApp.
--
-- reservar_cita_v3 = reservar_cita_v2 + p_servicio_otro. La v2 sigue
-- existiendo (páginas en caché) y pasa por la v3. Mismas validaciones de
-- horario, bloqueos y disponibilidad.
--
-- Requiere v31 (horarios y bloqueos). Seguro de correr más de una vez.
-- ============================================================

create or replace function reservar_cita_v3(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha date, p_hora text, p_trabajo_id uuid, p_servicio_otro text, p_notas text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_fecha_hora timestamptz;
  v_cliente uuid; v_vehiculo uuid; v_trab_nombre text; v_num bigint;
  v_otro text := nullif(left(trim(coalesce(p_servicio_otro, '')), 500), '');
begin
  if p_nombre is null or length(trim(p_nombre)) = 0 or p_telefono is null or length(trim(p_telefono)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Faltan datos de contacto.');
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

  select id into v_cliente from clientes where telefono = p_telefono limit 1;
  if v_cliente is null then
    insert into clientes (nombre, telefono) values (trim(p_nombre), p_telefono) returning id into v_cliente;
  end if;

  if p_patente is not null and length(trim(p_patente)) > 0 then
    select id into v_vehiculo from vehiculos where upper(replace(patente, ' ', '')) = upper(replace(p_patente, ' ', '')) limit 1;
    if v_vehiculo is null then
      insert into vehiculos (cliente_id, patente) values (v_cliente, upper(replace(p_patente, ' ', ''))) returning id into v_vehiculo;
    end if;
  end if;

  -- Trabajo del catálogo (si existe y sigue activo) o, si no, lo que escribió el cliente
  if p_trabajo_id is not null then
    select nombre into v_trab_nombre from trabajos where id = p_trabajo_id;
  end if;
  if v_trab_nombre is null and v_otro is null then
    return jsonb_build_object('ok', false, 'error', 'Ese servicio ya no está disponible. Elige otro o cuéntanos qué necesitas en «Otro».');
  end if;

  insert into citas (cliente_id, vehiculo_id, trabajo_id, fecha_hora, duracion_min, estado, origen,
                     nombre_contacto, telefono_contacto, patente_contacto, descripcion, notas)
  values (v_cliente, v_vehiculo,
          case when v_trab_nombre is not null then p_trabajo_id else null end,
          v_fecha_hora,
          coalesce((select slot_min from taller_config where id = 1), 60),
          'pendiente', 'online', trim(p_nombre), p_telefono, p_patente,
          coalesce(v_trab_nombre, 'Otro: ' || v_otro), p_notas)
  returning numero into v_num;

  return jsonb_build_object('ok', true, 'numero', v_num);
end $$;

grant execute on function reservar_cita_v3(text, text, text, date, text, uuid, text, text) to anon;

-- La v2 (páginas en caché) pasa por la v3
create or replace function reservar_cita_v2(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha date, p_hora text, p_trabajo_id uuid, p_notas text
) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return reservar_cita_v3(p_nombre, p_telefono, p_patente, p_fecha, p_hora, p_trabajo_id, null, p_notas);
end $$;

grant execute on function reservar_cita_v2(text, text, text, date, text, uuid, text) to anon;

select 'v35 reserva online con "Otro" aplicada' as estado;
