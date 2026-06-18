-- ============================================================
-- Actualización v6: Módulo de Contabilidad
--
-- Libro contable mensual al estilo del Excel "Autonova Sistema
-- Contable 2026": cada movimiento es un trabajo con mano de obra,
-- repuestos, forma de pago, tipo de documento y estado de pago.
-- El reparto (mecánico/dueño/taller) y los totales se calculan en
-- la app a partir de estos campos.
--
-- EJECUTAR en el SQL Editor de Supabase. Seguro de correr más de una vez.
-- ============================================================

create table if not exists movimientos_contables (
  id uuid primary key default uuid_generate_v4(),
  fecha date not null default current_date,
  patente text,
  vehiculo text,                 -- marca / modelo / año
  cliente text,
  telefono text,
  quien_trabajo text not null default 'ambos'
    check (quien_trabajo in ('yo', 'ambos', '2do_mec')),
  horas numeric(6,2) not null default 0,
  descripcion text,
  mo_neta numeric(12,2) not null default 0,        -- mano de obra neta (sin IVA)
  forma_pago text check (forma_pago in ('efectivo','transferencia','debito','credito','mixto')),
  tipo_doc text not null default 'neto'
    check (tipo_doc in ('boleta','factura','neto')),
  num_doc text,
  estado_pago text not null default 'pagado'
    check (estado_pago in ('pagado','pendiente')),
  costo_repuesto numeric(12,2) not null default 0, -- lo pagado al proveedor
  precio_repuesto numeric(12,2) not null default 0,-- lo cobrado al cliente
  orden_id uuid references ordenes(id) on delete set null,  -- vínculo opcional a una OT
  notas text,
  creado_en timestamptz not null default now()
);

create index if not exists idx_movcont_fecha on movimientos_contables (fecha);

alter table movimientos_contables enable row level security;
drop policy if exists "Usuarios autenticados acceso total" on movimientos_contables;
create policy "Usuarios autenticados acceso total" on movimientos_contables
  for all using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

select 'v6 aplicada' as estado;
