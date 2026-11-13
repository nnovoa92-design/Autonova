-- ============================================================
-- v70 — Club Autonova, fase 2: encuesta de satisfacción y reseñas en Google
--
--  * A los 7 días de entregado un vehículo (OT «Entregado»), el cliente recibe por correo una encuesta de
--    30 segundos: estrellas (1 a 5), del 0 al 10 si nos recomendaría, qué podemos mejorar y un comentario.
--    Sale sola desde las 10:00 (hora de Chile), con el mismo diseño de los demás correos.
--  * Al terminar, a TODOS se les ofrece dejar su reseña en Google (Google prohíbe pedírsela solo a los
--    contentos) y se le recuerda su código del Club.
--  * Nota de 1 a 3 (o 0 a 6 en la recomendación): aviso en rojo en la campanita y en Inicio para llamarlo.
--  * Los clientes sin correo quedan en Inicio para enviarles la encuesta por WhatsApp con un botón.
--  * Días, link de reseñas de Google y encendido/apagado: Configuración → Encuesta y reseñas.
--
-- Requiere v69. Seguro de correr más de una vez.
-- ============================================================

alter table taller_config add column if not exists encuesta jsonb not null default '{}'::jsonb;

create or replace function _encuesta_cfg() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('activa', true, 'dias', 7, 'google_url', '')
         || coalesce((select encuesta from taller_config where id = 1), '{}'::jsonb)
$$;
revoke execute on function _encuesta_cfg() from public, anon, authenticated;

create table if not exists encuestas (
  id uuid primary key default uuid_generate_v4(),          -- también es el link público (imposible de adivinar)
  orden_id uuid unique references ordenes(id) on delete cascade,
  cliente_id uuid references clientes(id) on delete set null,
  vehiculo_id uuid references vehiculos(id) on delete set null,
  enviada_en timestamptz,
  canal text,                                               -- 'correo' | 'whatsapp'
  respondida_en timestamptz,
  nota int check (nota between 1 and 5),
  nps int check (nps between 0 and 10),
  mejoras text[] not null default '{}',
  comentario text,
  google_en timestamptz,                                    -- tocó «Dejar reseña en Google»
  atendida_en timestamptz,                                  -- el taller ya llamó al cliente (alertas)
  creado_en timestamptz not null default now()
);
create index if not exists idx_encuestas_vehiculo on encuestas (vehiculo_id);
create index if not exists idx_encuestas_respondida on encuestas (respondida_en);
alter table encuestas enable row level security;
drop policy if exists "Acceso solo usuarios autorizados" on encuestas;
create policy "Acceso solo usuarios autorizados" on encuestas for all using (es_autorizado()) with check (es_autorizado());

-- ---------- Página pública de la encuesta (encuesta.html?e=<id>) ----------
create or replace function encuesta_info(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; club jsonb := _club_cfg(); enc jsonb := _encuesta_cfg();
begin
  select e.id, e.respondida_en, e.nota, cl.nombre, cl.codigo_referido, v.patente, v.marca, v.modelo, o.numero, o.fecha_entrega,
         t.nombre as taller, t.telefono
    into r
    from encuestas e
    join ordenes o on o.id = e.orden_id
    left join clientes cl on cl.id = e.cliente_id
    left join vehiculos v on v.id = e.vehiculo_id
    cross join (select nombre, telefono from taller_config where id = 1) t
   where e.id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'No encontramos esta encuesta. Revisa el link que te enviamos.');
  end if;
  return jsonb_build_object(
    'ok', true,
    'respondida', r.respondida_en is not null,
    'nota', r.nota,
    'nombre', initcap(split_part(btrim(coalesce(r.nombre, '')), ' ', 1)),
    'vehiculo', nullif(btrim(concat_ws(' ', r.marca, r.modelo, r.patente)), ''),
    'ot', _num_doc('OT', r.numero),
    'fecha_entrega', (r.fecha_entrega at time zone 'America/Santiago')::date,
    'google_url', nullif(btrim(coalesce(enc ->> 'google_url', '')), ''),
    'codigo', case when coalesce((club ->> 'activo')::boolean, true) then r.codigo_referido else null end,
    'pct', (club ->> 'pct')::numeric, 'tope', (club ->> 'tope')::numeric,
    'taller', jsonb_build_object('nombre', r.taller, 'telefono', r.telefono, 'instagram', club ->> 'instagram'));
end $$;
grant execute on function encuesta_info(uuid) to anon, authenticated;

create or replace function encuesta_responder(p_id uuid, p_nota int, p_nps int, p_mejoras text[], p_comentario text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_permitidas text[] := array['tiempo', 'comunicacion', 'precio', 'calidad', 'explicacion', 'limpieza', 'atencion', 'agenda', 'nada'];
  v_mejoras text[];
  v_com text := nullif(left(btrim(coalesce(limpiar_marcado(p_comentario), '')), 1000), '');
  r record;
  v_alerta boolean;
begin
  if p_nota is null or p_nota not between 1 and 5 then
    return jsonb_build_object('ok', false, 'error', 'Elige de 1 a 5 estrellas.');
  end if;
  if p_nps is not null and p_nps not between 0 and 10 then
    return jsonb_build_object('ok', false, 'error', 'La recomendación va de 0 a 10.');
  end if;
  select coalesce(array_agg(distinct m), '{}') into v_mejoras from unnest(coalesce(p_mejoras, '{}')) m where m = any(v_permitidas);

  update encuestas set respondida_en = now(), nota = p_nota, nps = p_nps, mejoras = v_mejoras, comentario = v_com
   where id = p_id and respondida_en is null;
  if not found then
    if exists (select 1 from encuestas where id = p_id) then
      return jsonb_build_object('ok', false, 'error', 'Esta encuesta ya fue respondida. ¡Gracias!', 'ya_respondida', true);
    end if;
    return jsonb_build_object('ok', false, 'error', 'No encontramos esta encuesta.');
  end if;

  select cl.nombre, v.patente, o.numero into r
    from encuestas e join ordenes o on o.id = e.orden_id
    left join clientes cl on cl.id = e.cliente_id left join vehiculos v on v.id = e.vehiculo_id
   where e.id = p_id;
  v_alerta := p_nota <= 3 or (p_nps is not null and p_nps <= 6);
  insert into notificaciones (tipo, titulo, detalle, url)
  values (case when v_alerta then 'encuesta_alerta' else 'encuesta' end,
          case when v_alerta then '🔴 ' else '⭐ ' end || coalesce(r.nombre, 'Un cliente') || ' calificó ' || p_nota || '/5'
            || case when p_nps is not null then ' · recomienda ' || p_nps || '/10' else '' end
            || case when v_alerta then ': llámalo' else '' end,
          concat_ws(' · ', _num_doc('OT', r.numero), r.patente,
                    case when array_length(v_mejoras, 1) > 0 then 'mejorar: ' || array_to_string(v_mejoras, ', ') end,
                    left(v_com, 140)),
          'referidos.html#encuestas');
  return jsonb_build_object('ok', true, 'alerta', v_alerta);
end $$;
grant execute on function encuesta_responder(uuid, int, int, text[], text) to anon, authenticated;

-- Para medir cuántos fueron a Google
create or replace function encuesta_google(p_id uuid) returns jsonb
language sql security definer set search_path = public as $$
  update encuestas set google_en = coalesce(google_en, now()) where id = p_id returning jsonb_build_object('ok', true)
$$;
grant execute on function encuesta_google(uuid) to anon, authenticated;

-- ---------- Botón del correo: «Responder la encuesta» (mismo cambio en layout.js → BOTONES_CORREO) ----------
create or replace function _boton_correo(p_url text) returns text language sql immutable as $$
  select '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:4px 0 20px;"><tr><td style="border-radius:10px;background:#d4a84b;">'
      || '<a href="' || _esc_html(p_url) || '" target="_blank" style="display:inline-block;padding:13px 24px;font-family:Arial,Helvetica,sans-serif;font-size:15px;font-weight:bold;color:#15181e;text-decoration:none;border-radius:10px;">'
      || case when p_url like '%#condiciones%' then '📋 Ver condiciones completas'
              when p_url like '%/encuesta.html%' then '⭐ Responder la encuesta (30 segundos)'
              when p_url like '%/inspeccion-ingreso.html%' then '✍️ Revisar y firmar la inspección'
              when p_url like '%/inspeccion.html%' then '📋 Ver el informe de inspección'
              when p_url like '%/cotizacion.html%' then '📄 Ver y aprobar la cotización'
              when p_url like '%/diagnostico.html%' then '🔎 Ver el informe de diagnóstico'
              when p_url like '%/portal.html%' then '🚗 Seguir mi vehículo'
              when p_url like '%/reservar.html%' then '📅 Reservar hora'
              when p_url like '%/club.html%' then '🎁 Compartir mi código'
              else 'Abrir enlace' end
      || '</a></td></tr></table>'
$$;

-- ---------- Envío automático: a los X días de entregado (cada hora; correos desde las 10:00) ----------
create or replace function enviar_encuestas() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  cfg taller_config%rowtype;
  enc jsonb := _encuesta_cfg();
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_hora int := extract(hour from (now() at time zone 'America/Santiago'))::int;
  v_dias int := greatest(coalesce((enc ->> 'dias')::int, 7), 1);
  v_url text; v_plant jsonb; v_firma text; v_contacto text;
  r record; v_vals jsonb; v_asunto text; v_texto text; v_res jsonb;
  v_nuevas int := 0; v_env int := 0;
begin
  if coalesce((enc ->> 'activa')::boolean, true) is false then return jsonb_build_object('estado', 'apagada'); end if;

  -- OT entregadas hace X días (con 3 días de margen por si el reloj no corrió algún día): queda su encuesta
  insert into encuestas (orden_id, cliente_id, vehiculo_id)
  select o.id, o.cliente_id, o.vehiculo_id
    from ordenes o
   where o.estado = 'entregado' and o.fecha_entrega is not null
     and (o.fecha_entrega at time zone 'America/Santiago')::date between v_hoy - v_dias - 3 and v_hoy - v_dias
     and not exists (select 1 from encuestas e where e.orden_id = o.id)
  on conflict (orden_id) do nothing;
  get diagnostics v_nuevas = row_count;

  select * into cfg from taller_config where id = 1;
  if v_hora < 10 or coalesce(btrim(cfg.correo_script_url), '') = '' or coalesce(btrim(cfg.correo_script_clave), '') = ''
     or coalesce(cfg.correo_eventos ->> 'encuesta', '') = 'false' then
    return jsonb_build_object('estado', 'sin_correos_ahora', 'nuevas', v_nuevas);
  end if;
  v_url := rtrim(coalesce(nullif(btrim(cfg.app_url), ''), 'https://autonova.nnovoa92.workers.dev'), '/');
  v_plant := coalesce(cfg.correo_plantillas, '{}'::jsonb);
  v_contacto := concat_ws(' · ', nullif(btrim(cfg.direccion), ''), nullif(btrim(cfg.telefono), ''));
  v_firma := E'Saludos,\n' || coalesce(nullif(btrim(cfg.nombre), ''), 'El taller') || case when v_contacto <> '' then E'\n' || v_contacto else '' end;

  for r in
    select e.id, e.cliente_id, e.vehiculo_id, cl.nombre, cl.email, v.patente, v.marca, v.modelo, o.numero
      from encuestas e
      join ordenes o on o.id = e.orden_id
      join clientes cl on cl.id = e.cliente_id
      left join vehiculos v on v.id = e.vehiculo_id
     where e.enviada_en is null and e.respondida_en is null and e.creado_en > now() - interval '5 days'
       and coalesce(cl.email, '') ~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$'
  loop
    v_vals := jsonb_build_object(
      'nombre', r.nombre,
      'vehiculo', case when r.patente is not null
                       then 'su vehículo ' || r.patente || coalesce(' (' || nullif(concat_ws(' ', r.marca, r.modelo), '') || ')', '')
                       else 'su vehículo' end,
      'ot', _num_doc('OT', r.numero),
      'link_encuesta', v_url || '/encuesta.html?e=' || r.id,
      'taller', coalesce(cfg.nombre, 'el taller'),
      'firma', v_firma);
    -- Mismo texto por defecto que layout.js (PLANTILLAS_CORREO.encuesta_7dias): si se cambia uno, cambiar el otro
    v_asunto := _rellenar(_plantilla(v_plant, 'encuesta_7dias', 'asunto',
      '⭐ ¿Cómo le fue con nosotros? — {ot} · {taller}'), v_vals);
    v_texto := _rellenar(_plantilla(v_plant, 'encuesta_7dias', 'texto',
      E'Hola {nombre},\n\nHace unos días le entregamos {vehiculo} ({ot}). ¿Cómo le ha funcionado?\n\nSu opinión nos ayuda a mejorar y nos toma solo 30 segundos:\n{link_encuesta}\n\nSi algo no quedó como esperaba, cuéntenos en la encuesta: lo revisamos personalmente.\n\n{firma}'), v_vals);
    v_res := _enviar_correo_script(cfg.correo_script_url, cfg.correo_script_clave, cfg.nombre, r.email, v_asunto, v_texto);
    if to_regclass('public.correos_enviados') is not null then
      insert into correos_enviados (para, asunto, texto, evento, estado, error, ref_tabla, ref_id, cliente_id, vehiculo_id)
      values (r.email, v_asunto, v_texto, 'encuesta', coalesce(v_res ->> 'estado', 'incierto'), v_res ->> 'error',
              'encuestas', r.id, r.cliente_id, r.vehiculo_id);
    end if;
    -- Queda marcada aunque haya fallado (no se repite); si falló, el aviso queda en la campanita
    update encuestas set enviada_en = now(), canal = 'correo' where id = r.id;
    if coalesce(v_res ->> 'estado', '') <> 'enviado' then
      insert into notificaciones (tipo, titulo, detalle, url)
      values ('correo_error', '⚠ No se confirmó la encuesta a ' || r.email, coalesce(v_res ->> 'error', ''), 'dashboard.html');
    end if;
    v_env := v_env + 1;
  end loop;
  return jsonb_build_object('estado', 'ok', 'nuevas', v_nuevas, 'enviadas', v_env);
end $$;
revoke execute on function enviar_encuestas() from public, anon, authenticated;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'autonova-encuestas';
  perform cron.schedule('autonova-encuestas', '45 * * * *', 'select public.enviar_encuestas()');
exception when others then
  raise notice 'No se pudo programar el envío de encuestas: %', sqlerrm;
end $$;

-- Verificación: tabla y tarea programada (1)
select (select count(*) from cron.job where jobname = 'autonova-encuestas') as tarea_encuestas,
       to_regclass('public.encuestas') is not null as tabla_encuestas;
