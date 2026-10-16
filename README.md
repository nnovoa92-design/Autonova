# Autonova — Sistema de Gestión de Taller Mecánico

Aplicación web para administrar un taller mecánico, inspirada en GestionCar:
cotizaciones, órdenes de trabajo (OT), catálogo de trabajos precargados,
inventario de repuestos, horas de taller y pagos.

**Stack:** HTML + CSS + JavaScript puro (sin build) + Supabase (base de datos
Postgres, autenticación y API). Se puede hospedar en cualquier hosting
estático (Netlify, Vercel, Cloudflare Pages).

## Módulos

| Página | Función |
|---|---|
| `index.html` | Login (Supabase Auth) |
| `pages/dashboard.html` | KPIs: OTs activas, cotizaciones pendientes, stock bajo, horas e ingresos del mes |
| `pages/diagnosticos.html` | Diagnóstico de un vehículo sin cotización ni OT: motivo de consulta, **pruebas y monitoreos** (nombre + resultado + fotos: compresión, vacío, hermeticidad, scanner…), conclusión, **valor del diagnóstico** (tiempo real: horas con decimales o minutos, × valor hora; sin mínimo), trabajos recomendados y resumen de valores (total si acepta / solo diagnóstico si rechaza), con informe PDF. Incluye la **inspección de ingreso** (checklist del estado del vehículo que el cliente firma a distancia y que pasa a la OT al crearla). El cliente acepta o rechaza los trabajos desde su link. Se convierte en cotización y/o OT; desde ahí manda la cotización/OT y el diagnóstico las muestra (requiere `sql/actualizacion-v32-diagnosticos.sql`, `v34-diagnostico-valor`, `v37-diagnostico-respuesta` y `v39-inspeccion-ingreso-diagnostico`) |
| `pages/cotizaciones.html` | Crear/editar cotizaciones eligiendo **trabajos precargados** o repuestos, descuento, IVA, impresión y conversión a OT |
| `pages/ordenes.html` | Órdenes de trabajo con estados (recepción → diagnóstico → en proceso → listo → entregado), ítems, **registro de horas por mecánico** y descuento automático de stock |
| `pages/clientes.html` | Clientes con sus vehículos |
| `pages/vehiculos.html` | Vehículos (patente, marca, modelo, año, km, cilindrada/motor, combustible, tipo, N° de motor, color, transmisión, VIN). Combustible, tipo, N° de motor, color y transmisión requieren `sql/actualizacion-v51-datos-del-vehiculo.sql` |
| `pages/trabajos.html` | Catálogo de trabajos con horas estimadas; precio = horas × valor hora del taller (o precio fijo) |
| `pages/inventario.html` | Repuestos con stock, mínimos, entradas/salidas/ajustes |
| `pages/pagos.html` | Pagos por OT con saldo pendiente |
| `pages/inspecciones.html` | Inspecciones precompra: checklist de 7 secciones con puntaje 0-100, recomendación, ítems extra, WhatsApp, impresión y link público |
| `pages/configuracion.html` | Configuración: datos del taller, valor hora, IVA y porcentajes de reparto de mano de obra (manuales), horarios y bloqueos, plantillas de mensajes y la **clave de consulta de patentes** (requiere `sql/actualizacion-v41-clave-patentes.sql`) |
| `pages/agenda.html` | Agenda de citas (día/semana). Al confirmar una reserva (desde la **campanita** o la lista) se dimensionan las **horas del trabajo**: ocupan la agenda (también para el link público) y avisa si se junta con otra cita; se puede **sobreagendar** o marcar «permitir otros vehículos al mismo tiempo» (requiere `sql/actualizacion-v48-confirmar-reserva-duracion.sql`). Al crear una cita, el **RUT** (se formatea solo con puntos y guion) reconoce al cliente y muestra sus datos y vehículos para elegir el que corresponde; si no existe, pide nombre, RUT y teléfono (+56 automático) y, con la **patente**, trae marca/modelo/año del registro público (boostr.cl, con la clave de Configuración) y crea cliente y vehículo junto con la cita |
| `portal.html` | **Público**: el cliente consulta el estado de su vehículo con patente + N° de OT (incluye fotos y detalle) |
| `cotizacion.html` | **Público**: el cliente revisa y aprueba/rechaza la cotización desde el link que le envías por WhatsApp |
| `inspeccion.html` | **Público**: informe completo de inspección precompra desde el link único |
| `inspeccion-ingreso.html` | **Público**: el cliente revisa el checklist de recepción de su OT y lo firma a distancia desde el link que le envías por WhatsApp |
| `diagnostico.html` | **Público**: el cliente ve el informe de su diagnóstico (pruebas y monitoreos con resultados y fotos, conclusión, valor del diagnóstico, trabajos recomendados y totales) desde el link que le envías por WhatsApp o correo; puede **aceptar o rechazar los trabajos recomendados** (si rechaza, solo se cobra el diagnóstico); según el estado le ofrece aprobar la cotización, agendar cita o seguir el avance de su OT (requiere `sql/actualizacion-v33-link-diagnostico.sql` y `v37-diagnostico-respuesta`) |
| `reservar.html` | **Público**: el cliente reserva su hora (servicio con buscador u «Otro», día y hora de toda la semana). Escribe su **RUT** (con puntos y guion automáticos): si ya es cliente se le saluda por su primer nombre y elige cuál de sus vehículos trae; si no, deja nombre, teléfono (+56 automático) y datos del vehículo. La cita queda asociada al cliente y vehículo correctos. No pide mecánico (es un dato interno). Al cliente conocido no se le vuelve a pedir el teléfono: ve el registrado censurado (•••• 5678) y elige usarlo o indicar otro; las patentes se muestran censuradas (AB••34). Requiere `sql/actualizacion-v35-reserva-otro.sql`, `v44-reserva-reconoce-cliente` y `v45-reserva-usa-telefono-registrado` (sin v44/v45 funciona como antes) |

> Si tu base ya existía antes de la v2, ejecuta también `sql/actualizacion-v2.sql`
> (crea inspecciones, migra las antiguas y agrega los porcentajes de reparto).

Extras integrados:
- **Campanita de novedades** (arriba a la derecha, en todas las pantallas): avisa reservas
  online, cotizaciones y diagnósticos que el cliente aprueba/rechaza, e inspecciones firmadas.
  Contador de sin leer, lista, y aviso del navegador opcional (requiere `sql/actualizacion-v38-notificaciones.sql`).
- **WhatsApp**: botones en cotizaciones y OTs que abren el chat del cliente con
  el mensaje armado (incluye link de aprobación / link de seguimiento).
- **Fotos por OT**: se suben desde el detalle de la orden al bucket `fotos-ot`
  de Supabase Storage (el schema lo crea automáticamente).
- **Historial por vehículo**: botón "Historial" en la página de vehículos.

> Las páginas públicas no exponen tu base de datos: usan funciones SQL
> (`security definer`) que solo devuelven una orden si se conoce patente +
> número, o una cotización si se conoce su link único.


> **Antes de publicar**: pega `tools/verificar-paginas.js` en la consola del navegador con el sitio abierto; debe devolver
> `sintaxis` y `choques` vacíos (detecta errores de sintaxis y nombres repetidos entre una página y `layout.js`).

> **Horas**: toda casilla de horas acepta decimales (0,5 · 0,33 · 1,25) y trae al lado «o minutos»: se escribe `30` y queda `0,5 h`
> (20 min = 0,33 h; 45 min = 0,75 h). Se detectan por id (`…horas…`) o `data-horas` en `assets/js/layout.js`.

> **Descuentos**: se eligen en % o en pesos y corren **solo sobre la mano de obra** (nunca sobre repuestos,
> insumos ni trabajos externos); la línea de descuento lo indica así en cotizaciones, OT, diagnósticos,
> informes impresos y links del cliente. Los documentos que ya tenían un descuento antes de
> `sql/actualizacion-v43-descuento-mano-obra.sql` conservan su cálculo anterior (sobre el total) hasta que
> se les modifique el descuento. El cálculo vive en `descuentoDeItems()` de `assets/js/layout.js`.

> **Formato único de RUT y teléfono**: todas las casillas de RUT (`12.345.678-9`) y de teléfono
> (`+56 9 1234 5678`) se formatean solas al escribir, en toda la app, desde `assets/js/layout.js`
> (se detectan por el `id` de la casilla o `type="tel"`; para excluir una, `data-formato="ninguno"`).
> Los datos ya guardados se unifican con `sql/actualizacion-v42-unificar-rut-telefono.sql`
> (deja respaldo de lo que cambia).

> **Datos del vehículo por patente** (boostr.cl, plan gratuito): marca, modelo, año, tipo de vehículo,
> N° de motor, combustible y kilometraje de la última revisión técnica. Color, chasis/VIN, cilindrada y
> transmisión solo llegan en planes de pago; si la respuesta trae campos nuevos que no conocemos, se
> guardan en *Notas* del vehículo. En la reserva pública el cliente puede indicar kilometraje, cilindrada y
> combustible (opcionales). Requiere `sql/actualizacion-v51-datos-del-vehiculo.sql` (sin v51 esos datos van a
> *Notas* y la reserva funciona igual).

> **Cliente y vehículo al confirmar**: una reserva web de alguien que aún no es cliente NO crea su ficha:
> los datos (nombre, RUT, teléfono, patente y datos del vehículo) viajan en la cita (`citas.datos_vehiculo`).
> Al **confirmar** desde la Agenda o la campanita se registra el cliente y el vehículo (o se reutiliza la
> ficha si ya existe por RUT, dueño del vehículo o teléfono); si la reserva se rechaza o cancela no queda nada.
> Mientras está pendiente aparece con la etiqueta «nuevo». Requiere `sql/actualizacion-v52-cliente-al-confirmar.sql`
> (sin v52 las fichas se crean al reservar, como antes, con la etiqueta «Por revisar»).

> **Reserva pública sin precios y con datos obligatorios**: `reservar.html` ya no muestra el catálogo con valores:
> el buscador lista solo nombres y el **valor del servicio se informa recién al terminar la reserva**
> (pantalla de confirmación). Para que tampoco se pueda leer llamando a la función pública, `sql/actualizacion-v53-precios-solo-tras-reservar.sql`
> hace que `reservar_info()` entregue solo id y nombre, y que `reservar_cita_v4` devuelva el valor del servicio reservado.
> Los datos del vehículo (patente, marca, modelo, año, kilometraje, cilindrada y combustible) son obligatorios; una leyenda indica
> escribir primero la patente y esperar a que se reconozca.

## Puesta en marcha (15 minutos)

### 1. Crear el proyecto en Supabase
1. Crea una cuenta gratis en [supabase.com](https://supabase.com) y un proyecto nuevo.
2. En **SQL Editor**, pega y ejecuta el contenido completo de `sql/schema.sql`.
   Esto crea todas las tablas **y deja precargados**: configuración del taller,
   3 mecánicos, 22 trabajos típicos, 16 repuestos con stock, 5 clientes con
   6 vehículos, una cotización y una OT de ejemplo.
3. En **Authentication → Users → Add user**, crea tu usuario (email + contraseña).

### 2. Conectar la app
En `assets/js/supabaseClient.js` reemplaza:
- `SUPABASE_URL` → Project Settings → API → Project URL
- `SUPABASE_ANON_KEY` → Project Settings → API → anon public key

### 3. Personalizar tu taller
En Supabase, edita la fila de la tabla `taller_config`: nombre, RUT, dirección,
teléfono y sobre todo el **valor hora** de tu taller (usado para calcular el
precio de los trabajos sin precio fijo) y el % de IVA.

### 4. Publicar en Netlify
1. Cuenta gratis en [netlify.com](https://netlify.com).
2. Arrastra esta carpeta completa a **Sites → Add new site → Deploy manually**
   (o conecta un repositorio de GitHub para deploy automático).
3. Listo: la app queda en `https://tu-sitio.netlify.app`.

> La `anon key` de Supabase es pública por diseño; la seguridad real la dan
> las políticas RLS de la base de datos (solo usuarios autenticados pueden
> leer/escribir).

## Probar localmente

Por usar rutas absolutas en la autenticación, sírvelo con un servidor local:

```
cd "carpeta-del-proyecto"
python -m http.server 8000
# o: npx serve .
```

y abre http://localhost:8000
