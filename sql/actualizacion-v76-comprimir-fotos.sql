-- ============================================================
-- Autonova · Actualización v76 · Comprimir fotos guardadas
-- Permite que el ADMINISTRADOR reemplace una foto del bucket `fotos-ot`
-- por su versión comprimida (mismo nombre y misma dirección, así las OT,
-- diagnósticos e inspecciones siguen mostrando la foto sin cambiar nada).
-- No borra ni comprime nada por sí sola: eso se hace desde
-- Configuración → Espacio de fotos, cuando tú lo decidas.
-- ============================================================

drop policy if exists "fotos_ot_update_admin" on storage.objects;
create policy "fotos_ot_update_admin" on storage.objects
  for update to authenticated
  using (bucket_id = 'fotos-ot' and es_admin())
  with check (bucket_id = 'fotos-ot' and es_admin());

-- Comprobación: debe decir «permiso ok»
select case when exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'fotos_ot_update_admin')
            then 'permiso ok' else 'FALTA el permiso' end as resultado;
