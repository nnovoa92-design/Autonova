-- ============================================================
-- Actualización v20: Garantías por categoría + cláusula de repuestos
--
-- · Actualiza las 4 categorías que ya tenían garantía configurada
--   (Climatización, Eléctrico, Escape, Frenos) y crea las 8 que
--   estaban en 0, con valores definidos junto al dueño del taller
-- · Agrega a las políticas generales una cláusula explícita sobre
--   repuestos: sin garantía si los trae el cliente; si los compra
--   Autonova, se gestiona con el proveedor pero no se garantiza
--   directamente, caso a caso según cada proveedor
-- ============================================================

-- Paso 1: actualizar políticas que ya existían
update service_policies sp
set garantia_meses = v.meses, garantia_tipo = v.tipo
from (values
  ('Frenos', 3, 'trabajo'),
  ('Suspensión y dirección', 3, 'trabajo'),
  ('Motor', 6, 'trabajo'),
  ('Transmisión y embrague', 3, 'trabajo'),
  ('Eléctrico', 3, 'trabajo'),
  ('Climatización', 3, 'trabajo'),
  ('Escape', 3, 'trabajo'),
  ('Mantención', 3, 'trabajo'),
  ('Neumáticos', 1, 'trabajo'),
  ('Otros servicios', 3, 'trabajo'),
  ('Inspección', 0, 'ninguna'),
  ('Servicios Externos', 0, 'ninguna')
) as v(categoria_nombre, meses, tipo)
join categorias_trabajos c on c.nombre = v.categoria_nombre
where sp.categoria_id = c.id;

-- Paso 2: crear políticas para las categorías que estaban sin fila
insert into service_policies (categoria_id, nombre, garantia_meses, garantia_tipo)
select c.id, v.categoria_nombre, v.meses, v.tipo
from (values
  ('Frenos', 3, 'trabajo'),
  ('Suspensión y dirección', 3, 'trabajo'),
  ('Motor', 6, 'trabajo'),
  ('Transmisión y embrague', 3, 'trabajo'),
  ('Eléctrico', 3, 'trabajo'),
  ('Climatización', 3, 'trabajo'),
  ('Escape', 3, 'trabajo'),
  ('Mantención', 3, 'trabajo'),
  ('Neumáticos', 1, 'trabajo'),
  ('Otros servicios', 3, 'trabajo'),
  ('Inspección', 0, 'ninguna'),
  ('Servicios Externos', 0, 'ninguna')
) as v(categoria_nombre, meses, tipo)
join categorias_trabajos c on c.nombre = v.categoria_nombre
where not exists (select 1 from service_policies sp where sp.categoria_id = c.id);

-- Paso 3: agregar cláusula de repuestos a las políticas generales
update taller_config set politicas_generales_texto =
'RETIRO DEL VEHÍCULO
El vehículo debe ser retirado dentro de 2 días corridos desde que se notifica que está listo. Pasado ese plazo, se cobrará un bodegaje de $3.500 por día, el cual se sumará a la deuda total. Mientras existan saldos pendientes de pago (reparación y/o bodegaje), Autonova ejercerá el derecho legal de retención del vehículo que le asiste conforme a la ley. Si transcurren 15 días sin retiro ni respuesta del cliente pese a los intentos de contacto, Autonova se reserva el derecho de iniciar las acciones judiciales de cobro que correspondan. Autonova no dispondrá, venderá ni desmantelará el vehículo sin autorización expresa y por escrito del cliente, o sin una resolución judicial que así lo ordene.

PERTENENCIAS Y OBJETOS PERSONALES
Se recomienda al cliente retirar objetos de valor antes de dejar el vehículo. Autonova no se responsabiliza por objetos personales no declarados expresamente en la recepción. Los objetos visibles al momento del ingreso quedan registrados en el checklist de recepción.

GARANTÍA GENERAL
Los trabajos realizados cuentan con garantía general de 3 meses sobre la mano de obra, sin perjuicio de garantías específicas mayores indicadas para la categoría del servicio realizado en esta orden. La garantía no cubre: mal uso, modificaciones no autorizadas, desgaste normal, ni fallas por falta de mantenciones posteriores.

Respecto de los repuestos: si el repuesto fue proporcionado por el cliente, Autonova no otorga garantía alguna sobre su funcionamiento o eventual falla. Si el repuesto fue adquirido por Autonova a un proveedor, Autonova no garantiza directamente la durabilidad del componente, pero gestionará la reclamación correspondiente ante el proveedor respectivo, cuyos términos y plazos de garantía se consultarán de forma particular en cada caso.

LEGALIDADES Y RESPONSABILIDAD
Autonova no responde por daños o fallas preexistentes no declaradas en la recepción del vehículo. La responsabilidad de Autonova se limita al valor del trabajo facturado, salvo dolo o negligencia grave. Se emite boleta o factura por cada servicio, conforme a la Ley N° 19.496 sobre Protección de los Derechos de los Consumidores.

INSPECCIÓN DE RECEPCIÓN
Al ingresar el vehículo se registra kilometraje, nivel de combustible, estado visual de la carrocería y pertenencias visibles. La firma del cliente valida su conformidad con este registro.'
where id = 1;

select 'v20 politicas garantia por categoria aplicada' as estado;
