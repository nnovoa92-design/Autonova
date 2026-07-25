-- ============================================================
-- Actualización v24: dirección de atención para retiro/terreno
--
-- Solo aplica cuando la modalidad de la cita es "retiro" o "terreno".
-- Se pre-llena con la dirección del cliente (si la tiene guardada),
-- pero queda editable por cita porque el lugar de retiro/atención
-- puede variar (casa, trabajo, etc.) respecto a la ficha del cliente.
-- ============================================================

ALTER TABLE citas
ADD COLUMN IF NOT EXISTS direccion text;

select 'v24 direccion de cita aplicada' as estado;
