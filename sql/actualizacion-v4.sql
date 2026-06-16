-- ============================================================
-- Actualización v4:
--  · ordenes.avances  -> registro de "qué se hizo" (varios), cada
--    uno con texto + fotos. Visibles en el portal del cliente.
--  · recordatorios     -> mantención y revisión técnica (para #7).
--
-- EJECUTAR en el SQL Editor de Supabase. Seguro de correr más de una vez.
-- ============================================================

-- 1) Avances de la orden de trabajo
alter table ordenes add column if not exists avances jsonb not null default '[]'::jsonb;

-- 2) Recordatorios (mantención / revisión técnica)
create table if not exists recordatorios (
  id uuid primary key default uuid_generate_v4(),
  vehiculo_id uuid references vehiculos(id) on delete cascade,
  cliente_id uuid references clientes(id) on delete set null,
  tipo text not null check (tipo in ('mantencion', 'revision_tecnica')),
  fecha_objetivo date not null,        -- cuándo avisar (mantención: a N meses; RT: 1° del mes)
  detalle text,
  enviado boolean not null default false,
  fecha_envio timestamptz,
  creado_en timestamptz not null default now()
);

create index if not exists idx_recordatorios_fecha on recordatorios (fecha_objetivo);
create index if not exists idx_recordatorios_pendientes on recordatorios (enviado, fecha_objetivo);

alter table recordatorios enable row level security;
drop policy if exists "Usuarios autenticados acceso total" on recordatorios;
create policy "Usuarios autenticados acceso total" on recordatorios
  for all using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

-- 3) El portal del cliente también devuelve los avances (qué se hizo + fotos)
create or replace function portal_consultar_orden(p_patente text, p_numero bigint)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'orden_id', o.id,
    'numero', o.numero,
    'estado', o.estado,
    'fecha_ingreso', o.fecha_ingreso,
    'fecha_entrega', o.fecha_entrega,
    'diagnostico', o.diagnostico,
    'avances', o.avances,
    'vehiculo', jsonb_build_object('patente', v.patente, 'marca', v.marca, 'modelo', v.modelo),
    'taller', (
      select jsonb_build_object(
        'nombre', nombre, 'telefono', telefono,
        'direccion', direccion, 'iva_pct', iva_pct
      ) from taller_config where id = 1
    ),
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'descripcion', i.descripcion,
        'cantidad', i.cantidad,
        'precio_unitario', i.precio_unitario
      ) order by i.orden), '[]'::jsonb)
      from orden_items i where i.orden_id = o.id
    )
  )
  from ordenes o
  join vehiculos v on v.id = o.vehiculo_id
  where upper(replace(v.patente, ' ', '')) = upper(replace(p_patente, ' ', ''))
    and o.numero = p_numero
  limit 1;
$$;

grant execute on function portal_consultar_orden(text, bigint) to anon;

select 'v4 aplicada' as estado;
