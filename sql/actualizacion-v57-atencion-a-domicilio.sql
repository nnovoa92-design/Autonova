-- ============================================================
-- Actualización v57: atención a domicilio en la reserva (traslado bloqueado y valor del catálogo)
--
--  * La reserva online pregunta «En el taller» o «A domicilio» (el mecánico va a la dirección del cliente;
--    en la agenda es la modalidad «terreno»). A domicilio pide la dirección.
--  * Una cita a domicilio bloquea además el traslado: por defecto 1 hora antes y 1 hora después de la hora
--    elegida (citas.margen_antes_min / margen_despues_min; el tiempo se ajusta en Configuración).
--    Las horas libres de la reserva ya consideran esos traslados.
--  * El valor de la atención a domicilio sale del catálogo: el servicio elegido en Configuración
--    (por defecto el que se llame «… domicilio …», p. ej. «Trabajo a Domicilio»). Igual que los demás
--    precios, se informa al cliente recién con la reserva hecha.
--
-- Requiere v55. Seguro de correr más de una vez.
-- ============================================================

alter table citas
  add column if not exists margen_antes_min integer not null default 0,
  add column if not exists margen_despues_min integer not null default 0;
comment on column citas.margen_antes_min is 'Minutos que la cita bloquea ANTES de su hora (traslado a domicilio).';
comment on column citas.margen_despues_min is 'Minutos que la cita bloquea DESPUÉS de terminar (traslado de vuelta).';

alter table taller_config
  add column if not exists trabajo_domicilio_id uuid references trabajos(id) on delete set null,
  add column if not exists domicilio_margen_min integer not null default 60;
comment on column taller_config.trabajo_domicilio_id is 'Servicio del catálogo que se cobra por la atención a domicilio.';
comment on column taller_config.domicilio_margen_min is 'Minutos de traslado que se bloquean antes y después de una cita a domicilio.';

-- Servicio de domicilio por defecto: el del catálogo con «domicilio» en el nombre
update taller_config set trabajo_domicilio_id = (
    select id from trabajos where activo and nombre ilike '%domicilio%'
    order by (lower(nombre) = 'trabajo a domicilio') desc, nombre limit 1)
  where id = 1 and trabajo_domicilio_id is null;

-- Citas a domicilio ya agendadas (futuras): también bloquean el traslado
update citas set margen_antes_min = 60, margen_despues_min = 60
  where modalidad = 'terreno' and estado in ('pendiente', 'confirmado') and fecha_hora > now()
    and margen_antes_min = 0 and margen_despues_min = 0;

-- ------------------------------------------------------------
-- Valor (neto) de la atención a domicilio según el catálogo
-- ------------------------------------------------------------
create or replace function domicilio_valor()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when t.id is null then null else jsonb_build_object(
    'nombre', t.nombre,
    'valor', case
      when jsonb_typeof(t.opciones) = 'array' and jsonb_array_length(t.opciones) > 0 then
        (select min(nullif(o ->> 'precio', '')::numeric) from jsonb_array_elements(t.opciones) o)
      when t.precio_fijo is not null then t.precio_fijo
      when t.horas_estimadas > 0 and coalesce(cfg.valor_hora, 0) > 0 then round(t.horas_estimadas * cfg.valor_hora)
      else null end,
    'desde', (jsonb_typeof(t.opciones) = 'array' and jsonb_array_length(t.opciones) > 0)
  ) end
  from taller_config cfg
  left join trabajos t on t.id = cfg.trabajo_domicilio_id and t.activo
  where cfg.id = 1;
$$;
-- Solo la usan las funciones de reserva (el precio se informa con la reserva hecha, no antes)
revoke execute on function domicilio_valor() from public;
revoke execute on function domicilio_valor() from anon;
revoke execute on function domicilio_valor() from authenticated;

-- ------------------------------------------------------------
-- Horas libres: cada cita ocupa su duración MÁS su traslado (antes y después).
-- p_margen = traslado de la cita que se quiere reservar (0 en el taller).
-- ------------------------------------------------------------
drop function if exists agenda_slots_libres(date);
create or replace function agenda_slots_libres(p_fecha date, p_margen int default 0)
returns text[]
language plpgsql stable security definer set search_path = public as $$
declare
  v_h horario_atencion%rowtype;
  v_slot int;
  v_m int;
  v_ini int;
  v_fin int;
  v_margen int := greatest(coalesce(p_margen, 0), 0);
  v_ahora timestamp := (now() at time zone 'America/Santiago');
  v_desde timestamptz;
  v_hasta timestamptz;
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
    -- lo que ocuparía la nueva cita, incluido su traslado
    v_desde := (p_fecha::timestamp + make_interval(mins => v_m - v_margen)) at time zone 'America/Santiago';
    v_hasta := (p_fecha::timestamp + make_interval(mins => v_m + v_slot + v_margen)) at time zone 'America/Santiago';
    if (p_fecha::timestamp + make_interval(mins => v_m)) > v_ahora
       -- pausa (colación): la atención no puede cruzarse con ella
       and not (v_h.pausa_desde is not null and v_h.pausa_hasta is not null
                and v_m < hhmm_a_min(v_h.pausa_hasta) and hhmm_a_min(v_h.pausa_desde) < v_m + v_slot)
       -- bloqueos por horas (tampoco el traslado)
       and not exists (select 1 from bloqueos_agenda b
                       where p_fecha between b.fecha_desde and b.fecha_hasta
                         and b.hora_desde is not null
                         and v_m - v_margen < hhmm_a_min(b.hora_hasta) and hhmm_a_min(b.hora_desde) < v_m + v_slot + v_margen)
       -- citas ya tomadas: su duración y su traslado
       and not exists (select 1 from citas c
                       where c.estado <> 'cancelado' and c.bloquea
                         and v_desde < c.fecha_hora + make_interval(mins => c.duracion_min + coalesce(c.margen_despues_min, 0))
                         and c.fecha_hora - make_interval(mins => coalesce(c.margen_antes_min, 0)) < v_hasta)
    then
      v_res := v_res || (lpad((v_m / 60)::text, 2, '0') || ':' || lpad((v_m % 60)::text, 2, '0'));
    end if;
    v_m := v_m + v_slot;
  end loop;

  return v_res;
end $$;

grant execute on function agenda_slots_libres(date, int) to anon, authenticated;

-- ------------------------------------------------------------
-- Semana para la página de reserva: horas libres según la modalidad (a domicilio necesita el traslado libre)
-- ------------------------------------------------------------
drop function if exists reservar_semana(date, int);
create or replace function reservar_semana(p_desde date, p_dias int default 7, p_modalidad text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_desde date := p_desde;
  v_n int := least(greatest(coalesce(p_dias, 7), 1), 14);
  v_margen int := case when lower(coalesce(p_modalidad, '')) in ('domicilio', 'terreno')
                       then greatest(coalesce((select domicilio_margen_min from taller_config where id = 1), 60), 0) else 0 end;
  v_d date;
  v_res jsonb := '[]'::jsonb;
begin
  if v_desde is null or v_desde < v_hoy then v_desde := v_hoy; end if;
  if v_desde > v_hoy + 90 then v_desde := v_hoy + 90; end if;
  for i in 0 .. v_n - 1 loop
    v_d := v_desde + i;
    v_res := v_res || jsonb_build_object(
      'fecha', v_d,
      'dow', extract(dow from v_d)::int,
      'slots', to_jsonb(agenda_slots_libres(v_d, v_margen))
    );
  end loop;
  return v_res;
end $$;

grant execute on function reservar_semana(date, int, text) to anon;

-- ------------------------------------------------------------
-- Reserva online: + modalidad (taller / domicilio) y dirección
-- ------------------------------------------------------------
drop function if exists reservar_cita_v4(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer, integer, text, text, text);

create or replace function reservar_cita_v4(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha date, p_hora text, p_trabajo_id uuid, p_servicio_otro text, p_notas text,
  p_rut text, p_vehiculo_id uuid, p_marca text, p_modelo text, p_anio integer,
  p_km integer default null, p_motor text default null, p_combustible text default null,
  p_email text default null,
  p_modalidad text default null, p_direccion text default null
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
  v_datos jsonb := null;
  v_email text := nullif(left(lower(trim(coalesce(limpiar_marcado(p_email), ''))), 120), '');
  -- A domicilio: el mecánico va a la dirección del cliente; se bloquea además el traslado antes y después
  v_modalidad text := case when lower(coalesce(p_modalidad, '')) in ('domicilio', 'terreno') then 'terreno' else 'taller' end;
  v_direccion text := nullif(left(trim(coalesce(limpiar_marcado(p_direccion), '')), 200), '');
  v_margen int := 0;
  v_precio_fijo numeric; v_precio_desde numeric; v_trab_desc text;
  v_ip text := reservar_ip();
  v_n int;
begin
  if length(v_nombre) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Faltan datos de contacto.');
  end if;
  if v_modalidad = 'terreno' then
    if v_direccion is null or length(v_direccion) < 5 then
      return jsonb_build_object('ok', false, 'error', 'Indica la dirección donde atenderemos tu vehículo.');
    end if;
    v_margen := greatest(coalesce((select domicilio_margen_min from taller_config where id = 1), 60), 0);
  end if;
  if v_email is not null and v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]{2,}$' then
    return jsonb_build_object('ok', false, 'error', 'El correo no es válido.');
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
  if not (p_hora = any (agenda_slots_libres(p_fecha, v_margen))) then
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

  -- Cliente que ya existe: por RUT; si no, por teléfono. Si es una persona nueva NO se crea ficha aquí:
  -- se crea cuando el taller confirma la reserva.
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
    select id into v_cliente from clientes where telefono = v_tel order by activo desc, creado_en limit 1;
  end if;

  -- Máximo 3 reservas web pendientes a la vez por teléfono / cliente
  select count(*) into v_n from citas
  where origen = 'online' and estado in ('pendiente', 'confirmado') and fecha_hora > now()
    and (telefono_contacto = v_tel or (v_cliente is not null and cliente_id = v_cliente));
  if v_n >= 3 then
    return jsonb_build_object('ok', false, 'error', 'Ya tienes 3 reservas pendientes. Para agendar otra, espera a que se realicen o llama al taller.');
  end if;

  -- Vehículo: el elegido (si es de ese cliente) o el que ya existe con esa patente. Si es uno nuevo,
  -- sus datos viajan en la cita y el vehículo se crea al confirmar.
  if p_vehiculo_id is not null and v_cliente is not null then
    select id into v_vehiculo from vehiculos where id = p_vehiculo_id and cliente_id = v_cliente;
  end if;
  if v_vehiculo is null and v_patente is not null then
    select id into v_vehiculo from vehiculos where upper(replace(patente, ' ', '')) = v_patente limit 1;
    if v_vehiculo is null then
      v_datos := jsonb_strip_nulls(jsonb_build_object(
        'marca', nullif(left(trim(coalesce(limpiar_marcado(p_marca), '')), 40), ''),
        'modelo', nullif(left(trim(coalesce(limpiar_marcado(p_modelo), '')), 60), ''),
        'anio', case when p_anio between 1950 and 2100 then p_anio else null end,
        'kilometraje', case when p_km between 0 and 2000000 then p_km else null end,
        'motor', nullif(left(trim(coalesce(limpiar_marcado(p_motor), '')), 40), ''),
        'combustible', nullif(left(trim(coalesce(limpiar_marcado(p_combustible), '')), 20), '')
      ));
      if v_datos = '{}'::jsonb then v_datos := null; end if;
    end if;
  end if;
  if v_patente is null and v_vehiculo is not null then
    select patente into v_patente from vehiculos where id = v_vehiculo;
  end if;

  if p_trabajo_id is not null then
    select nombre, precio_fijo, nullif(trim(coalesce(descripcion, '')), ''),
           (select min((o ->> 'precio')::numeric) from jsonb_array_elements(coalesce(opciones, '[]'::jsonb)) o where (o ->> 'precio') is not null)
      into v_trab_nombre, v_precio_fijo, v_trab_desc, v_precio_desde
    from trabajos where id = p_trabajo_id;
  end if;
  if v_trab_nombre is null and v_otro is null then
    return jsonb_build_object('ok', false, 'error', 'Ese servicio ya no está disponible. Elige otro o cuéntanos qué necesitas en «Otro».');
  end if;

  insert into reservar_limites (ip, tipo) values (v_ip, 'cita');

  insert into citas (cliente_id, vehiculo_id, trabajo_id, fecha_hora, duracion_min, estado, origen,
                     nombre_contacto, telefono_contacto, patente_contacto, rut_contacto, datos_vehiculo, email_contacto,
                     modalidad, direccion, margen_antes_min, margen_despues_min, descripcion, notas)
  values (v_cliente, v_vehiculo,
          case when v_trab_nombre is not null then p_trabajo_id else null end,
          v_fecha_hora,
          coalesce((select slot_min from taller_config where id = 1), 60),
          'pendiente', 'online', coalesce(v_cli_nombre, v_nombre), v_tel, v_patente, v_rut, v_datos, v_email,
          v_modalidad, case when v_modalidad = 'terreno' then v_direccion else null end, v_margen, v_margen,
          coalesce(v_trab_nombre, 'Otro: ' || v_otro), left(p_notas, 500))
  returning numero into v_num;

  -- El valor del servicio se informa recién ahora, con la reserva hecha (la lista pública ya no trae precios)
  return jsonb_build_object('ok', true, 'numero', v_num, 'servicio', v_trab_nombre,
                            'precio_fijo', v_precio_fijo, 'precio_desde', v_precio_desde, 'descripcion', v_trab_desc,
                            'modalidad', v_modalidad, 'direccion', case when v_modalidad = 'terreno' then v_direccion else null end,
                            'domicilio', case when v_modalidad = 'terreno' then domicilio_valor() else null end);
end $$;


grant execute on function reservar_cita_v4(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer, integer, text, text, text, text, text) to anon;

select 'v57 atención a domicilio aplicada' as estado,
       (select t.nombre from taller_config c left join trabajos t on t.id = c.trabajo_domicilio_id where c.id = 1) as servicio_domicilio,
       (select domicilio_margen_min from taller_config where id = 1) as traslado_min;
