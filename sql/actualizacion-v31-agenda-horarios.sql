-- ============================================================
-- Actualización v31: horario semanal editable + bloqueos de agenda
--
-- · horario_atencion: un registro por día de la semana (0=domingo ...
--   6=sábado) con abierto/cerrado, apertura, cierre y pausa opcional.
--   Lunes a viernes quedan abiertos con el horario que ya tenías en
--   taller_config; sábado y domingo quedan CERRADOS (se abren desde
--   Configuración cuando quieras).
-- · bloqueos_agenda: cierra un día, un rango de días o unas horas por
--   motivos internos (feriado, mantención, trámite...).
-- · La disponibilidad que ve el cliente en la reserva online se calcula
--   en el servidor (agenda_slots_libres) y reservar_cita_v2 la valida,
--   así nadie puede reservar un día cerrado o bloqueado forzando el link.
--
-- Requiere es_autorizado() (v9) y la tabla citas (v10).
-- Seguro de correr más de una vez.
-- ============================================================

-- 1) Horario semanal
create table if not exists horario_atencion (
  dow smallint primary key check (dow between 0 and 6),
  abierto boolean not null default false,
  apertura text not null default '09:00',
  cierre text not null default '18:00',
  pausa_desde text,
  pausa_hasta text
);

alter table horario_atencion enable row level security;
drop policy if exists "Acceso solo usuarios autorizados" on horario_atencion;
create policy "Acceso solo usuarios autorizados" on horario_atencion
  for all using (es_autorizado()) with check (es_autorizado());

insert into horario_atencion (dow, abierto, apertura, cierre)
select d,
       d between 1 and 5,
       case when d = 6 then coalesce(t.sab_apertura, '09:00') else coalesce(t.hora_apertura, '09:00') end,
       case when d = 6 then coalesce(t.sab_cierre,   '13:00') else coalesce(t.hora_cierre,   '18:00') end
from generate_series(0, 6) d
left join taller_config t on t.id = 1
on conflict (dow) do nothing;

-- 2) Bloqueos puntuales
create table if not exists bloqueos_agenda (
  id uuid primary key default uuid_generate_v4(),
  fecha_desde date not null,
  fecha_hasta date not null,
  hora_desde text,                 -- null = todo el día
  hora_hasta text,
  motivo text,
  creado_en timestamptz not null default now(),
  check (fecha_hasta >= fecha_desde),
  check ((hora_desde is null) = (hora_hasta is null))
);
create index if not exists idx_bloqueos_agenda_fechas on bloqueos_agenda (fecha_desde, fecha_hasta);

alter table bloqueos_agenda enable row level security;
drop policy if exists "Acceso solo usuarios autorizados" on bloqueos_agenda;
create policy "Acceso solo usuarios autorizados" on bloqueos_agenda
  for all using (es_autorizado()) with check (es_autorizado());

-- 3) "HH:MM" -> minutos desde medianoche
create or replace function hhmm_a_min(p text)
returns int language sql immutable as $$
  select split_part(p, ':', 1)::int * 60 + split_part(p, ':', 2)::int;
$$;

-- 4) Horas libres de un día, en orden: respeta día abierto/cerrado, pausa,
--    bloqueos, citas ya tomadas (con su duración) y horas que ya pasaron.
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
                       where c.estado <> 'cancelado'
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

-- 5) Semana completa para la página de reserva: cada día con sus horas libres
create or replace function reservar_semana(p_desde date, p_dias int default 7)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_desde date := p_desde;
  v_n int := least(greatest(coalesce(p_dias, 7), 1), 14);
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
      'slots', to_jsonb(agenda_slots_libres(v_d))
    );
  end loop;
  return v_res;
end $$;

grant execute on function reservar_semana(date, int) to anon;

-- 6) Reserva online: recibe día y hora por separado (hora de Chile) y
--    valida contra la disponibilidad real antes de crear la cita.
create or replace function reservar_cita_v2(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha date, p_hora text, p_trabajo_id uuid, p_notas text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_fecha_hora timestamptz;
  v_cliente uuid; v_vehiculo uuid; v_trab_nombre text; v_num bigint;
begin
  if p_nombre is null or length(trim(p_nombre)) = 0 or p_telefono is null or length(trim(p_telefono)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Faltan datos de contacto.');
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

  select nombre into v_trab_nombre from trabajos where id = p_trabajo_id;

  insert into citas (cliente_id, vehiculo_id, trabajo_id, fecha_hora, duracion_min, estado, origen,
                     nombre_contacto, telefono_contacto, patente_contacto, descripcion, notas)
  values (v_cliente, v_vehiculo, p_trabajo_id, v_fecha_hora,
          coalesce((select slot_min from taller_config where id = 1), 60),
          'pendiente', 'online', trim(p_nombre), p_telefono, p_patente, v_trab_nombre, p_notas)
  returning numero into v_num;

  return jsonb_build_object('ok', true, 'numero', v_num);
end $$;

grant execute on function reservar_cita_v2(text, text, text, date, text, uuid, text) to anon;

-- 7) La función anterior sigue existiendo (páginas en caché), pero ahora
--    pasa por la misma validación en vez de saltársela.
create or replace function reservar_cita(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha_hora timestamptz, p_trabajo_id uuid, p_notas text
) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return reservar_cita_v2(
    p_nombre, p_telefono, p_patente,
    (p_fecha_hora at time zone 'America/Santiago')::date,
    to_char(p_fecha_hora at time zone 'America/Santiago', 'HH24:MI'),
    p_trabajo_id, p_notas
  );
end $$;

grant execute on function reservar_cita(text, text, text, timestamptz, uuid, text) to anon;

select 'v31 horarios y bloqueos de agenda aplicado' as estado;
