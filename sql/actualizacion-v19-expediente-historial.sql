-- ============================================================
-- Actualización v19: Historial de estados + Expediente completo de OT
--
-- · ordenes_historial: registra cada cambio de estado con fecha/hora,
--   desde ahora en adelante (no reconstruye el pasado)
-- · Se usa para armar la línea de tiempo del "Expediente completo"
--   (botón nuevo en el detalle de cada OT, solo visible para el
--   editor, pensado para respaldo en caso de disputa judicial)
-- ============================================================

create table if not exists ordenes_historial (
  id uuid primary key default uuid_generate_v4(),
  orden_id uuid not null references ordenes(id) on delete cascade,
  estado_anterior text,
  estado_nuevo text not null,
  fecha timestamptz not null default now()
);

create index if not exists idx_ordenes_historial_orden on ordenes_historial (orden_id);

alter table ordenes_historial enable row level security;

drop policy if exists "Acceso historial ordenes" on ordenes_historial;
create policy "Acceso historial ordenes" on ordenes_historial
  for all using (es_autorizado()) with check (es_autorizado());

select 'v19 expediente + historial aplicada' as estado;
