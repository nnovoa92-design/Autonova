-- ============================================================
-- v61 — Plan Compra Segura 360°: certificados incluidos
--
--  * El 360° sube a $75.000 sin IVA (antes $70.000): incluye el certificado de anotaciones vigentes y el de
--    multas impagas, que tienen costo; así no baja el valor neto de la mano de obra.
--  * Su descripción menciona los certificados, y la del Esencial ya no habla de elevador.
--  * Punto nuevo «Multas de tránsito impagas» en Documentación (desde el 360°), también si ya guardaste
--    tus propios puntos en Configuración.
--
-- Requiere v60. Solo cambia lo que sigue con el valor/texto original (si ya lo editaste, se respeta).
-- Seguro de correr más de una vez.
-- ============================================================

do $$
declare
  v_map jsonb;
begin
  select insp_planes -> 'trabajos' into v_map from taller_config where id = 1;
  if v_map is null then
    raise exception 'Primero corre sql/actualizacion-v60-planes-de-inspeccion.sql';
  end if;

  -- 360°: precio y descripción
  update trabajos set precio_fijo = 75000
   where id = (v_map ->> 'total')::uuid and precio_fijo = 70000;

  update trabajos
     set descripcion = 'Todo lo del Pro, más: certificado de anotaciones vigentes y de multas impagas (incluidos en el valor), escáner de todos los módulos con datos en vivo y kilometraje cruzado entre módulos, prueba de batería, de humedad del líquido de frenos y de presión y gases del sistema de refrigeración (empaquetadura de culata), frenos traseros y discos medidos, pintura panel por panel, recalls y prueba en carretera con frenada de emergencia. Ideal para autos de alto valor, con más de 100.000 km o cuando hay dudas.'
   where id = (v_map ->> 'total')::uuid
     and descripcion = 'Todo lo del Pro, más: escáner de todos los módulos con datos en vivo y kilometraje cruzado entre módulos, prueba de batería, de humedad del líquido de frenos y de presión y gases del sistema de refrigeración (empaquetadura de culata), frenos traseros y discos medidos, pintura panel por panel, anotaciones vigentes y recalls, y prueba en carretera con frenada de emergencia. Ideal para autos de alto valor, con más de 100.000 km o cuando hay dudas.';

  -- Esencial: sin la mención al elevador
  update trabajos set descripcion = replace(descripcion, 'de todo el auto, sin elevador:', 'de todo el auto:')
   where id = (v_map ->> 'esencial')::uuid and descripcion like '%sin elevador%';
end $$;

-- Puntos guardados por el taller (Configuración → Planes): se agrega «Multas impagas» a Documentación
update taller_config c
   set insp_planes = jsonb_set(c.insp_planes, '{secciones}', (
     select jsonb_agg(
       case when e.s ->> 'id' = 'doc'
             and not exists (select 1 from jsonb_array_elements(coalesce(e.s -> 'items', '[]'::jsonb)) i where i ->> 'id' = 'doc_multas')
            then jsonb_set(e.s, '{items}', coalesce(e.s -> 'items', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                   'id', 'doc_multas', 't', 'Multas de tránsito impagas (certificado del Registro de Multas)', 'p', 2, 'n', 3)))
            else e.s end
       order by e.ord)
     from jsonb_array_elements(c.insp_planes -> 'secciones') with ordinality as e(s, ord)))
 where c.id = 1 and jsonb_typeof(c.insp_planes -> 'secciones') = 'array';

-- Verificación: el 360° debe quedar en 75000
select v.plan, t.nombre, t.precio_fijo
from taller_config c
cross join lateral jsonb_each_text(c.insp_planes -> 'trabajos') as v(plan, trabajo_id)
join trabajos t on t.id = v.trabajo_id::uuid
where c.id = 1;
