-- ============================================================
-- Actualización v12: Políticas de Servicio por categoría
--
-- · Tabla `service_policies` para políticas de garantía y servicio
-- · Tabla `service_policy_trabajos` para trabajos recomendados
-- · Tabla `service_policy_repuestos` para repuestos típicos
-- ============================================================

-- Tabla de políticas de servicio (una por categoría de trabajo)
create table if not exists service_policies (
  id uuid primary key default uuid_generate_v4(),
  categoria_id uuid references categorias_trabajos(id) on delete cascade,
  nombre text not null,
  descripcion text,
  garantia_meses int default 0,
  garantia_tipo text check (garantia_tipo in ('ninguna', 'trabajo', 'repuestos', 'ambos')) default 'trabajo',
  tiempo_estimado_horas numeric(5, 2),
  notas text,
  activo boolean default true,
  creado_en timestamptz default now(),
  actualizado_en timestamptz default now(),
  created_by uuid references auth.users(id)
);

-- Trabajos recomendados para cada política
create table if not exists service_policy_trabajos (
  id uuid primary key default uuid_generate_v4(),
  policy_id uuid references service_policies(id) on delete cascade,
  trabajo_id uuid references trabajos(id) on delete cascade,
  recomendado boolean default true,
  orden int default 0,
  creado_en timestamptz default now(),
  created_by uuid references auth.users(id)
);

-- Repuestos típicos para cada política
create table if not exists service_policy_repuestos (
  id uuid primary key default uuid_generate_v4(),
  policy_id uuid references service_policies(id) on delete cascade,
  repuesto_id uuid references inventario(id) on delete cascade,
  recomendado boolean default true,
  cantidad_tipica numeric(10, 2) default 1,
  orden int default 0,
  creado_en timestamptz default now(),
  created_by uuid references auth.users(id)
);

-- Índices para performance
create index if not exists idx_service_policies_categoria on service_policies(categoria_id);
create index if not exists idx_service_policies_activo on service_policies(activo);
create index if not exists idx_service_policy_trabajos_policy on service_policy_trabajos(policy_id);
create index if not exists idx_service_policy_repuestos_policy on service_policy_repuestos(policy_id);

-- RLS
alter table service_policies enable row level security;
alter table service_policy_trabajos enable row level security;
alter table service_policy_repuestos enable row level security;

drop policy if exists "Acceso políticas de servicio" on service_policies;
create policy "Acceso políticas de servicio" on service_policies
  for all using (es_autorizado()) with check (es_autorizado());

drop policy if exists "Acceso trabajos en políticas" on service_policy_trabajos;
create policy "Acceso trabajos en políticas" on service_policy_trabajos
  for all using (es_autorizado()) with check (es_autorizado());

drop policy if exists "Acceso repuestos en políticas" on service_policy_repuestos;
create policy "Acceso repuestos en políticas" on service_policy_repuestos
  for all using (es_autorizado()) with check (es_autorizado());

select 'v12 service_policies aplicada' as estado;
