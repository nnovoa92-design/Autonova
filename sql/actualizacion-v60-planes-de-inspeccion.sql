-- ============================================================
-- v60 — Planes de inspección precompra
--
--  * Tres planes (Compra Segura Esencial / Pro / 360°) creados como servicios del Catálogo de trabajos,
--    categoría «Inspecciones precompra», con su precio sin IVA ($45.000 / $55.000 / $70.000), descripción y
--    duración. El nombre, precio, descripción y duración del plan SON los de ese servicio: si se cambian en el
--    catálogo o en Configuración → Planes de inspección, se ve igual en ambos lados.
--  * taller_config.insp_planes: vínculo plan → servicio del catálogo, lema/destacado de cada plan y, si se
--    editan en Configuración, las secciones y puntos de inspección del taller.
--  * inspecciones: cliente y vehículo (fichas de Clientes y Vehículos), plan elegido y su valor sin IVA.
--
-- Seguro de correr más de una vez (no duplica los servicios).
-- ============================================================

alter table taller_config add column if not exists insp_planes jsonb not null default '{}'::jsonb;

alter table inspecciones add column if not exists cliente_id uuid references clientes(id) on delete set null;
alter table inspecciones add column if not exists vehiculo_id uuid references vehiculos(id) on delete set null;
alter table inspecciones add column if not exists plan text;
alter table inspecciones add column if not exists valor numeric(12,2);
create index if not exists idx_inspecciones_cliente on inspecciones (cliente_id);
create index if not exists idx_inspecciones_vehiculo on inspecciones (vehiculo_id);

comment on column taller_config.insp_planes is 'Planes de inspección precompra: { trabajos: {esencial|pro|total: id del servicio}, planes: {id: {lema, destacado}}, secciones: [...] }';
comment on column inspecciones.plan is 'Plan elegido: esencial | pro | total (el detalle queda en datos._plan)';
comment on column inspecciones.valor is 'Valor del plan sin IVA al momento de la inspección';

do $$
declare
  v_cat uuid;
  v_id uuid;
  v_mapa jsonb := '{}'::jsonb;
  r record;
begin
  -- Ya vinculados (se corrió antes): no se crea nada de nuevo
  if exists (select 1 from taller_config where id = 1 and coalesce(insp_planes, '{}'::jsonb) ? 'trabajos') then
    return;
  end if;

  insert into categorias_trabajos (nombre, orden) values ('Inspecciones precompra', 0)
  on conflict (nombre) do nothing;
  select id into v_cat from categorias_trabajos where nombre = 'Inspecciones precompra';

  for r in
    select * from (values
      ('esencial', 'Compra Segura Esencial', 45000::numeric, 1.0::numeric,
       'Revisión visual y funcional de todo el auto, sin elevador: documentos, luces y electrónica, testigos y medidores del panel, niveles, fugas visibles, frenos, neumáticos, carrocería e interior, lectura de códigos de falla con escáner y prueba en ruta urbana. Ideal para autos recientes o de bajo kilometraje, o para descartar entre varias opciones.'),
      ('pro', 'Compra Segura Pro', 55000::numeric, 1.5::numeric,
       'Todo lo del Esencial, más: revisión bajo el vehículo (chasis, fugas, rótulas, homocinéticas, espirales y cremallera), medición de pastillas y discos delanteros, espesor de pintura en capot, techo y puertas, búsqueda de choques e inundación, verificación del kilometraje y del VIN, y prueba en ruta ampliada. Ideal para la mayoría de los autos usados.'),
      ('total', 'Compra Segura 360°', 70000::numeric, 2.0::numeric,
       'Todo lo del Pro, más: escáner de todos los módulos con datos en vivo y kilometraje cruzado entre módulos, prueba de batería, de humedad del líquido de frenos y de presión y gases del sistema de refrigeración (empaquetadura de culata), frenos traseros y discos medidos, pintura panel por panel, anotaciones vigentes y recalls, y prueba en carretera con frenada de emergencia. Ideal para autos de alto valor, con más de 100.000 km o cuando hay dudas.')
    ) as t(plan, nombre, precio, horas, descripcion)
  loop
    v_id := null;
    select id into v_id from trabajos where nombre = r.nombre order by activo desc, creado_en limit 1;
    if v_id is null then
      insert into trabajos (categoria_id, nombre, descripcion, horas_estimadas, precio_fijo)
      values (v_cat, r.nombre, r.descripcion, r.horas, r.precio)
      returning id into v_id;
    end if;
    v_mapa := v_mapa || jsonb_build_object(r.plan, v_id);
  end loop;

  update taller_config
     set insp_planes = coalesce(insp_planes, '{}'::jsonb) || jsonb_build_object('trabajos', v_mapa)
   where id = 1;
end $$;

-- Verificación: debe mostrar los 3 planes con su precio
select v.plan, t.nombre, t.precio_fijo, t.horas_estimadas
from taller_config c
cross join lateral jsonb_each_text(c.insp_planes -> 'trabajos') as v(plan, trabajo_id)
join trabajos t on t.id = v.trabajo_id::uuid
where c.id = 1;
