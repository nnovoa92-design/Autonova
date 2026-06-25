-- ============================================================
-- Actualización v9: BLINDAJE DE SEGURIDAD (crítico)
--
-- Problema: hoy CUALQUIER usuario autenticado tiene acceso total.
-- Como el registro público está habilitado, un tercero podría
-- crear una cuenta y ver/editar todos los datos.
--
-- Solución: el acceso se restringe a usuarios que estén en la tabla
-- `perfiles` (lista blanca). Un registro externo NO está en perfiles,
-- así que no ve nada — aunque logre autenticarse.
--
-- Para agregar un empleado en el futuro: créale el usuario en
-- Authentication y agrégalo a `perfiles`.
--
-- EJECUTAR en el SQL Editor de Supabase. Seguro de correr más de una vez.
-- ============================================================

-- 1) Asegurar que el DUEÑO esté en la lista blanca (evita auto-bloqueo)
insert into perfiles (id, nombre, rol, activo)
values ('ebeacf39-185f-4a02-abf5-4a18d352c174', 'Nicolás Novoa', 'admin', true)
on conflict (id) do update set activo = true, rol = 'admin';

-- 2) Función de autorización (usuario presente y activo en perfiles)
create or replace function es_autorizado()
returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from perfiles where id = auth.uid() and activo) $$;

-- 3) Reemplazar las políticas "acceso total" por la lista blanca
do $$
declare t text;
begin
  foreach t in array array[
    'clientes','vehiculos','personal','categorias_trabajos','trabajos',
    'repuestos','movimientos_stock','cotizaciones','cotizacion_items',
    'ordenes','orden_items','registro_horas','pagos','taller_config',
    'inspecciones','recordatorios','movimientos_contables','ventas_dte','compras_dte'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "Usuarios autenticados acceso total" on %I', t);
    execute format('drop policy if exists "Acceso solo usuarios autorizados" on %I', t);
    execute format(
      'create policy "Acceso solo usuarios autorizados" on %I for all using (es_autorizado()) with check (es_autorizado())', t
    );
  end loop;
end $$;

-- 4) Storage: subir/borrar fotos solo usuarios autorizados (lectura sigue pública para el portal)
drop policy if exists "fotos_ot_insert" on storage.objects;
create policy "fotos_ot_insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'fotos-ot' and es_autorizado());

drop policy if exists "fotos_ot_delete" on storage.objects;
create policy "fotos_ot_delete" on storage.objects
  for delete to authenticated using (bucket_id = 'fotos-ot' and es_autorizado());

select 'v9 seguridad aplicada' as estado, count(*) as perfiles_autorizados from perfiles where activo;
