-- ============================================================
-- Actualización v41: clave para consultar patentes (agenda)
--
-- Al ingresar una patente en la agenda, los datos del vehículo (marca, modelo, año)
-- se traen del registro público a través de un servicio externo (boostr.cl), que
-- necesita una clave. Se guarda en Configuración → Consulta de patentes.
--
-- Vive en taller_config, que solo pueden leer los usuarios autorizados del taller
-- (las páginas públicas usan funciones que devuelven columnas puntuales, no esta fila).
-- Es seguro ejecutarlo más de una vez.
-- ============================================================

alter table taller_config
  add column if not exists api_patentes_key text;

comment on column taller_config.api_patentes_key is 'Clave del servicio de consulta de patentes (boostr.cl). Solo usuarios autorizados.';

select 'v41 clave de patentes aplicado' as estado;
