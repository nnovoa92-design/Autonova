-- ============================================================
-- Actualización v22: modalidad de atención por cita
--
-- Permite que el mensaje de recordatorio se adapte según cómo se
-- entrega el servicio: en el taller, retiro a domicilio, o trabajo
-- en terreno. Afecta solo el texto del mensaje (instrucciones de
-- llegada, llaves, etc.), no la lógica de agenda/slots.
-- ============================================================

ALTER TABLE citas
ADD COLUMN IF NOT EXISTS modalidad text NOT NULL DEFAULT 'taller'
  CHECK (modalidad IN ('taller', 'retiro', 'terreno'));

COMMENT ON COLUMN citas.modalidad IS 'Cómo se entrega el servicio: taller (cliente llega), retiro (se va a buscar el vehículo), terreno (se trabaja en la ubicación del cliente)';

select 'v22 modalidad de citas aplicada' as estado;
