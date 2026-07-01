-- ============================================================
-- Actualización v10: Agenda + reservas online de clientes
--
-- · Horarios de atención en taller_config.
-- · Tabla `citas` (turnos): reservas internas y online.
-- · Funciones públicas (security definer, para la página de reserva)
--   que respetan el blindaje RLS: el cliente no toca las tablas
--   directamente, solo llama funciones controladas.
--
-- EJECUTAR en el SQL Editor de Supabase. Seguro de correr más de una vez.
-- (Requiere que ya exista la función es_autorizado() de v9.)
-- ============================================================

-- 1) Horarios de atención
alter table taller_config add column if not exists hora_apertura text default '09:00';
alter table taller_config add column if not exists hora_cierre  text default '18:00';
alter table taller_config add column if not exists sab_apertura text default '09:00';
alter table taller_config add column if not exists sab_cierre   text default '13:00';
alter table taller_config add column if not exists slot_min     integer default 60;

-- 2) Tabla de citas (agenda)
create table if not exists citas (
  id uuid primary key default uuid_generate_v4(),
  numero bigserial,
  cliente_id uuid references clientes(id) on delete set null,
  vehiculo_id uuid references vehiculos(id) on delete set null,
  trabajo_id uuid references trabajos(id) on delete set null,
  personal_id uuid references personal(id) on delete set null,
  orden_id uuid references ordenes(id) on delete set null,
  fecha_hora timestamptz not null,
  duracion_min integer not null default 60,
  estado text not null default 'pendiente'
    check (estado in ('pendiente','confirmado','completado','cancelado','ausente')),
  origen text not null default 'interno' check (origen in ('interno','online')),
  nombre_contacto text,
  telefono_contacto text,
  patente_contacto text,
  descripcion text,
  notas text,
  creado_en timestamptz not null default now()
);
create index if not exists idx_citas_fecha on citas (fecha_hora);

alter table citas enable row level security;
drop policy if exists "Acceso solo usuarios autorizados" on citas;
create policy "Acceso solo usuarios autorizados" on citas
  for all using (es_autorizado()) with check (es_autorizado());

-- 3) Función pública: info para la página de reserva (horarios + trabajos)
create or replace function reservar_info()
returns jsonb language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'taller', (select jsonb_build_object('nombre', nombre, 'telefono', telefono, 'direccion', direccion) from taller_config where id = 1),
    'horarios', (select jsonb_build_object('apertura', hora_apertura, 'cierre', hora_cierre, 'sab_apertura', sab_apertura, 'sab_cierre', sab_cierre, 'slot_min', coalesce(slot_min,60)) from taller_config where id = 1),
    'trabajos', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'horas', horas_estimadas, 'precio_fijo', precio_fijo) order by nombre), '[]'::jsonb) from trabajos where activo)
  );
$$;
grant execute on function reservar_info() to anon;

-- 4) Función pública: horas ya ocupadas de un día (para marcar slots)
create or replace function reservar_ocupados(p_fecha date)
returns jsonb language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(to_char(fecha_hora at time zone 'America/Santiago', 'HH24:MI')), '[]'::jsonb)
  from citas
  where estado <> 'cancelado'
    and (fecha_hora at time zone 'America/Santiago')::date = p_fecha;
$$;
grant execute on function reservar_ocupados(date) to anon;

-- 5) Función pública: crear la reserva online
create or replace function reservar_cita(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha_hora timestamptz, p_trabajo_id uuid, p_notas text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_cliente uuid; v_vehiculo uuid; v_trab_nombre text; v_num bigint;
begin
  if p_nombre is null or length(trim(p_nombre)) = 0 or p_telefono is null or length(trim(p_telefono)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Faltan datos de contacto.');
  end if;
  if exists (select 1 from citas where estado <> 'cancelado' and fecha_hora = p_fecha_hora) then
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
  values (v_cliente, v_vehiculo, p_trabajo_id, p_fecha_hora,
          coalesce((select slot_min from taller_config where id = 1), 60),
          'pendiente', 'online', trim(p_nombre), p_telefono, p_patente, v_trab_nombre, p_notas)
  returning numero into v_num;

  return jsonb_build_object('ok', true, 'numero', v_num);
end $$;
grant execute on function reservar_cita(text, text, text, timestamptz, uuid, text) to anon;

select 'v10 agenda aplicada' as estado;
