-- ============================================================
-- v62 — Registro de correos enviados (respaldo)
--
--  * correos_enviados: cada correo que la app envía al cliente (automático o con el botón ✉), con su texto,
--    si salió o no, y a qué documento, cliente y vehículo corresponde (para el historial del vehículo).
--  * Se ve en Configuración → Correos enviados; además cada envío queda en la campanita.
--
-- Seguro de correr más de una vez.
-- ============================================================

create table if not exists correos_enviados (
  id uuid primary key default uuid_generate_v4(),
  creado_en timestamptz not null default now(),
  para text not null,
  asunto text,
  texto text,
  evento text,                 -- ot_ingreso, ot_listo, cotizacion_enviada, inspeccion, cita_confirmada, manual…
  estado text not null,        -- enviado | error | incierto
  error text,
  ref_tabla text,              -- ordenes | cotizaciones | diagnosticos | inspecciones | citas
  ref_id uuid,
  cliente_id uuid references clientes(id) on delete set null,
  vehiculo_id uuid references vehiculos(id) on delete set null
);

create index if not exists idx_correos_enviados_fecha on correos_enviados (creado_en desc);
create index if not exists idx_correos_enviados_vehiculo on correos_enviados (vehiculo_id);
create index if not exists idx_correos_enviados_ref on correos_enviados (ref_id);

alter table correos_enviados enable row level security;
drop policy if exists "Acceso solo usuarios autorizados" on correos_enviados;
create policy "Acceso solo usuarios autorizados" on correos_enviados
  for all using (es_autorizado()) with check (es_autorizado());
