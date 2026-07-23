-- ============================================================
-- Actualización v13: Agregar campo tipo_otro a cotizacion_items
-- ============================================================

-- Agregar columna tipo_otro a cotizacion_items si no existe
ALTER TABLE cotizacion_items
ADD COLUMN IF NOT EXISTS tipo_otro text;

-- Agregar comentario
COMMENT ON COLUMN cotizacion_items.tipo_otro IS 'Subtipo cuando tipo=otro (repuesto, trabajo_externo, maestranza, etc)';

select 'v13 tipo_otro aplicada' as estado;
