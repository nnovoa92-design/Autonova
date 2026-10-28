-- ============================================================
-- Actualización v58: avisos automáticos por correo al cliente
--
--  * taller_config.correo_eventos: qué avisos automáticos están APAGADOS, p. ej. {"ot_en_proceso": false}.
--    Lo que no aparece está encendido. Se marca en Configuración → Correo de confirmaciones → Avisos automáticos.
--    Avisos: ingreso del vehículo (OT creada), OT en diagnóstico / en proceso / lista para retiro / entregada,
--    cotización marcada como enviada e inspección precompra terminada. El WhatsApp sigue siendo manual.
--  * inspecciones.email: correo del comprador, para enviarle el informe al terminar la inspección.
--
-- Seguro de correr más de una vez.
-- ============================================================

alter table taller_config add column if not exists correo_eventos jsonb not null default '{}'::jsonb;
comment on column taller_config.correo_eventos is 'Avisos automáticos por correo apagados: {"evento": false}. Lo que no aparece está encendido.';

alter table inspecciones add column if not exists email text;
comment on column inspecciones.email is 'Correo del comprador: recibe el informe al terminar la inspección.';

select 'v58 avisos automáticos por correo aplicado' as estado;
