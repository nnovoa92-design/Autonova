-- ============================================================
-- v63 — Expediente del vehículo: ordenar lo antiguo
--
-- El expediente de cada vehículo (Vehículos → Expediente) junta citas, diagnósticos, cotizaciones, OT,
-- inspecciones, recordatorios y correos. Este script asocia al vehículo lo que quedó guardado sin él:
--   1. Citas ya atendidas o cerradas con la patente escrita en la reserva (las pendientes no se tocan:
--      se asocian al confirmarlas).
--   2. Inspecciones precompra con la patente del vehículo.
--   3. Cotizaciones, OT y diagnósticos encadenados (diagnóstico → cotización → OT): si uno tiene el vehículo,
--      los otros lo toman.
--   4. Lo que aún queda sin vehículo y cuyo cliente tiene UN solo vehículo registrado: es ese.
--   5. Correos enviados: el vehículo del documento al que corresponden.
-- Al final muestra cuántos registros se ordenaron en cada paso. Seguro de correr más de una vez.
-- ============================================================

create temp table if not exists _v63 (paso text, registros integer);
truncate _v63;

-- Patente comparable: sin espacios ni guiones, en mayúsculas
create or replace function pg_temp.pat(t text) returns text language sql immutable as
  $$ select upper(regexp_replace(coalesce(t, ''), '[^A-Za-z0-9]', '', 'g')) $$;

-- 1. Citas (no pendientes) por la patente de la reserva
with u as (
  update citas c set vehiculo_id = v.id
    from vehiculos v
   where c.vehiculo_id is null and c.estado <> 'pendiente'
     and pg_temp.pat(c.patente_contacto) <> '' and pg_temp.pat(c.patente_contacto) = pg_temp.pat(v.patente)
  returning 1)
insert into _v63 select 'Citas asociadas por patente', count(*) from u;

-- 2. Inspecciones precompra por patente
with u as (
  update inspecciones i set vehiculo_id = v.id
    from vehiculos v
   where i.vehiculo_id is null
     and pg_temp.pat(i.patente) <> '' and pg_temp.pat(i.patente) = pg_temp.pat(v.patente)
  returning 1)
insert into _v63 select 'Inspecciones precompra asociadas por patente', count(*) from u;

-- 3. Cadena diagnóstico → cotización → OT
with u as (
  update cotizaciones c set vehiculo_id = d.vehiculo_id
    from diagnosticos d
   where c.vehiculo_id is null and d.cotizacion_id = c.id and d.vehiculo_id is not null
  returning 1)
insert into _v63 select 'Cotizaciones con el vehículo de su diagnóstico', count(*) from u;

with u as (
  update cotizaciones c set vehiculo_id = o.vehiculo_id
    from ordenes o
   where c.vehiculo_id is null and o.cotizacion_id = c.id and o.vehiculo_id is not null
  returning 1)
insert into _v63 select 'Cotizaciones con el vehículo de su OT', count(*) from u;

with u as (
  update ordenes o set vehiculo_id = c.vehiculo_id
    from cotizaciones c
   where o.vehiculo_id is null and o.cotizacion_id = c.id and c.vehiculo_id is not null
  returning 1)
insert into _v63 select 'OT con el vehículo de su cotización', count(*) from u;

with u as (
  update diagnosticos d set vehiculo_id = c.vehiculo_id
    from cotizaciones c
   where d.vehiculo_id is null and d.cotizacion_id = c.id and c.vehiculo_id is not null
  returning 1)
insert into _v63 select 'Diagnósticos con el vehículo de su cotización', count(*) from u;

-- 4. Cliente con un solo vehículo registrado: lo que está sin vehículo es de ese
with unico as (
  select cliente_id, min(id::text)::uuid as vehiculo_id from vehiculos group by cliente_id having count(*) = 1
), u as (
  update ordenes o set vehiculo_id = un.vehiculo_id from unico un
   where o.vehiculo_id is null and o.cliente_id = un.cliente_id
  returning 1)
insert into _v63 select 'OT del único vehículo del cliente', count(*) from u;

with unico as (
  select cliente_id, min(id::text)::uuid as vehiculo_id from vehiculos group by cliente_id having count(*) = 1
), u as (
  update cotizaciones c set vehiculo_id = un.vehiculo_id from unico un
   where c.vehiculo_id is null and c.cliente_id = un.cliente_id
  returning 1)
insert into _v63 select 'Cotizaciones del único vehículo del cliente', count(*) from u;

with unico as (
  select cliente_id, min(id::text)::uuid as vehiculo_id from vehiculos group by cliente_id having count(*) = 1
), u as (
  update diagnosticos d set vehiculo_id = un.vehiculo_id from unico un
   where d.vehiculo_id is null and d.cliente_id = un.cliente_id
  returning 1)
insert into _v63 select 'Diagnósticos del único vehículo del cliente', count(*) from u;

with unico as (
  select cliente_id, min(id::text)::uuid as vehiculo_id from vehiculos group by cliente_id having count(*) = 1
), u as (
  update citas c set vehiculo_id = un.vehiculo_id from unico un
   where c.vehiculo_id is null and c.estado <> 'pendiente' and c.cliente_id = un.cliente_id
  returning 1)
insert into _v63 select 'Citas del único vehículo del cliente', count(*) from u;

-- 5. Correos enviados (v62): el vehículo del documento al que corresponden
do $$
declare n integer := 0; k integer;
begin
  if to_regclass('public.correos_enviados') is null then
    insert into _v63 values ('Correos enviados (falta v62)', 0);
    return;
  end if;
  update correos_enviados ce set vehiculo_id = o.vehiculo_id from ordenes o
   where ce.vehiculo_id is null and ce.ref_tabla = 'ordenes' and ce.ref_id = o.id and o.vehiculo_id is not null;
  get diagnostics k = row_count; n := n + k;
  update correos_enviados ce set vehiculo_id = c.vehiculo_id from cotizaciones c
   where ce.vehiculo_id is null and ce.ref_tabla = 'cotizaciones' and ce.ref_id = c.id and c.vehiculo_id is not null;
  get diagnostics k = row_count; n := n + k;
  update correos_enviados ce set vehiculo_id = d.vehiculo_id from diagnosticos d
   where ce.vehiculo_id is null and ce.ref_tabla = 'diagnosticos' and ce.ref_id = d.id and d.vehiculo_id is not null;
  get diagnostics k = row_count; n := n + k;
  update correos_enviados ce set vehiculo_id = i.vehiculo_id from inspecciones i
   where ce.vehiculo_id is null and ce.ref_tabla = 'inspecciones' and ce.ref_id = i.id and i.vehiculo_id is not null;
  get diagnostics k = row_count; n := n + k;
  update correos_enviados ce set vehiculo_id = c.vehiculo_id from citas c
   where ce.vehiculo_id is null and ce.ref_tabla = 'citas' and ce.ref_id = c.id and c.vehiculo_id is not null;
  get diagnostics k = row_count; n := n + k;
  insert into _v63 values ('Correos asociados a su vehículo', n);
end $$;

-- Índices para que el expediente cargue rápido
create index if not exists idx_citas_vehiculo on citas (vehiculo_id);
create index if not exists idx_cotizaciones_vehiculo on cotizaciones (vehiculo_id);
create index if not exists idx_ordenes_vehiculo on ordenes (vehiculo_id);
create index if not exists idx_diagnosticos_vehiculo on diagnosticos (vehiculo_id);

-- Resultado
select paso, registros from _v63;
