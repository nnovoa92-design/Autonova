-- ============================================================
-- Actualización v26: plantillas de mensajes editables en Configuración
--
-- Los mensajes de WhatsApp (confirmación/recordatorio de cita,
-- mantención, revisión técnica) y las líneas de modalidad estaban
-- escritos directamente en el código. Ahora viven en taller_config
-- como texto editable, con tokens {nombre}/{fecha}/{hora}/etc. que la
-- app reemplaza al momento de generar el mensaje.
-- ============================================================

ALTER TABLE taller_config
ADD COLUMN IF NOT EXISTS msg_confirmacion_cita text,
ADD COLUMN IF NOT EXISTS msg_recordatorio_cita text,
ADD COLUMN IF NOT EXISTS msg_recordatorio_mantencion text,
ADD COLUMN IF NOT EXISTS msg_recordatorio_revision_tecnica text,
ADD COLUMN IF NOT EXISTS msg_modalidad_taller text,
ADD COLUMN IF NOT EXISTS msg_modalidad_retiro text,
ADD COLUMN IF NOT EXISTS msg_modalidad_terreno text;

update taller_config set
  msg_confirmacion_cita = 'Hola, {nombre},

Le saluda el equipo de {taller}. Confirmamos su cita:

Fecha: {fecha} a las {hora}
Servicio: {servicio}

Lo que puede esperar:
{precio_linea}
{tiempo_linea}
{modalidad_linea}

Cualquier cambio, avísenos con tiempo. ¡Le esperamos!',

  msg_recordatorio_cita = 'Hola, {nombre},

Le saluda el equipo de {taller}. Este es un recordatorio de su cita:

Fecha: mañana a las {hora}
Servicio: {servicio}

Lo que puede esperar:
{precio_linea}
{tiempo_linea}
{modalidad_linea}

Gracias por confiar en nosotros. ¡Nos vemos mañana!',

  msg_recordatorio_mantencion = 'Hola, {nombre}

Le saluda el equipo de {taller}. Queremos contarle que ya están próximos a cumplirse 12 meses desde el último servicio realizado a su vehículo patente {patente}.

Por este motivo, queremos invitarle a programar una nueva mantención preventiva, para revisar su estado general, anticiparnos a posibles fallas y ayudarle a mantenerlo seguro, confiable y en buenas condiciones.

Será un gusto volver a recibirle, revisar su vehículo con dedicación y efectuar los trabajos que realmente necesite.

Quedamos atentos para coordinar una hora en el día que más le acomode.',

  msg_recordatorio_revision_tecnica = 'Hola, {nombre}

Le saluda el equipo de {taller}. Queremos recordarle que la revisión técnica de su vehículo, patente {patente}, corresponde durante este mes.

Para ayudarle a ahorrar tiempo y evitar esperas, contamos con el servicio de traslado y gestión de revisión técnica. Nosotros retiramos su vehículo, realizamos una inspección preventiva de los principales puntos y lo llevamos a la planta de revisión técnica.

Quedamos atentos para ayudarle y coordinar una hora.',

  msg_modalidad_taller = 'Le recomendamos llegar 5 minutos antes y traer su cédula.',
  msg_modalidad_retiro = 'Pasaremos a retirar su vehículo a la hora acordada en {direccion}. Tenga las llaves y el padrón a mano.',
  msg_modalidad_terreno = 'Un mecánico llegará a la hora acordada a {direccion}. Le pedimos que el vehículo esté accesible y tenga las llaves a mano.'
where id = 1;

select 'v26 plantillas de mensajes aplicada' as estado;
