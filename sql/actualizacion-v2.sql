-- ============================================================
-- Actualización v2: Inspecciones precompra + porcentajes de
-- reparto manuales en la configuración.
--
-- EJECUTAR en el SQL Editor de Supabase (después de schema.sql
-- y migracion.sql). Es seguro correrlo más de una vez.
-- ============================================================

-- Tabla de control de migraciones (por si migracion.sql no se ejecutó)
create table if not exists _migracion_done (
  id integer primary key,
  fecha timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 1) Porcentajes de reparto (configurables, 0 = no usar)
-- ------------------------------------------------------------
alter table taller_config add column if not exists pct_mecanico numeric(5,2) not null default 0;
alter table taller_config add column if not exists pct_dueno    numeric(5,2) not null default 0;
alter table taller_config add column if not exists pct_taller   numeric(5,2) not null default 0;

-- ------------------------------------------------------------
-- 2) Inspecciones precompra
-- ------------------------------------------------------------
create table if not exists inspecciones (
  id uuid primary key default uuid_generate_v4(),
  numero bigserial,
  nombre_comprador text not null,
  telefono text,
  patente text,
  marca text,
  modelo text,
  km text,
  precio_pedido numeric(12,2),
  datos jsonb not null default '{}'::jsonb,  -- respuestas del checklist
  score integer,
  ok integer not null default 0,
  warn integer not null default 0,
  bad integer not null default 0,
  na integer not null default 0,
  total integer not null default 0,
  recomendacion text,
  observaciones text,
  fecha timestamptz not null default now()
);

create index if not exists idx_inspecciones_fecha on inspecciones (fecha);

alter table inspecciones enable row level security;
drop policy if exists "Usuarios autenticados acceso total" on inspecciones;
create policy "Usuarios autenticados acceso total" on inspecciones
  for all using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

-- Informe público: el cliente lo ve con el link único (UUID)
create or replace function portal_consultar_inspeccion(p_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'numero', i.numero,
    'fecha', i.fecha,
    'nombre_comprador', i.nombre_comprador,
    'patente', i.patente,
    'marca', i.marca,
    'modelo', i.modelo,
    'km', i.km,
    'precio_pedido', i.precio_pedido,
    'datos', i.datos,
    'score', i.score,
    'ok', i.ok, 'warn', i.warn, 'bad', i.bad, 'na', i.na, 'total', i.total,
    'recomendacion', i.recomendacion,
    'observaciones', i.observaciones,
    'taller', (
      select jsonb_build_object(
        'nombre', nombre, 'telefono', telefono,
        'direccion', direccion, 'email', email
      ) from taller_config where id = 1
    )
  )
  from inspecciones i
  where i.id = p_id;
$$;

grant execute on function portal_consultar_inspeccion(uuid) to anon;

-- ------------------------------------------------------------
-- 3) Migrar inspecciones de la app anterior (autonova_data)
-- ------------------------------------------------------------
do $$
declare
  raw jsonb;
  ij jsonb;
begin
  if exists (select 1 from _migracion_done where id = 2) then
    raise notice 'Inspecciones ya migradas. No se hace nada.';
    return;
  end if;

  select (data)::jsonb into raw from autonova_data where id = 'autonova_main';
  if raw is null then
    raise notice 'No se encontró autonova_data.';
    insert into _migracion_done (id) values (2);
    return;
  end if;

  for ij in select * from jsonb_array_elements(coalesce(raw->'insp', '[]'::jsonb)) loop
    insert into inspecciones (
      nombre_comprador, telefono, patente, marca, modelo, km, precio_pedido,
      datos, score, ok, warn, bad, na, total, recomendacion, observaciones, fecha
    ) values (
      coalesce(nullif(trim(ij->>'nombre'), ''), 'Sin nombre'),
      nullif(trim(coalesce(ij->>'wa','')), ''),
      upper(nullif(trim(coalesce(ij->'vid'->>'pat','')), '')),
      nullif(trim(coalesce(ij->'vid'->>'marca','')), ''),
      nullif(trim(coalesce(ij->'vid'->>'modelo','')), ''),
      nullif(trim(coalesce(ij->'vid'->>'km','')), ''),
      coalesce(nullif(regexp_replace(coalesce(ij->'vid'->>'precio','0'), '[^0-9.]', '', 'g'), '')::numeric, 0),
      coalesce(ij->'datos', '{}'::jsonb),
      coalesce(nullif(regexp_replace(coalesce(ij->>'score','0'), '\D', '', 'g'), '')::integer, 0),
      coalesce((ij->>'ok')::integer, 0),
      coalesce((ij->>'warn')::integer, 0),
      coalesce((ij->>'bad')::integer, 0),
      coalesce((ij->>'na')::integer, 0),
      coalesce((ij->>'total')::integer, 0),
      nullif(trim(coalesce(ij->>'rec','')), ''),
      nullif(trim(coalesce(ij->'datos'->>'_obs','')), ''),
      case when coalesce(ij->>'fecha','') ~ '^\d{4}-\d{2}-\d{2}'
           then (ij->>'fecha')::timestamptz
           else now() end
    );
  end loop;

  insert into _migracion_done (id) values (2);
  raise notice 'Inspecciones migradas.';
end $$;

-- Resumen
select count(*) as inspecciones_totales from inspecciones;
