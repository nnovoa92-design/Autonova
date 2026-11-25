-- ============================================================
-- DIAGNÓSTICO DE ESPACIO (solo lee: no borra ni cambia nada)
-- Pégalo en Supabase → SQL Editor → Run. Copia los 3 resultados (o una captura) y envíamelos.
-- ============================================================

-- 1) Tamaño total de la base de datos (el plan gratis permite 500 MB)
select pg_size_pretty(pg_database_size(current_database())) as base_de_datos_total;

-- 2) Las 15 tablas más pesadas
select c.relname as tabla,
       pg_size_pretty(pg_total_relation_size(c.oid)) as tamano,
       c.reltuples::bigint as filas_aprox
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where c.relkind = 'r' and n.nspname in ('public', 'cron', 'net', 'storage', 'auth')
 order by pg_total_relation_size(c.oid) desc
 limit 15;

-- 3) Archivos guardados (fotos, firmas, vouchers): el plan gratis permite 1 GB
select bucket_id as carpeta,
       count(*) as archivos,
       pg_size_pretty(coalesce(sum((metadata ->> 'size')::bigint), 0)) as tamano,
       pg_size_pretty(coalesce(avg((metadata ->> 'size')::bigint), 0)::bigint) as promedio_por_archivo
  from storage.objects
 group by bucket_id
 order by sum((metadata ->> 'size')::bigint) desc nulls last;
