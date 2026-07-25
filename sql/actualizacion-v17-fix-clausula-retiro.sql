-- ============================================================
-- Actualización v17: corregir cláusula de retiro del vehículo
--
-- La redacción anterior ("se reserva el derecho de proceder según la
-- normativa vigente" tras 15 días) era ambigua y riesgosa: en Chile,
-- un taller NO puede vender, desmantelar ni disponer de un vehículo
-- no retirado por su cuenta. Solo existe el "derecho legal de
-- retención" (negarse a entregarlo hasta que paguen) y, si hay deuda
-- impaga, la única vía para forzar su cobro es un proceso judicial
-- (demanda, embargo y remate ordenados por un tribunal).
--
-- Referencia: Corte Suprema confirmó el 12-06-2026 una condena contra
-- un taller de Rancagua por desmantelar el vehículo de un cliente que
-- no pudo retirarlo a tiempo (COVID) — $7.900.000 + $500.000 + multa
-- fiscal por infracción a la Ley 19.496 (Ley del Consumidor).
-- ============================================================

update taller_config set politicas_generales_texto =
'RETIRO DEL VEHÍCULO
El vehículo debe ser retirado dentro de 2 días corridos desde que se notifica que está listo. Pasado ese plazo, se cobrará un bodegaje de $3.500 por día, el cual se sumará a la deuda total. Mientras existan saldos pendientes de pago (reparación y/o bodegaje), Autonova ejercerá el derecho legal de retención del vehículo que le asiste conforme a la ley. Si transcurren 15 días sin retiro ni respuesta del cliente pese a los intentos de contacto, Autonova se reserva el derecho de iniciar las acciones judiciales de cobro que correspondan. Autonova no dispondrá, venderá ni desmantelará el vehículo sin autorización expresa y por escrito del cliente, o sin una resolución judicial que así lo ordene.

PERTENENCIAS Y OBJETOS PERSONALES
Se recomienda al cliente retirar objetos de valor antes de dejar el vehículo. Autonova no se responsabiliza por objetos personales no declarados expresamente en la recepción. Los objetos visibles al momento del ingreso quedan registrados en el checklist de recepción.

GARANTÍA GENERAL
Los trabajos realizados cuentan con garantía general de 3 meses, sin perjuicio de garantías específicas mayores indicadas para el servicio realizado en esta orden. La garantía no cubre: mal uso, modificaciones no autorizadas, repuestos no instalados por Autonova, desgaste normal, ni fallas por falta de mantenciones posteriores.

LEGALIDADES Y RESPONSABILIDAD
Autonova no responde por daños o fallas preexistentes no declaradas en la recepción del vehículo. La responsabilidad de Autonova se limita al valor del trabajo facturado, salvo dolo o negligencia grave. Se emite boleta o factura por cada servicio, conforme a la Ley N° 19.496 sobre Protección de los Derechos de los Consumidores.

INSPECCIÓN DE RECEPCIÓN
Al ingresar el vehículo se registra kilometraje, nivel de combustible, estado visual de la carrocería y pertenencias visibles. La firma del cliente valida su conformidad con este registro.'
where id = 1;

-- También se actualiza el default para instalaciones nuevas
alter table taller_config alter column politicas_generales_texto set default
'RETIRO DEL VEHÍCULO
El vehículo debe ser retirado dentro de 2 días corridos desde que se notifica que está listo. Pasado ese plazo, se cobrará un bodegaje de $3.500 por día, el cual se sumará a la deuda total. Mientras existan saldos pendientes de pago (reparación y/o bodegaje), Autonova ejercerá el derecho legal de retención del vehículo que le asiste conforme a la ley. Si transcurren 15 días sin retiro ni respuesta del cliente pese a los intentos de contacto, Autonova se reserva el derecho de iniciar las acciones judiciales de cobro que correspondan. Autonova no dispondrá, venderá ni desmantelará el vehículo sin autorización expresa y por escrito del cliente, o sin una resolución judicial que así lo ordene.

PERTENENCIAS Y OBJETOS PERSONALES
Se recomienda al cliente retirar objetos de valor antes de dejar el vehículo. Autonova no se responsabiliza por objetos personales no declarados expresamente en la recepción. Los objetos visibles al momento del ingreso quedan registrados en el checklist de recepción.

GARANTÍA GENERAL
Los trabajos realizados cuentan con garantía general de 3 meses, sin perjuicio de garantías específicas mayores indicadas para el servicio realizado en esta orden. La garantía no cubre: mal uso, modificaciones no autorizadas, repuestos no instalados por Autonova, desgaste normal, ni fallas por falta de mantenciones posteriores.

LEGALIDADES Y RESPONSABILIDAD
Autonova no responde por daños o fallas preexistentes no declaradas en la recepción del vehículo. La responsabilidad de Autonova se limita al valor del trabajo facturado, salvo dolo o negligencia grave. Se emite boleta o factura por cada servicio, conforme a la Ley N° 19.496 sobre Protección de los Derechos de los Consumidores.

INSPECCIÓN DE RECEPCIÓN
Al ingresar el vehículo se registra kilometraje, nivel de combustible, estado visual de la carrocería y pertenencias visibles. La firma del cliente valida su conformidad con este registro.';

select 'v17 clausula de retiro corregida' as estado;
