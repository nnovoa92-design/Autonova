-- ============================================================
-- v81 — Avance de la OT por categoría, ponderado por horas
--
--  * Catálogo: cada trabajo puede tener sus TAREAS (pasos): desarme, rectificación, armado…
--    (trabajos.tareas = [{ id, nombre, horas? }]). La OT las lee del catálogo en vivo: si cambias
--    las tareas de un trabajo, cambian en todas las OT.
--  * OT: cada tarea se marca ✓ con comentario y fotos (tabla ot_checks). Los repuestos se marcan
--    pedido / recibido / instalado (solo los que se usen), también con comentario y foto; no suman al %.
--  * El % se pondera con las horas de cada trabajo. ordenes.progreso guarda el resumen
--    (total, por categoría y último envío al cliente) y el seguimiento del cliente (portal) lo muestra.
--  * Se cargan tareas sugeridas en los trabajos largos del catálogo (solo si aún no tienen tareas).
--
-- Requiere v80. Seguro de correr más de una vez.
-- ============================================================

alter table trabajos add column if not exists tareas jsonb not null default '[]'::jsonb;
alter table ordenes add column if not exists progreso jsonb;

create table if not exists ot_checks (
  id uuid primary key default gen_random_uuid(),
  orden_id uuid not null references ordenes(id) on delete cascade,
  item_id uuid not null references orden_items(id) on delete cascade,
  clave text not null,                    -- id de la tarea del catálogo, '_' (trabajo sin tareas) o pedido/recibido/instalado
  comentario text,
  fotos jsonb not null default '[]'::jsonb,
  hecho_por uuid default auth.uid(),
  hecho_por_nombre text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz,
  unique (item_id, clave)
);
create index if not exists idx_ot_checks_orden on ot_checks (orden_id);

alter table ot_checks enable row level security;
drop policy if exists ot_checks_autorizado on ot_checks;
create policy ot_checks_autorizado on ot_checks for all using (es_autorizado()) with check (es_autorizado());

-- Quién marcó: el nombre de su perfil (o del personal vinculado)
create or replace function _ot_check_autor() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.hecho_por := coalesce(new.hecho_por, auth.uid());
    new.hecho_por_nombre := coalesce(
      (select nombre from personal where perfil_id = new.hecho_por and activo limit 1),
      (select nombre from perfiles where id = new.hecho_por), new.hecho_por_nombre);
  else
    new.actualizado_en := now();
  end if;
  return new;
end $$;
drop trigger if exists trg_ot_check_autor on ot_checks;
create trigger trg_ot_check_autor before insert or update on ot_checks
  for each row execute function _ot_check_autor();

-- Seguimiento del cliente: igual que v56 + el avance ponderado
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
    'progreso', case when o.progreso is null then null else jsonb_build_object(
                  'pct', o.progreso -> 'pct', 'categorias', o.progreso -> 'categorias', 'actualizado', o.progreso -> 'actualizado') end,
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
        'tipo_otro', i.tipo_otro,
        'horas', i.horas,
        'por_hora', i.por_hora
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

-- Tareas sugeridas para los trabajos largos (solo si aún no tienen; se editan en Catálogo)
create or replace function _tareas_sugeridas(variadic p_nombres text[]) returns jsonb
language sql immutable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', 't' || n, 'nombre', nombre) order by n), '[]'::jsonb)
    from unnest(p_nombres) with ordinality as x(nombre, n);
$$;

update trabajos set tareas = _tareas_sugeridas('Desarme y retiro de culata', 'Revisión y rectificación de culata', 'Armado de culata', 'Montaje y torque', 'Llenado de fluidos y prueba de motor')
 where nombre ilike 'Cambio de Culata%' and tareas = '[]'::jsonb;
update trabajos set tareas = _tareas_sugeridas('Desarme de accesorios y tapa de distribución', 'Cambio de cadena, guías y tensor', 'Puesta a punto', 'Armado', 'Prueba de motor')
 where nombre ilike 'Cambio Cadena de distribuci%' and tareas = '[]'::jsonb;
update trabajos set tareas = _tareas_sugeridas('Desarme de accesorios y tapas', 'Cambio de correa, tensor y poleas', 'Puesta a punto', 'Armado y prueba de motor')
 where nombre ilike 'Cambio de correa de distribución%' and tareas = '[]'::jsonb;
update trabajos set tareas = _tareas_sugeridas('Desarme de accesorios y tapas', 'Cambio de correa, tensor y poleas', 'Cambio de bomba de agua', 'Puesta a punto', 'Llenado de refrigerante y prueba')
 where nombre ilike 'Cambio Kit distribución%' and tareas = '[]'::jsonb;
update trabajos set tareas = _tareas_sugeridas('Desarme de distribución', 'Cambio de bomba de agua', 'Armado y puesta a punto', 'Llenado de refrigerante y prueba')
 where nombre ilike 'Cambio de bomba de agua en distribuci%' and tareas = '[]'::jsonb;
update trabajos set tareas = _tareas_sugeridas('Desmontaje de caja', 'Cambio de disco, plato y collarín', 'Montaje de caja', 'Regulación y prueba de ruta')
 where (nombre ilike 'Cambio de kit de embrague%' or nombre ilike 'Cambio de Embrague 4x4%') and tareas = '[]'::jsonb;
update trabajos set tareas = _tareas_sugeridas('Desconexión y retiro de motor', 'Instalación de motor', 'Conexiones y llenado de fluidos', 'Prueba de motor')
 where nombre ilike 'Retiro e instalación de motor%' and tareas = '[]'::jsonb;
update trabajos set tareas = _tareas_sugeridas('Cambio de aceite y filtros', 'Revisión de frenos y suspensión', 'Revisión de niveles, luces y neumáticos', 'Scanner y prueba de ruta')
 where nombre ilike 'Mantención preventiva completa%' and tareas = '[]'::jsonb;
update trabajos set tareas = _tareas_sugeridas('Desmontaje de cremallera', 'Instalación de cremallera', 'Purga y prueba de dirección')
 where nombre ilike 'Cambio de Cremallera%' and tareas = '[]'::jsonb;
update trabajos set tareas = _tareas_sugeridas('Recuperación de gas', 'Cambio de compresor', 'Vacío y carga de gas', 'Prueba de A/C')
 where nombre ilike 'Cambio de compresor de A/C%' and tareas = '[]'::jsonb;
update trabajos set tareas = _tareas_sugeridas('Vaciado de aceite y desmontaje de cárter', 'Limpieza y sellado', 'Montaje y llenado de aceite')
 where nombre ilike 'Cambio de empaque de cárter%' and tareas = '[]'::jsonb;

-- Verificación: debe decir «ok» y cuántos trabajos quedaron con tareas
select case when exists (select 1 from information_schema.columns where table_name = 'trabajos' and column_name = 'tareas')
             and exists (select 1 from information_schema.columns where table_name = 'ordenes' and column_name = 'progreso')
             and to_regclass('public.ot_checks') is not null
            then 'ok' else 'revisar' end as v81,
       (select count(*) from trabajos where activo and jsonb_array_length(tareas) > 0) as trabajos_con_tareas;
