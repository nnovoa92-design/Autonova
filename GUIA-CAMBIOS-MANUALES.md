# Guía: cómo hacer cambios manuales en Autonova

Esta app está hecha con tecnología estándar (HTML + JavaScript + Supabase +
GitHub + Cloudflare). Cualquier desarrollador web puede mantenerla, y muchas
cosas las puedes cambiar tú mismo sin tocar código. Aquí está el mapa.

---

## 1. Cambios SIN tocar código (desde la app)

Entras a la app con tu usuario y editas directamente:

| Qué | Dónde |
|---|---|
| Nombre del taller, RUT, dirección, teléfono | **Configuración** |
| Valor hora, % de IVA | **Configuración** |
| Porcentajes de reparto (mecánico/dueño/taller) | **Configuración** |
| Clientes (datos, correo, teléfono) | **Clientes** |
| Vehículos | **Vehículos** |
| Catálogo de trabajos, horas y precios | **Catálogo de trabajos** |
| Repuestos, stock y precios | **Inventario** |

> Consejo: para dar de baja un cliente/vehículo/repuesto usa **"Desactivar"**,
> NO lo borres. Borrar arrastra todo su historial.

---

## 2. Cambios en la BASE DE DATOS (Supabase)

Para cambios estructurales (agregar campos, tablas, etc.):

1. Entra a [supabase.com](https://supabase.com) → tu proyecto.
2. **SQL Editor** → **New query** → pegas el SQL → **Run**.
3. Los scripts viven en la carpeta `sql/` del proyecto (schema.sql,
   actualizacion-v3/v4/v5.sql). Son el historial de cambios de la base.

También puedes ver y editar datos a mano en **Table Editor**, y exportar
respaldos con **Export CSV** (recomendado cada cierto tiempo).

---

## 3. Cambios en el CÓDIGO (GitHub)

Todo el código está en: https://github.com/nnovoa92-design/Autonova

Para editar un archivo sin instalar nada:

1. Abre el archivo en GitHub.
2. Haz clic en el ícono del **lápiz** (Edit).
3. Cambias lo que necesites.
4. Abajo, **"Commit changes"**.
5. **Cloudflare publica el cambio solo** en 1–2 minutos.

Archivos útiles:
- `pages/*.html` → cada pantalla de la app.
- `assets/css/style.css` → colores y estilos.
- `assets/js/layout.js` → menú, helpers, calendario de revisión técnica.
- `assets/js/supabaseClient.js` → conexión a la base (URL + clave pública).

---

## 4. El robot de correo automático

- Textos de los mensajes: `tools/enviar-recordatorios.mjs`.
- Hora a la que corre: `.github/workflows/recordatorios.yml` (línea `cron`).
- Probarlo manualmente: GitHub → pestaña **Actions** → "Recordatorios
  automáticos por correo" → **Run workflow**.

> ⚠️ GitHub apaga las tareas programadas si el repositorio pasa **60 días sin
> actividad**. Te avisa por correo; entras a Actions y le das "re-enable".

---

## 5. Claves y secretos

- **Clave pública de Supabase** (`anon`/publishable): está en el código, es
  pública por diseño. La seguridad la dan las políticas RLS de la base.
- **Clave de servicio (`service_role`)** y **clave de Gmail**: viven SOLO como
  *Secrets* en GitHub (Settings → Secrets and variables → Actions). Nunca van
  en el código.

---

## 6. Si algo se rompe

- La app no carga / error raro → revisa la consola del navegador (F12).
- El robot de correo falla → GitHub te marca la ejecución en rojo y te avisa.
- Olvidaste la contraseña → Supabase → Authentication → tu usuario → reset.
- Quieres volver a una versión anterior del código → GitHub guarda todo el
  historial (cada "commit"); se puede revertir.
