-- ============================================================
-- Actualización v49: endurecimiento de seguridad (auditoría)
--
-- 1) CRÍTICO — La tabla `perfiles` (la lista blanca de quién puede entrar) quedó con la política
--    original "cualquier usuario autenticado puede todo". Como el registro público de cuentas está
--    abierto, un tercero podía crear una cuenta, agregarse a `perfiles` como activo y ver/editar
--    TODO el sistema. Ahora solo un administrador puede escribir en `perfiles`; cada usuario solo
--    puede leer su propia fila (y los usuarios autorizados, la lista).
--
-- 2) Las fotos (bucket `fotos-ot`) se podían LISTAR sin iniciar sesión. Ahora el listado queda solo
--    para usuarios autorizados. Las fotos siguen viéndose en la app y en los informes (el bucket es
--    público por enlace).
--
-- 3) El seguimiento de OT por patente + número (portal público) no tenía límite de consultas: ahora
--    se permiten 30 consultas cada 10 minutos por conexión.
--
-- Es seguro ejecutarlo más de una vez. Requiere v9 (es_autorizado) y v47 (reservar_ip, reservar_limites).
-- ============================================================

-- ------------------------------------------------------------
-- 1) perfiles: solo un administrador puede modificar la lista blanca
-- ------------------------------------------------------------
create or replace function es_admin()
returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from perfiles where id = auth.uid() and activo and rol = 'admin') $$;

do $$
declare r record;
begin
  -- Seguro anti-bloqueo: si no hubiera ningún administrador activo, no se toca nada
  if not exists (select 1 from perfiles where activo and rol = 'admin') then
    raise exception 'No hay ningún administrador activo en perfiles: no se aplica el cambio para no dejarte sin acceso.';
  end if;
  -- Se eliminan TODAS las políticas anteriores de perfiles (incluida «acceso total a autenticados»)
  for r in select policyname from pg_policies where schemaname = 'public' and tablename = 'perfiles' loop
    execute format('drop policy %I on perfiles', r.policyname);
  end loop;
end $$;

alter table perfiles enable row level security;

create policy "perfiles_lectura" on perfiles
  for select using (id = auth.uid() or es_autorizado());

create policy "perfiles_administra" on perfiles
  for all using (es_admin()) with check (es_admin());

-- ------------------------------------------------------------
-- 2) Fotos: ya no se pueden listar sin sesión
-- ------------------------------------------------------------
drop policy if exists "fotos_ot_select" on storage.objects;
create policy "fotos_ot_select" on storage.objects
  for select to authenticated
  using (bucket_id = 'fotos-ot' and es_autorizado());

-- ------------------------------------------------------------
-- 3) Seguimiento de OT: límite de consultas por conexión
-- ------------------------------------------------------------
create or replace function portal_consultar_orden(p_patente text, p_numero bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip text := reservar_ip();
  v_n int;
  v_res jsonb;
begin
  delete from reservar_limites where creado_en < now() - interval '2 days';
  select count(*) into v_n from reservar_limites
  where ip = v_ip and tipo = 'portal' and creado_en > now() - interval '10 minutes';
  if v_n >= 30 then
    return null;
  end if;
  insert into reservar_limites (ip, tipo) values (v_ip, 'portal');

  select jsonb_build_object(
    'orden_id', o.id,
    'numero', o.numero,
    'estado', o.estado,
    'fecha_ingreso', o.fecha_ingreso,
    'fecha_entrega', o.fecha_entrega,
    'diagnostico', o.diagnostico,
    'avances', o.avances,
    'con_iva', o.con_iva,
    'descuento_tipo', o.descuento_tipo,
    'descuento_pct', o.descuento_pct,
    'descuento_monto', o.descuento_monto,
    'descuento_base', o.descuento_base,
    'vehiculo', jsonb_build_object('patente', v.patente, 'marca', v.marca, 'modelo', v.modelo),
    'taller', (
      select jsonb_build_object(
        'nombre', nombre, 'telefono', telefono,
        'direccion', direccion, 'iva_pct', iva_pct
      ) from taller_config where id = 1
    ),
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'descripcion', i.descripcion,
        'cantidad', i.cantidad,
        'precio_unitario', i.precio_unitario,
        'tipo', i.tipo,
        'tipo_otro', i.tipo_otro
      ) order by i.orden), '[]'::jsonb)
      from orden_items i where i.orden_id = o.id
    )
  )
  into v_res
  from ordenes o
  join vehiculos v on v.id = o.vehiculo_id
  where upper(replace(v.patente, ' ', '')) = upper(replace(p_patente, ' ', ''))
    and o.numero = p_numero
  limit 1;

  return v_res;
end $$;

grant execute on function portal_consultar_orden(text, bigint) to anon;

-- Resumen: quiénes pueden administrar la lista blanca
select 'v49 endurecimiento aplicado' as estado,
       (select count(*) from perfiles where activo and rol = 'admin') as administradores,
       (select count(*) from perfiles where activo) as usuarios_activos;
