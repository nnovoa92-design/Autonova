-- ============================================================
-- Actualización v59: criterios de inspección precompra editables
--
--  * taller_config.insp_pesos: importancia que el taller le da a cada ítem del checklist precompra
--    ({"Título del ítem": 1 | 2 | 3}; 3 = crítico, 2 = importante, 1 = menor). Solo se guardan los ítems que
--    difieren del estándar de la app. Se edita en Configuración → Criterios de inspección precompra.
--    (El ajuste según la causa de cada hallazgo se guarda dentro de cada inspección y no necesita SQL.)
--
-- Seguro de correr más de una vez.
-- ============================================================

alter table taller_config add column if not exists insp_pesos jsonb not null default '{}'::jsonb;
comment on column taller_config.insp_pesos is 'Importancia de cada ítem de la inspección precompra según el taller: {"título": 1|2|3}. Sin clave = estándar de la app.';

select 'v59 criterios de inspección aplicado' as estado;
