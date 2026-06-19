-- ============================================================
-- Actualización v8: Libro de Compras (DTE recibidos) + IVA crédito
--
-- Registro de facturas/documentos recibidos de proveedores, para
-- el IVA crédito y la utilidad real del taller. Se cargan desde los
-- XML "Recibidos" exportados de TUU/SII.
--
-- Las guías de despacho (T52) y similares se guardan como REGISTRO
-- pero NO se consideran tributables (no suman IVA ni gasto): eso se
-- maneja en la app según el tipo de documento.
--
-- EJECUTAR en el SQL Editor de Supabase. Seguro de correr más de una vez.
-- ============================================================

create table if not exists compras_dte (
  id uuid primary key default uuid_generate_v4(),
  tipo_dte integer not null,           -- 33=factura, 34=factura exenta, 52=guía despacho (solo registro), etc.
  folio bigint not null,
  fecha date not null,
  rut_emisor text,                     -- RUT del proveedor
  emisor text,                         -- razón social del proveedor
  neto numeric(14,2) not null default 0,
  iva numeric(14,2) not null default 0,
  exento numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  items text,
  creado_en timestamptz not null default now(),
  unique (tipo_dte, folio, rut_emisor)
);

create index if not exists idx_compras_dte_fecha on compras_dte (fecha);

alter table compras_dte enable row level security;
drop policy if exists "Usuarios autenticados acceso total" on compras_dte;
create policy "Usuarios autenticados acceso total" on compras_dte
  for all using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

select 'v8 aplicada' as estado;
