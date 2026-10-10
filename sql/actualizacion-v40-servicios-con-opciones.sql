-- ============================================================
-- Actualización v40: servicios con opciones (combos) y diagnóstico mínimo 1 hora
--
-- 1) trabajos.opciones: un servicio base puede NO venderse solo. Ej.:
--      "Cambio de pastillas de freno" -> opciones obligatorias:
--         · "con cambio de discos"        (precio cerrado de mano de obra)
--         · "con rectificación de discos" (precio cerrado de mano de obra)
--    Al agregar el servicio a una cotización, OT o diagnóstico, el sistema
--    pregunta con qué opción y carga la línea con el precio cerrado de esa
--    combinación (neto, sin IVA). Cada opción se guarda como
--    { nombre, precio, horas }.
--
-- 2) Diagnóstico: se cobra mínimo 1 hora y luego por cuarto de hora (sube al
--    siguiente cuarto). La pantalla lo aplica al guardar; aquí se ajustan los
--    diagnósticos ya guardados que aún no se convirtieron en cotización/OT, para
--    que el link del cliente muestre lo mismo.
--
-- Seguro de correr más de una vez.
-- ============================================================

alter table trabajos
  add column if not exists opciones jsonb not null default '[]'::jsonb;

comment on column trabajos.opciones is 'Opciones obligatorias del servicio (combos): [{nombre, precio (neto, mano de obra), horas}]. Si hay opciones, el servicio no se vende solo.';

-- Diagnósticos aún sin convertir: mínimo 1 h, redondeado hacia arriba al cuarto de hora
update diagnosticos
set horas_diagnostico = greatest(1, ceil(horas_diagnostico * 4) / 4)
where horas_diagnostico > 0
  and cotizacion_id is null
  and horas_diagnostico <> greatest(1, ceil(horas_diagnostico * 4) / 4);

-- La lista pública de servicios (reserva online) ahora también informa si tienen opciones,
-- para poder mostrar "desde $X" en vez de un valor único.
create or replace function reservar_info()
returns jsonb language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'taller', (select jsonb_build_object('nombre', nombre, 'telefono', telefono, 'direccion', direccion) from taller_config where id = 1),
    'horarios', (select jsonb_build_object('apertura', hora_apertura, 'cierre', hora_cierre, 'sab_apertura', sab_apertura, 'sab_cierre', sab_cierre, 'slot_min', coalesce(slot_min,60)) from taller_config where id = 1),
    'trabajos', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'nombre', nombre, 'horas', horas_estimadas, 'precio_fijo', precio_fijo,
        'precio_desde', (select min((o ->> 'precio')::numeric) from jsonb_array_elements(coalesce(opciones, '[]'::jsonb)) o where (o ->> 'precio') is not null)
      ) order by nombre), '[]'::jsonb) from trabajos where activo)
  );
$$;
grant execute on function reservar_info() to anon;

select 'v40 servicios con opciones aplicado' as estado;
