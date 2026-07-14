-- ============================================================
-- Actualización v11: Abonos en órdenes de trabajo
--
-- · Tabla `abonos` para registrar pagos parciales por OT
-- · Vouchers subidos a Storage (fotos-ot/abonos/{id})
-- · Cálculo automático de saldo a pagar en OT
-- ============================================================

-- Tabla de abonos (pagos parciales)
create table if not exists abonos (
  id uuid primary key default uuid_generate_v4(),
  orden_id uuid not null references ordenes(id) on delete cascade,
  monto numeric(12, 2) not null,
  metodo_pago text not null check (metodo_pago in ('efectivo', 'tarjeta_debito', 'tarjeta_credito', 'transferencia', 'otro')),
  fecha date not null,
  hora time,
  voucher_url text,
  notas text,
  creado_en timestamptz default now(),
  created_by uuid references auth.users(id)
);

-- Índices
create index if not exists idx_abonos_orden on abonos(orden_id);
create index if not exists idx_abonos_fecha on abonos(fecha);

-- RLS
alter table abonos enable row level security;
drop policy if exists "Acceso solo usuarios autorizados" on abonos;
create policy "Acceso solo usuarios autorizados" on abonos
  for all using (es_autorizado()) with check (es_autorizado());

select 'v11 abonos aplicada' as estado;
