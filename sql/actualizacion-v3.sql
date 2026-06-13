-- ============================================================
-- Actualización v3: Catálogo de trabajos con insumos asociados
--
-- · Cada trabajo guarda en `insumos` (jsonb) la lista de items que
--   normalmente requiere: repuestos, insumos de taller e insumos de
--   vehículo. Al elegir el trabajo en una cotización/OT se cargan
--   esas líneas automáticamente (mano de obra + insumos).
-- · Se amplían los tipos de ítem a: mano_obra, repuesto,
--   insumo_taller, insumo_vehiculo, otro.
-- · Se reemplaza el catálogo de ejemplo por el catálogo real.
--
-- EJECUTAR en el SQL Editor de Supabase. Seguro de correr más de una vez.
-- Todos los valores se manejan SIN IVA (el IVA se agrega en el total).
-- ============================================================

-- 1) Columna de insumos en el catálogo
alter table trabajos add column if not exists insumos jsonb not null default '[]'::jsonb;

-- 2) Ampliar los tipos de ítem permitidos
alter table cotizacion_items drop constraint if exists cotizacion_items_tipo_check;
alter table cotizacion_items add constraint cotizacion_items_tipo_check
  check (tipo in ('mano_obra','repuesto','insumo_taller','insumo_vehiculo','otro'));

alter table orden_items drop constraint if exists orden_items_tipo_check;
alter table orden_items add constraint orden_items_tipo_check
  check (tipo in ('mano_obra','repuesto','insumo_taller','insumo_vehiculo','otro'));

-- 3) Categorías (las que falten)
insert into categorias_trabajos (nombre, orden) values
  ('Mantención', 1),
  ('Frenos', 2),
  ('Motor', 3),
  ('Suspensión y dirección', 4),
  ('Eléctrico', 5),
  ('Climatización', 6),
  ('Transmisión y embrague', 7),
  ('Escape', 8),
  ('Neumáticos', 9),
  ('Inspección', 10),
  ('Otros servicios', 11)
on conflict (nombre) do nothing;

-- 4) Reemplazar el catálogo de trabajos por el catálogo real
delete from trabajos;

insert into trabajos (categoria_id, nombre, horas_estimadas, precio_fijo, insumos)
select c.id, v.nombre, v.horas, v.precio_fijo, v.insumos::jsonb
from (values
  -- ---------- MANTENCIÓN ----------
  ('Mantención','Cambio de aceite y filtro de aceite',0.5,null,'[{"categoria":"repuesto","descripcion":"Filtro de aceite"},{"categoria":"insumo_vehiculo","descripcion":"Aceite de motor"},{"categoria":"insumo_taller","descripcion":"Empaque/cobre tapón de drenaje"}]'),
  ('Mantención','Cambio de filtro de aire',0.3,null,'[{"categoria":"repuesto","descripcion":"Filtro de aire"}]'),
  ('Mantención','Cambio de filtro de combustible',0.5,null,'[{"categoria":"repuesto","descripcion":"Filtro de combustible"}]'),
  ('Mantención','Cambio de filtro de habitáculo (polen)',0.3,null,'[{"categoria":"repuesto","descripcion":"Filtro de habitáculo"}]'),
  ('Mantención','Cambio de bujías',0.8,null,'[{"categoria":"repuesto","descripcion":"Bujías (juego)"},{"categoria":"repuesto","descripcion":"Cables de bujía (si aplica)"}]'),
  ('Mantención','Cambio de correa de distribución (kit)',3.0,null,'[{"categoria":"repuesto","descripcion":"Kit de distribución (correa + tensores + bomba de agua)"},{"categoria":"insumo_vehiculo","descripcion":"Refrigerante"}]'),
  ('Mantención','Cambio de correa de accesorios (multicanal)',0.8,null,'[{"categoria":"repuesto","descripcion":"Correa multicanal"},{"categoria":"repuesto","descripcion":"Tensor (si corresponde)"}]'),
  ('Mantención','Cambio de líquido refrigerante',0.6,null,'[{"categoria":"insumo_vehiculo","descripcion":"Refrigerante"},{"categoria":"insumo_taller","descripcion":"Sellador (si aplica)"}]'),
  ('Mantención','Cambio de líquido de frenos',0.6,null,'[{"categoria":"insumo_vehiculo","descripcion":"Líquido de frenos DOT3/DOT4"}]'),
  ('Mantención','Cambio de aceite de caja manual',0.6,null,'[{"categoria":"insumo_vehiculo","descripcion":"Aceite de caja manual"}]'),
  ('Mantención','Cambio de aceite de caja automática',1.0,null,'[{"categoria":"insumo_vehiculo","descripcion":"Aceite de caja automática"},{"categoria":"repuesto","descripcion":"Filtro de caja (si aplica)"}]'),
  ('Mantención','Cambio de aceite de diferencial',0.5,null,'[{"categoria":"insumo_vehiculo","descripcion":"Aceite de diferencial"}]'),
  ('Mantención','Lubricación general (puntos de grasa)',0.5,null,'[{"categoria":"insumo_taller","descripcion":"Grasa multipropósito"}]'),

  -- ---------- FRENOS ----------
  ('Frenos','Cambio de pastillas de freno delanteras',0.8,null,'[{"categoria":"repuesto","descripcion":"Pastillas de freno delanteras"},{"categoria":"insumo_vehiculo","descripcion":"Líquido de frenos (relleno)"}]'),
  ('Frenos','Cambio de pastillas de freno traseras',0.8,null,'[{"categoria":"repuesto","descripcion":"Pastillas de freno traseras"}]'),
  ('Frenos','Cambio de discos de freno delanteros (par)',1.2,null,'[{"categoria":"repuesto","descripcion":"Discos delanteros (par)"},{"categoria":"repuesto","descripcion":"Pastillas delanteras (recomendado)"},{"categoria":"insumo_vehiculo","descripcion":"Líquido de frenos"}]'),
  ('Frenos','Cambio de discos de freno traseros (par)',1.2,null,'[{"categoria":"repuesto","descripcion":"Discos traseros (par)"},{"categoria":"repuesto","descripcion":"Pastillas traseras (recomendado)"}]'),
  ('Frenos','Cambio de tambores de freno (par)',1.0,null,'[{"categoria":"repuesto","descripcion":"Tambores (par)"},{"categoria":"repuesto","descripcion":"Zapatas"}]'),
  ('Frenos','Cambio de zapatas de freno traseras',1.0,null,'[{"categoria":"repuesto","descripcion":"Zapatas"},{"categoria":"insumo_taller","descripcion":"Kit de resortes"}]'),
  ('Frenos','Cambio de cilindro de rueda',0.8,null,'[{"categoria":"repuesto","descripcion":"Cilindro de rueda"},{"categoria":"insumo_vehiculo","descripcion":"Líquido de frenos"}]'),
  ('Frenos','Cambio de cilindro maestro de freno (bomba)',1.5,null,'[{"categoria":"repuesto","descripcion":"Cilindro maestro de freno"},{"categoria":"insumo_vehiculo","descripcion":"Líquido de frenos"}]'),
  ('Frenos','Purga de frenos',0.6,null,'[{"categoria":"insumo_vehiculo","descripcion":"Líquido de frenos"}]'),
  ('Frenos','Cambio de cable de freno de mano',1.0,null,'[{"categoria":"repuesto","descripcion":"Cable de freno de mano"}]'),
  ('Frenos','Cambio de servofreno (booster)',1.5,null,'[{"categoria":"repuesto","descripcion":"Servofreno"}]'),
  ('Frenos','Cambio de cañerías/mangueras de freno',1.0,null,'[{"categoria":"repuesto","descripcion":"Cañería o manguera de freno"},{"categoria":"insumo_vehiculo","descripcion":"Líquido de frenos"}]'),

  -- ---------- SUSPENSIÓN Y DIRECCIÓN ----------
  ('Suspensión y dirección','Cambio de amortiguador delantero (c/u)',1.0,null,'[{"categoria":"repuesto","descripcion":"Amortiguador delantero"}]'),
  ('Suspensión y dirección','Cambio de amortiguador trasero (c/u)',0.8,null,'[{"categoria":"repuesto","descripcion":"Amortiguador trasero"}]'),
  ('Suspensión y dirección','Cambio de par de amortiguadores',1.8,null,'[{"categoria":"repuesto","descripcion":"Amortiguadores (par)"}]'),
  ('Suspensión y dirección','Cambio de terminal de dirección (c/u)',0.6,null,'[{"categoria":"repuesto","descripcion":"Terminal de dirección"}]'),
  ('Suspensión y dirección','Cambio de barra de dirección completa',1.0,null,'[{"categoria":"repuesto","descripcion":"Barra de dirección"}]'),
  ('Suspensión y dirección','Cambio de rótula de suspensión (c/u)',1.0,null,'[{"categoria":"repuesto","descripcion":"Rótula de suspensión"}]'),
  ('Suspensión y dirección','Cambio de bujes de suspensión',1.2,null,'[{"categoria":"repuesto","descripcion":"Bujes (par)"}]'),
  ('Suspensión y dirección','Cambio de mangueta/cubo con rodamiento',1.5,null,'[{"categoria":"repuesto","descripcion":"Cubo con rodamiento"},{"categoria":"insumo_taller","descripcion":"Tuerca de cubo"}]'),
  ('Suspensión y dirección','Cambio de rodamiento de rueda (c/u)',1.2,null,'[{"categoria":"repuesto","descripcion":"Rodamiento de rueda"}]'),
  ('Suspensión y dirección','Cambio de bieleta estabilizadora (c/u)',0.5,null,'[{"categoria":"repuesto","descripcion":"Bieleta estabilizadora"}]'),
  ('Suspensión y dirección','Cambio de soporte/copela de amortiguador',0.8,null,'[{"categoria":"repuesto","descripcion":"Soporte/copela"},{"categoria":"repuesto","descripcion":"Rodamiento de suspensión"}]'),
  ('Suspensión y dirección','Cambio de bomba de dirección hidráulica',1.5,null,'[{"categoria":"repuesto","descripcion":"Bomba de dirección"},{"categoria":"insumo_vehiculo","descripcion":"Líquido hidráulico"}]'),
  ('Suspensión y dirección','Cambio de caja/cremallera de dirección',2.5,null,'[{"categoria":"repuesto","descripcion":"Caja o cremallera de dirección"}]'),
  ('Suspensión y dirección','Alineación de tren delantero',0.6,null,'[]'),
  ('Suspensión y dirección','Balanceo de ruedas (4 ruedas)',0.5,null,'[{"categoria":"insumo_taller","descripcion":"Contrapesos de balanceo"}]'),

  -- ---------- ELÉCTRICO ----------
  ('Eléctrico','Cambio de batería',0.3,null,'[{"categoria":"repuesto","descripcion":"Batería"}]'),
  ('Eléctrico','Cambio de alternador',1.5,null,'[{"categoria":"repuesto","descripcion":"Alternador"},{"categoria":"repuesto","descripcion":"Correa (si corresponde)"}]'),
  ('Eléctrico','Cambio de motor de arranque',1.5,null,'[{"categoria":"repuesto","descripcion":"Motor de arranque"}]'),
  ('Eléctrico','Cambio de bobina de encendido (c/u)',0.5,null,'[{"categoria":"repuesto","descripcion":"Bobina de encendido"}]'),
  ('Eléctrico','Diagnóstico eléctrico con escáner',0.5,null,'[]'),
  ('Eléctrico','Cambio de ampolletas/focos exteriores',0.3,null,'[{"categoria":"repuesto","descripcion":"Ampolleta/foco"}]'),
  ('Eléctrico','Cambio de fusibles/relés',0.3,null,'[{"categoria":"repuesto","descripcion":"Fusible o relé"}]'),
  ('Eléctrico','Reparación de arnés/cableado (sección)',1.0,null,'[{"categoria":"insumo_taller","descripcion":"Cinta aislante"},{"categoria":"insumo_taller","descripcion":"Conectores"},{"categoria":"insumo_taller","descripcion":"Terminales"}]'),
  ('Eléctrico','Cambio de sensor de oxígeno (sonda lambda)',0.6,null,'[{"categoria":"repuesto","descripcion":"Sonda lambda"}]'),
  ('Eléctrico','Cambio de sensor MAP/MAF',0.5,null,'[{"categoria":"repuesto","descripcion":"Sensor MAP/MAF"}]'),
  ('Eléctrico','Cambio de sensor de temperatura del motor',0.5,null,'[{"categoria":"repuesto","descripcion":"Sensor de temperatura"}]'),
  ('Eléctrico','Cambio de sensor de cigüeñal/árbol de levas',0.8,null,'[{"categoria":"repuesto","descripcion":"Sensor CKP/CMP"}]'),
  ('Eléctrico','Diagnóstico y borrado de códigos de falla',0.5,null,'[]'),

  -- ---------- MOTOR ----------
  ('Motor','Cambio de empaque de tapa de cilindros (tapa válvulas)',1.2,null,'[{"categoria":"repuesto","descripcion":"Empaque de tapa de cilindros"},{"categoria":"repuesto","descripcion":"Bujías (si se requiere desmontar)"}]'),
  ('Motor','Cambio de empaque de cárter',1.5,null,'[{"categoria":"insumo_taller","descripcion":"Empaque de cárter"},{"categoria":"insumo_vehiculo","descripcion":"Aceite de motor (relleno)"}]'),
  ('Motor','Cambio de retén delantero de cigüeñal',2.0,null,'[{"categoria":"insumo_taller","descripcion":"Retén delantero de cigüeñal"}]'),
  ('Motor','Cambio de retén trasero de cigüeñal',3.5,null,'[{"categoria":"insumo_taller","descripcion":"Retén trasero de cigüeñal"}]'),
  ('Motor','Cambio de bomba de agua',2.0,null,'[{"categoria":"repuesto","descripcion":"Bomba de agua"},{"categoria":"insumo_vehiculo","descripcion":"Refrigerante"},{"categoria":"repuesto","descripcion":"Correa (si aplica)"}]'),
  ('Motor','Cambio de termostato',1.0,null,'[{"categoria":"repuesto","descripcion":"Termostato"},{"categoria":"insumo_vehiculo","descripcion":"Refrigerante"},{"categoria":"insumo_taller","descripcion":"Empaque"}]'),
  ('Motor','Reparación de fuga de aceite (general)',1.5,null,'[{"categoria":"insumo_taller","descripcion":"Sellador"},{"categoria":"insumo_taller","descripcion":"Empaques según fuga"}]'),
  ('Motor','Rectificación de culata (envío externo)',0,null,'[{"categoria":"insumo_taller","descripcion":"Empaque de culata"},{"categoria":"insumo_taller","descripcion":"Espárragos (si se requiere)"}]'),
  ('Motor','Cambio de soportes de motor (c/u)',1.0,null,'[{"categoria":"repuesto","descripcion":"Soporte de motor"}]'),
  ('Motor','Cambio de cañería de admisión/escape (sección)',1.0,null,'[{"categoria":"repuesto","descripcion":"Cañería"},{"categoria":"insumo_taller","descripcion":"Abrazaderas"}]'),
  ('Motor','Cambio de inyector (c/u)',1.0,null,'[{"categoria":"repuesto","descripcion":"Inyector"},{"categoria":"insumo_taller","descripcion":"Retenes/o-rings"}]'),
  ('Motor','Limpieza de inyectores (ultrasonido, servicio externo)',0.5,null,'[]'),
  ('Motor','Cambio de bomba de combustible',1.5,null,'[{"categoria":"repuesto","descripcion":"Bomba de combustible"}]'),

  -- ---------- CLIMATIZACIÓN ----------
  ('Climatización','Carga de gas refrigerante A/C',0.6,null,'[{"categoria":"insumo_vehiculo","descripcion":"Gas refrigerante"},{"categoria":"insumo_taller","descripcion":"Aceite para compresor"}]'),
  ('Climatización','Cambio de compresor de A/C',2.0,null,'[{"categoria":"repuesto","descripcion":"Compresor"},{"categoria":"repuesto","descripcion":"Filtro secador"},{"categoria":"insumo_vehiculo","descripcion":"Gas refrigerante"}]'),
  ('Climatización','Cambio de filtro secador (deshidratador)',1.0,null,'[{"categoria":"repuesto","descripcion":"Filtro secador"},{"categoria":"insumo_vehiculo","descripcion":"Gas refrigerante"}]'),
  ('Climatización','Cambio de condensador de A/C',1.5,null,'[{"categoria":"repuesto","descripcion":"Condensador"},{"categoria":"insumo_vehiculo","descripcion":"Gas refrigerante"}]'),
  ('Climatización','Diagnóstico de fuga A/C (UV/electrónico)',0.8,null,'[{"categoria":"insumo_taller","descripcion":"Tinte UV (si aplica)"}]'),
  ('Climatización','Cambio de motor de ventilador A/C',0.8,null,'[{"categoria":"repuesto","descripcion":"Motor de ventilador"}]'),
  ('Climatización','Cambio de válvula de expansión',1.2,null,'[{"categoria":"repuesto","descripcion":"Válvula de expansión"},{"categoria":"insumo_vehiculo","descripcion":"Gas refrigerante"}]'),

  -- ---------- TRANSMISIÓN Y EMBRAGUE ----------
  ('Transmisión y embrague','Cambio de kit de embrague (disco + collarín + plato de presión)',4.0,null,'[{"categoria":"repuesto","descripcion":"Kit de embrague completo"}]'),
  ('Transmisión y embrague','Cambio de collarín hidráulico (cilindro esclavo)',2.0,null,'[{"categoria":"repuesto","descripcion":"Collarín hidráulico"},{"categoria":"insumo_vehiculo","descripcion":"Líquido de embrague"}]'),
  ('Transmisión y embrague','Cambio de cilindro maestro de embrague (bombín)',1.5,null,'[{"categoria":"repuesto","descripcion":"Cilindro maestro de embrague"},{"categoria":"insumo_vehiculo","descripcion":"Líquido de embrague"}]'),
  ('Transmisión y embrague','Cambio de semieje/junta homocinética (c/u)',1.2,null,'[{"categoria":"repuesto","descripcion":"Semieje/junta homocinética"}]'),
  ('Transmisión y embrague','Cambio de soporte de caja de cambios',1.0,null,'[{"categoria":"repuesto","descripcion":"Soporte de caja"}]'),
  ('Transmisión y embrague','Cambio de selector/cable de cambios',1.2,null,'[{"categoria":"repuesto","descripcion":"Cable selector de cambios"}]'),

  -- ---------- ESCAPE ----------
  ('Escape','Cambio de silenciador/tramo de escape',1.0,null,'[{"categoria":"repuesto","descripcion":"Silenciador o tramo de escape"},{"categoria":"insumo_taller","descripcion":"Abrazaderas"}]'),
  ('Escape','Cambio de catalizador',1.5,null,'[{"categoria":"repuesto","descripcion":"Catalizador"},{"categoria":"insumo_taller","descripcion":"Empaques"}]'),
  ('Escape','Reparación de fuga de escape (soldadura)',0.8,null,'[{"categoria":"insumo_taller","descripcion":"Material de soldadura"},{"categoria":"insumo_taller","descripcion":"Abrazadera"}]'),

  -- ---------- NEUMÁTICOS ----------
  ('Neumáticos','Rotación de neumáticos (4 ruedas)',0.5,null,'[]'),
  ('Neumáticos','Reparación de pinchazo (parche)',0.4,null,'[{"categoria":"insumo_taller","descripcion":"Parche/mecha"}]'),
  ('Neumáticos','Montaje y balanceo de neumático nuevo (c/u)',0.4,null,'[{"categoria":"insumo_taller","descripcion":"Válvula nueva"},{"categoria":"insumo_taller","descripcion":"Contrapesos de balanceo"}]'),

  -- ---------- INSPECCIÓN ----------
  ('Inspección','Revisión pre-compra (inspección general)',1.5,null,'[]'),
  ('Inspección','Diagnóstico general (ruidos, fallas)',1.0,null,'[]'),
  ('Inspección','Mantención preventiva completa',1.5,null,'[{"categoria":"insumo_vehiculo","descripcion":"Aceite de motor"},{"categoria":"repuesto","descripcion":"Filtro de aceite"},{"categoria":"repuesto","descripcion":"Filtro de aire"},{"categoria":"repuesto","descripcion":"Filtro de habitáculo (según corresponda)"}]'),
  ('Inspección','Revisión y reseteo de luces de mantención',0.3,null,'[]'),

  -- ---------- OTROS SERVICIOS ----------
  ('Otros servicios','Retiro y entrega a terreno',1.0,10000,'[]'),
  ('Otros servicios','Reparación de alternador',2.0,null,'[{"categoria":"repuesto","descripcion":"Carbones de alternador"},{"categoria":"repuesto","descripcion":"Regulador de voltaje"}]')
) as v(categoria_nombre, nombre, horas, precio_fijo, insumos)
join categorias_trabajos c on c.nombre = v.categoria_nombre;

-- Resumen
select c.nombre as categoria, count(*) as trabajos
from trabajos t join categorias_trabajos c on c.id = t.categoria_id
group by c.nombre order by c.nombre;
