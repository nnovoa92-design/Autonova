-- ============================================================
-- Actualización v23: enlazar una cotización específica a la cita
--
-- Antes el precio de referencia del recordatorio se buscaba adivinando
-- la cotización más reciente del cliente. Ahora se puede elegir
-- explícitamente cuál cotización corresponde a la cita, para que el
-- precio mostrado sea el correcto y no una suposición.
-- ============================================================

ALTER TABLE citas
ADD COLUMN IF NOT EXISTS cotizacion_id uuid REFERENCES cotizaciones(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_citas_cotizacion ON citas (cotizacion_id);

select 'v23 cita cotizacion aplicada' as estado;
