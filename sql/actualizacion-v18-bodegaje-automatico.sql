-- ============================================================
-- Actualización v18: Cobro automático de bodegaje
--
-- · ordenes.fecha_listo: se registra cada vez que el estado pasa a
--   'listo' (marca el inicio del plazo de gracia para retirar)
-- · taller_config.bodegaje_dias_gracia / bodegaje_monto_dia: valores
--   editables en Configuración, usados para calcular el cobro
--   automático que se suma al saldo mientras el vehículo no se retira
-- ============================================================

ALTER TABLE ordenes
ADD COLUMN IF NOT EXISTS fecha_listo timestamptz;

ALTER TABLE taller_config
ADD COLUMN IF NOT EXISTS bodegaje_dias_gracia integer NOT NULL DEFAULT 2,
ADD COLUMN IF NOT EXISTS bodegaje_monto_dia numeric(12,2) NOT NULL DEFAULT 3500;

COMMENT ON COLUMN ordenes.fecha_listo IS 'Fecha en que se notificó que el vehículo está listo para retiro; inicia el conteo de días de gracia antes del cobro de bodegaje';

select 'v18 bodegaje automatico aplicada' as estado;
