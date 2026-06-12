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
| `pages/cotizaciones.html` | Crear/editar cotizaciones eligiendo **trabajos precargados** o repuestos, descuento, IVA, impresión y conversión a OT |
| `pages/ordenes.html` | Órdenes de trabajo con estados (recepción → diagnóstico → en proceso → listo → entregado), ítems, **registro de horas por mecánico** y descuento automático de stock |
| `pages/clientes.html` | Clientes con sus vehículos |
| `pages/vehiculos.html` | Vehículos (patente, marca, modelo, km, VIN) |
| `pages/trabajos.html` | Catálogo de trabajos con horas estimadas; precio = horas × valor hora del taller (o precio fijo) |
| `pages/inventario.html` | Repuestos con stock, mínimos, entradas/salidas/ajustes |
| `pages/pagos.html` | Pagos por OT con saldo pendiente |
| `portal.html` | **Público**: el cliente consulta el estado de su vehículo con patente + N° de OT (incluye fotos y detalle) |
| `cotizacion.html` | **Público**: el cliente revisa y aprueba/rechaza la cotización desde el link que le envías por WhatsApp |

Extras integrados:
- **WhatsApp**: botones en cotizaciones y OTs que abren el chat del cliente con
  el mensaje armado (incluye link de aprobación / link de seguimiento).
- **Fotos por OT**: se suben desde el detalle de la orden al bucket `fotos-ot`
  de Supabase Storage (el schema lo crea automáticamente).
- **Historial por vehículo**: botón "Historial" en la página de vehículos.

> Las páginas públicas no exponen tu base de datos: usan funciones SQL
> (`security definer`) que solo devuelven una orden si se conoce patente +
> número, o una cotización si se conoce su link único.

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
