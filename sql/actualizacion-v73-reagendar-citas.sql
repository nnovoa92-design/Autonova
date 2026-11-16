-- ============================================================
-- v73 — Reagendar citas: historial de cambios de fecha y hora
--
--  * Cada vez que reagendas una cita (Agenda → 📅 Reagendar) queda registrado: fecha y hora anterior, la nueva,
--    el motivo (solicitud del cliente, imprevisto del taller, etc.), si la hora anterior quedó libre o bloqueada
--    y cuándo se hizo. Se ve en la cita («🔁 Reagendada») y en el historial del vehículo.
--  * La cita no cambia nada más: cliente, vehículo, servicio, duración, dirección, notas y código se mantienen.
--
-- Seguro de correr más de una vez.
-- ============================================================

alter table citas add column if not exists reagendamientos jsonb not null default '[]'::jsonb;

-- Verificación: debe decir «ok»
select case when exists (select 1 from information_schema.columns
                          where table_name = 'citas' and column_name = 'reagendamientos')
            then 'ok' else 'revisar' end as v73;
