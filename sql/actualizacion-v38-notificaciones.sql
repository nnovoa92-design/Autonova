-- ============================================================
-- Actualización v38: notificaciones (campanita del sistema)
--
-- Cada novedad que importa al taller se guarda en la tabla
-- `notificaciones` y se muestra en la campanita de arriba a la derecha
-- (contador de sin leer, lista, y aviso del navegador si lo activas).
--
-- Se registran solas, con triggers, estas novedades:
--   · reserva_online       -> un cliente reservó hora desde el link (incluye "Otro")
--   · cotizacion_aprobada / cotizacion_rechazada -> el cliente respondió desde su link
--   · diagnostico_aceptado / diagnostico_rechazado -> el cliente respondió desde su link
--   · inspeccion_firmada   -> el cliente firmó a distancia la inspección de ingreso
-- Cuando el propio taller marca un estado desde el sistema NO se genera aviso
-- (solo cuenta lo que hace el cliente).
--
-- Un fallo al crear el aviso nunca bloquea la acción del cliente: el trigger
-- lo ignora y deja pasar la reserva / respuesta / firma.
--
-- Requiere es_autorizado() (v9), citas (v10), v37 (respuesta de diagnóstico).
-- Seguro de correr más de una vez.
-- ============================================================

create table if not exists notificaciones (
  id uuid primary key default uuid_generate_v4(),
  tipo text not null,
  titulo text not null,
  detalle text,
  url text,                                  -- pantalla a abrir, ej. 'agenda.html' o 'cotizaciones.html?id=...'
  leida boolean not null default false,
  creado_en timestamptz not null default now()
);

create index if not exists idx_notificaciones_leida on notificaciones (leida, creado_en desc);

alter table notificaciones enable row level security;
drop policy if exists "Acceso solo usuarios autorizados" on notificaciones;
create policy "Acceso solo usuarios autorizados" on notificaciones
  for all using (es_autorizado()) with check (es_autorizado());

-- ¿La acción la hizo alguien con sesión en el sistema (el taller)? Entonces no se avisa.
create or replace function notif_es_taller()
returns boolean
language plpgsql
stable
as $$
declare v_rol text;
begin
  begin
    v_rol := coalesce(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role', '');
  exception when others then
    v_rol := '';
  end;
  return v_rol = 'authenticated';
end $$;

-- ------------------------------------------------------------
-- Reserva online nueva
-- ------------------------------------------------------------
create or replace function notif_cita_online()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    insert into notificaciones (tipo, titulo, detalle, url)
    values (
      'reserva_online',
      'Nueva reserva online',
      coalesce(nullif(new.nombre_contacto, ''), 'Cliente')
        || ' · ' || coalesce(nullif(new.descripcion, ''), 'Servicio')
        || ' · ' || to_char(new.fecha_hora at time zone 'America/Santiago', 'DD-MM HH24:MI')
        || case when coalesce(new.patente_contacto, '') <> '' then ' · ' || upper(new.patente_contacto) else '' end,
      'agenda.html'
    );
  exception when others then
    null;   -- un fallo al avisar nunca debe impedir la reserva
  end;
  return new;
end $$;

drop trigger if exists trg_notif_cita_online on citas;
create trigger trg_notif_cita_online
  after insert on citas
  for each row when (new.origen = 'online')
  execute function notif_cita_online();

-- ------------------------------------------------------------
-- Cotización aprobada / rechazada por el cliente
-- ------------------------------------------------------------
create or replace function notif_cotizacion_respuesta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cli text;
  v_pat text;
begin
  begin
    if notif_es_taller() then
      return new;
    end if;
    select nombre into v_cli from clientes where id = new.cliente_id;
    select patente into v_pat from vehiculos where id = new.vehiculo_id;
    insert into notificaciones (tipo, titulo, detalle, url)
    values (
      case when new.estado = 'aprobada' then 'cotizacion_aprobada' else 'cotizacion_rechazada' end,
      'Cotización COT-' || lpad(new.numero::text, 4, '0')
        || case when new.estado = 'aprobada' then ' aprobada por el cliente' else ' rechazada por el cliente' end,
      coalesce(v_cli, 'Cliente') || case when v_pat is not null then ' · ' || v_pat else '' end,
      'cotizaciones.html?id=' || new.id::text
    );
  exception when others then
    null;
  end;
  return new;
end $$;

drop trigger if exists trg_notif_cotizacion_respuesta on cotizaciones;
create trigger trg_notif_cotizacion_respuesta
  after update of estado on cotizaciones
  for each row when (new.estado in ('aprobada', 'rechazada') and old.estado is distinct from new.estado)
  execute function notif_cotizacion_respuesta();

-- ------------------------------------------------------------
-- Diagnóstico aceptado / rechazado por el cliente
-- ------------------------------------------------------------
create or replace function notif_diagnostico_respuesta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cli text;
  v_pat text;
begin
  begin
    select nombre into v_cli from clientes where id = new.cliente_id;
    select patente into v_pat from vehiculos where id = new.vehiculo_id;
    insert into notificaciones (tipo, titulo, detalle, url)
    values (
      case when new.respuesta = 'aceptado' then 'diagnostico_aceptado' else 'diagnostico_rechazado' end,
      'Diagnóstico DIAG-' || lpad(new.numero::text, 4, '0')
        || case when new.respuesta = 'aceptado' then ': el cliente aceptó los trabajos' else ': el cliente rechazó los trabajos (solo se cobra el diagnóstico)' end,
      coalesce(v_cli, 'Cliente') || case when v_pat is not null then ' · ' || v_pat else '' end,
      'diagnosticos.html?id=' || new.id::text
    );
  exception when others then
    null;
  end;
  return new;
end $$;

drop trigger if exists trg_notif_diagnostico_respuesta on diagnosticos;
create trigger trg_notif_diagnostico_respuesta
  after update of respuesta on diagnosticos
  for each row when (
    new.respuesta in ('aceptado', 'rechazado')
    and old.respuesta is distinct from new.respuesta
    and new.respuesta_origen = 'cliente'
  )
  execute function notif_diagnostico_respuesta();

-- ------------------------------------------------------------
-- Inspección de ingreso firmada a distancia
-- ------------------------------------------------------------
create or replace function notif_inspeccion_firmada()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cli text;
  v_pat text;
begin
  begin
    if notif_es_taller() then
      return new;
    end if;
    select nombre into v_cli from clientes where id = new.cliente_id;
    select patente into v_pat from vehiculos where id = new.vehiculo_id;
    insert into notificaciones (tipo, titulo, detalle, url)
    values (
      'inspeccion_firmada',
      'Inspección de ingreso firmada · OT-' || lpad(new.numero::text, 4, '0'),
      coalesce(v_cli, 'Cliente') || case when v_pat is not null then ' · ' || v_pat else '' end,
      'ordenes.html?id=' || new.id::text
    );
  exception when others then
    null;
  end;
  return new;
end $$;

drop trigger if exists trg_notif_inspeccion_firmada on ordenes;
create trigger trg_notif_inspeccion_firmada
  after update of checklist_firma_fecha on ordenes
  for each row when (
    new.checklist_firma_fecha is not null
    and new.checklist_firma_fecha is distinct from old.checklist_firma_fecha
  )
  execute function notif_inspeccion_firmada();

select 'v38 notificaciones aplicado' as estado;
