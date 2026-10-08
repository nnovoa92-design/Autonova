-- ============================================================
-- Actualización v32: módulo de Diagnósticos
--
-- Un diagnóstico es la revisión de un vehículo SIN necesidad de una
-- cotización ni de una OT: se registra el motivo de consulta, lo
-- revisado (hallazgos con estado, nota y fotos), la conclusión y los
-- trabajos recomendados con su valor estimado. Con eso se genera el
-- informe y, si el cliente avanza, se convierte en cotización y/o OT.
--
-- Regla de sincronización: manda el documento más avanzado.
--   Diagnóstico -> Cotización -> OT
-- Los trabajos recomendados viven en el diagnóstico solo hasta que se
-- convierte; desde ahí las líneas (y el descuento / IVA) se editan en
-- la cotización o en la OT, y el diagnóstico las muestra desde ahí, así
-- nunca quedan dos copias distintas.
--
-- Requiere es_autorizado() (v9), cotizaciones, ordenes y orden_items.
-- Seguro de correr más de una vez.
-- ============================================================

create table if not exists diagnosticos (
  id uuid primary key default uuid_generate_v4(),
  numero bigserial,
  cliente_id uuid not null references clientes(id) on delete cascade,
  vehiculo_id uuid references vehiculos(id) on delete set null,
  fecha timestamptz not null default now(),
  km integer,
  motivo text,                                   -- lo que reporta el cliente
  hallazgos jsonb not null default '[]'::jsonb,  -- [{item, estado: 'optimo'|'observacion'|null, nota, fotos:[url]}]
  conclusion text,                               -- diagnóstico del mecánico
  descuento_pct numeric(5,2) not null default 0,
  con_iva boolean not null default true,
  cotizacion_id uuid references cotizaciones(id) on delete set null,
  creado_en timestamptz not null default now()
);

create index if not exists idx_diagnosticos_cliente on diagnosticos (cliente_id);
create index if not exists idx_diagnosticos_cotizacion on diagnosticos (cotizacion_id);

create table if not exists diagnostico_items (
  id uuid primary key default uuid_generate_v4(),
  diagnostico_id uuid not null references diagnosticos(id) on delete cascade,
  tipo text not null,
  tipo_otro text,
  trabajo_id uuid references trabajos(id) on delete set null,
  repuesto_id uuid references repuestos(id) on delete set null,
  descripcion text not null,
  cantidad numeric(10,2) not null default 1,
  precio_unitario numeric(12,2) not null default 0,
  orden integer not null default 0
);

create index if not exists idx_diagnostico_items_diag on diagnostico_items (diagnostico_id);

COMMENT ON COLUMN diagnosticos.cotizacion_id IS 'Cotización creada desde este diagnóstico; desde que existe, las líneas se leen de la cotización (o de su OT)';

alter table diagnosticos enable row level security;
drop policy if exists "Acceso solo usuarios autorizados" on diagnosticos;
create policy "Acceso solo usuarios autorizados" on diagnosticos
  for all using (es_autorizado()) with check (es_autorizado());

alter table diagnostico_items enable row level security;
drop policy if exists "Acceso solo usuarios autorizados" on diagnostico_items;
create policy "Acceso solo usuarios autorizados" on diagnostico_items
  for all using (es_autorizado()) with check (es_autorizado());

select 'v32 diagnósticos aplicado' as estado;
