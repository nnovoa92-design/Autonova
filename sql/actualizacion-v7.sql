-- ============================================================
-- Actualización v7: Libro de Ventas (DTE emitidos por TUU/SII)
--
-- Registro de boletas y facturas electrónicas tal como las emite
-- el SII (a través de TUU). Se cargan desde los XML exportados.
-- Es la vista tributaria (neto / IVA / total), complementaria al
-- libro de trabajos (movimientos_contables).
--
-- EJECUTAR en el SQL Editor de Supabase. Seguro de correr más de una vez.
-- ============================================================

create table if not exists ventas_dte (
  id uuid primary key default uuid_generate_v4(),
  tipo_dte integer not null,           -- 33=factura, 39=boleta, 34/41 exenta, etc.
  folio bigint not null,
  fecha date not null,
  rut_receptor text,
  receptor text,
  neto numeric(14,2) not null default 0,
  iva numeric(14,2) not null default 0,
  exento numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  items text,
  creado_en timestamptz not null default now(),
  unique (tipo_dte, folio)
);

create index if not exists idx_ventas_dte_fecha on ventas_dte (fecha);

alter table ventas_dte enable row level security;
drop policy if exists "Usuarios autenticados acceso total" on ventas_dte;
create policy "Usuarios autenticados acceso total" on ventas_dte
  for all using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

select 'v7 aplicada' as estado;
