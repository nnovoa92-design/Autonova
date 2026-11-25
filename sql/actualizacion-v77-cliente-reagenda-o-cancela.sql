-- ============================================================
-- v77 — El cliente reagenda o cancela su hora desde el correo
--
--  * Cada cita tiene un link privado (mi-cita.html?t=...) que va en el correo de confirmación,
--    en el de reagendamiento y en el recordatorio del día anterior.
--  * En ese link se le propone primero REAGENDAR (botón grande) y, en pequeño, cancelar.
--  * Al reagendar vuelve a la página de reserva con sus datos y su vehículo ya guardados: solo elige
--    el servicio (si cambió), dónde lo atendemos (taller / domicilio) y el nuevo día y hora.
--    La cita es la misma (mismo número, cliente, vehículo y código): cambia de fecha y queda
--    «pendiente» para que tú la confirmes (y le llegue la confirmación con la nueva hora).
--  * Todo queda en el historial de la cita (🔁 reagendada / cancelada por el cliente) y te llega
--    un aviso a la campanita 🔔.
--
-- Seguro de correr más de una vez.
-- ============================================================

-- 1) Link privado por cita (32 caracteres al azar; también para las citas que ya existen)
alter table citas add column if not exists token_cliente text default replace(gen_random_uuid()::text, '-', '');
update citas set token_cliente = replace(gen_random_uuid()::text, '-', '') where token_cliente is null;
create unique index if not exists idx_citas_token_cliente on citas (token_cliente);

-- 2) Lo que ve el cliente en su link (sin RUT, teléfono ni correo completos)
create or replace function cita_cliente_info(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c citas%rowtype; v_cli clientes%rowtype; v_veh vehiculos%rowtype; v_cfg taller_config%rowtype;
  v_email text; v_mod text; v_otro text;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'error', 'El link no es válido.');
  end if;
  select * into c from citas where token_cliente = p_token;
  if not found then return jsonb_build_object('ok', false, 'error', 'No encontramos esta reserva. Puede que el taller la haya eliminado.'); end if;
  select * into v_cfg from taller_config where id = 1;
  if c.cliente_id is not null then select * into v_cli from clientes where id = c.cliente_id; end if;
  if c.vehiculo_id is not null then select * into v_veh from vehiculos where id = c.vehiculo_id; end if;
  v_email := coalesce(nullif(btrim(c.email_contacto), ''), nullif(btrim(v_cli.email), ''));
  v_mod := coalesce(c.modalidad, 'taller');
  if c.trabajo_id is null and c.descripcion like 'Otro: %' then v_otro := substr(c.descripcion, 8); end if;
  return jsonb_build_object(
    'ok', true,
    'numero', c.numero,
    'estado', c.estado,
    'puede_modificar', c.estado in ('pendiente', 'confirmado') and c.fecha_hora > now(),
    'fecha', to_char(c.fecha_hora at time zone 'America/Santiago', 'YYYY-MM-DD'),
    'hora', to_char(c.fecha_hora at time zone 'America/Santiago', 'HH24:MI'),
    'servicio', coalesce((select nombre from trabajos where id = c.trabajo_id), c.descripcion),
    'trabajo_id', c.trabajo_id,
    'servicio_otro', v_otro,
    'modalidad', v_mod,
    'direccion', c.direccion,
    'nombre', split_part(btrim(coalesce(nullif(v_cli.nombre, ''), c.nombre_contacto, 'cliente')), ' ', 1),
    'patente', coalesce(v_veh.patente, c.patente_contacto),
    'vehiculo', nullif(btrim(concat_ws(' ', coalesce(v_veh.marca, c.datos_vehiculo ->> 'marca'), coalesce(v_veh.modelo, c.datos_vehiculo ->> 'modelo'))), ''),
    'correo', case when v_email is null then null
                   else left(v_email, 1) || '•••@' || split_part(v_email, '@', 2) end,
    'codigo', case when c.codigo_nota is null then c.codigo_descuento else null end,
    'taller', jsonb_build_object('nombre', v_cfg.nombre, 'telefono', v_cfg.telefono, 'direccion', v_cfg.direccion)
  );
end $$;
grant execute on function cita_cliente_info(text) to anon, authenticated;

-- 3) Reagendar desde el link: misma cita, nuevo día y hora (y servicio / atención si cambiaron)
create or replace function cita_cliente_reagendar(
  p_token text, p_fecha date, p_hora text, p_trabajo_id uuid, p_servicio_otro text,
  p_modalidad text, p_domicilio_tipo text, p_direccion text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c citas%rowtype;
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_fh timestamptz;
  v_otro text := nullif(left(btrim(coalesce(p_servicio_otro, '')), 500), '');
  v_mod text := case when lower(coalesce(p_modalidad, '')) in ('domicilio', 'terreno', 'retiro') then 'terreno' else 'taller' end;
  v_dir text := nullif(left(btrim(coalesce(limpiar_marcado(p_direccion), '')), 200), '');
  v_margen int := 0; v_ret uuid; v_dom jsonb := null;
  v_trab_nombre text; v_precio_fijo numeric; v_precio_desde numeric; v_desc text;
  v_ip text := reservar_ip(); v_n int;
begin
  if p_token is null or length(p_token) < 20 then return jsonb_build_object('ok', false, 'error', 'El link no es válido.'); end if;
  select * into c from citas where token_cliente = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'No encontramos esta reserva.'); end if;
  if c.estado not in ('pendiente', 'confirmado') or c.fecha_hora <= now() then
    return jsonb_build_object('ok', false, 'error', 'Esta hora ya no se puede cambiar desde aquí. Escríbenos o llámanos y te ayudamos.');
  end if;

  -- Límite por conexión: 6 cambios por hora
  select count(*) into v_n from reservar_limites where ip = v_ip and tipo = 'reagendar' and creado_en > now() - interval '1 hour';
  if v_n >= 6 then return jsonb_build_object('ok', false, 'error', 'Hiciste varios cambios seguidos. Espera un momento o llama al taller.'); end if;

  if p_trabajo_id is null and v_otro is null then return jsonb_build_object('ok', false, 'error', 'Cuéntanos qué servicio necesitas.'); end if;
  if p_fecha is null or p_hora is null or p_hora !~ '^[0-2][0-9]:[0-5][0-9]$' then return jsonb_build_object('ok', false, 'error', 'Día u hora inválidos.'); end if;
  if p_fecha < v_hoy or p_fecha > v_hoy + 90 then return jsonb_build_object('ok', false, 'error', 'Ese día no está disponible para reservar.'); end if;
  if v_mod = 'terreno' then
    if v_dir is null or length(v_dir) < 5 then return jsonb_build_object('ok', false, 'error', 'Indica la dirección donde atenderemos tu vehículo.'); end if;
    v_margen := greatest(coalesce((select domicilio_margen_min from taller_config where id = 1), 60), 0);
    if lower(coalesce(p_domicilio_tipo, '')) = 'retiro' or lower(coalesce(p_modalidad, '')) = 'retiro' then
      select trabajo_retiro_id into v_ret from taller_config where id = 1;
      if v_ret is not null then v_mod := 'retiro'; v_dom := _valor_trabajo(v_ret); end if;
    end if;
    if v_dom is null then v_dom := domicilio_valor(); end if;
  end if;

  if p_trabajo_id is not null then
    select nombre, precio_fijo, nullif(btrim(coalesce(descripcion, '')), ''),
           (select min((o ->> 'precio')::numeric) from jsonb_array_elements(coalesce(opciones, '[]'::jsonb)) o where (o ->> 'precio') is not null)
      into v_trab_nombre, v_precio_fijo, v_desc, v_precio_desde
      from trabajos where id = p_trabajo_id and activo;
  end if;
  if v_trab_nombre is null and v_otro is null then
    return jsonb_build_object('ok', false, 'error', 'Ese servicio ya no está disponible. Elige otro o cuéntanos qué necesitas en «Otro».');
  end if;

  v_fh := ((p_fecha::text || ' ' || p_hora)::timestamp) at time zone 'America/Santiago';
  if v_fh = c.fecha_hora and v_mod = coalesce(c.modalidad, 'taller') and coalesce(v_dir, '') = coalesce(c.direccion, '')
     and p_trabajo_id is not distinct from c.trabajo_id and (v_trab_nombre is not null or ('Otro: ' || v_otro) = c.descripcion) then
    return jsonb_build_object('ok', false, 'error', 'No cambiaste nada: elige otro día u hora.');
  end if;

  -- Su propia hora no cuenta como ocupada mientras se revisa la nueva
  update citas set estado = 'cancelado' where id = c.id;
  if not (p_hora = any (agenda_slots_libres(p_fecha, v_margen))) then
    update citas set estado = c.estado where id = c.id;
    return jsonb_build_object('ok', false, 'error', 'Ese horario ya no está disponible (tomado o cerrado). Elige otro.');
  end if;

  insert into reservar_limites (ip, tipo) values (v_ip, 'reagendar');
  update citas set
    fecha_hora = v_fh,
    estado = 'pendiente',                       -- el taller la vuelve a confirmar (y le llega la confirmación)
    origen = 'online',                          -- así aparece en «Reservas online por confirmar» de la Agenda
    trabajo_id = case when v_trab_nombre is not null then p_trabajo_id else null end,
    descripcion = coalesce(v_trab_nombre, 'Otro: ' || v_otro),
    duracion_min = case when p_trabajo_id is not distinct from c.trabajo_id then c.duracion_min
                        else coalesce((select slot_min from taller_config where id = 1), 60) end,
    modalidad = v_mod,
    direccion = case when v_mod in ('terreno', 'retiro') then v_dir else null end,
    margen_antes_min = v_margen, margen_despues_min = v_margen,
    reagendamientos = coalesce(c.reagendamientos, '[]'::jsonb) || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'desde', c.fecha_hora, 'hacia', v_fh, 'motivo', 'cliente', 'por', 'cliente',
      'motivo_texto', 'El cliente la cambió desde su correo',
      'servicio_antes', case when p_trabajo_id is distinct from c.trabajo_id or v_trab_nombre is null then c.descripcion end,
      'modalidad_antes', case when v_mod <> coalesce(c.modalidad, 'taller') then coalesce(c.modalidad, 'taller') end,
      'hora_anterior', 'disponible', 'fecha', now())))
  where id = c.id;

  begin
    insert into notificaciones (tipo, titulo, detalle, url, ref_id)
    values ('cita_reagendada_cliente', '🔁 Un cliente reagendó su hora',
            coalesce(nullif(c.nombre_contacto, ''), 'Cliente') || ' · de ' || to_char(c.fecha_hora at time zone 'America/Santiago', 'DD-MM HH24:MI')
              || ' a ' || to_char(v_fh at time zone 'America/Santiago', 'DD-MM HH24:MI') || ' · ' || coalesce(v_trab_nombre, 'Otro: ' || v_otro)
              || ' · queda pendiente de confirmar',
            'agenda.html?fecha=' || p_fecha::text, c.id);
  exception when others then null;   -- un fallo al avisar nunca impide el cambio
  end;

  return jsonb_build_object('ok', true, 'numero', c.numero, 'servicio', v_trab_nombre,
                            'precio_fijo', v_precio_fijo, 'precio_desde', v_precio_desde, 'descripcion', v_desc,
                            'modalidad', v_mod, 'direccion', case when v_mod in ('terreno', 'retiro') then v_dir end,
                            'domicilio', v_dom);
end $$;
grant execute on function cita_cliente_reagendar(text, date, text, uuid, text, text, text, text) to anon, authenticated;

-- 4) Cancelar desde el link (queda en el historial y te avisa)
create or replace function cita_cliente_cancelar(p_token text, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c citas%rowtype; v_mot text := nullif(left(btrim(coalesce(limpiar_marcado(p_motivo), '')), 200), '');
begin
  if p_token is null or length(p_token) < 20 then return jsonb_build_object('ok', false, 'error', 'El link no es válido.'); end if;
  select * into c from citas where token_cliente = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'No encontramos esta reserva.'); end if;
  if c.estado = 'cancelado' then return jsonb_build_object('ok', true, 'ya', true); end if;
  if c.estado not in ('pendiente', 'confirmado') or c.fecha_hora <= now() then
    return jsonb_build_object('ok', false, 'error', 'Esta hora ya no se puede cancelar desde aquí. Escríbenos o llámanos.');
  end if;
  update citas set estado = 'cancelado',
    reagendamientos = coalesce(c.reagendamientos, '[]'::jsonb) || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'tipo', 'cancelacion', 'desde', c.fecha_hora, 'motivo', 'cliente', 'por', 'cliente',
      'motivo_texto', 'La canceló el cliente desde su correo' || coalesce(': ' || v_mot, ''),
      'hora_anterior', 'disponible', 'aviso', '[]'::jsonb, 'fecha', now())))
  where id = c.id;
  begin
    insert into notificaciones (tipo, titulo, detalle, url, ref_id)
    values ('cita_cancelada_cliente', '✖ Un cliente canceló su hora',
            coalesce(nullif(c.nombre_contacto, ''), 'Cliente') || ' · ' || to_char(c.fecha_hora at time zone 'America/Santiago', 'DD-MM HH24:MI')
              || ' · ' || coalesce(c.descripcion, 'Servicio') || coalesce(' · Motivo: ' || v_mot, '') || ' · la hora quedó libre',
            'agenda.html?fecha=' || to_char(c.fecha_hora at time zone 'America/Santiago', 'YYYY-MM-DD'), c.id);
  exception when others then null;
  end;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function cita_cliente_cancelar(text, text) to anon, authenticated;

-- 5) Botón del correo para este link (mismo texto que en la página)
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
              when p_url like '%/mi-cita.html%' then '📅 Cambiar o cancelar mi hora'
              when p_url like '%/reservar.html%' then '📅 Reservar hora'
              when p_url like '%/club.html%' then '🎁 Compartir mi código'
              else 'Abrir enlace' end
      || '</a></td></tr></table>'
$$;

-- Verificación: debe decir «ok»
select case when exists (select 1 from information_schema.columns where table_name = 'citas' and column_name = 'token_cliente')
             and not exists (select 1 from citas where token_cliente is null)
             and to_regprocedure('cita_cliente_info(text)') is not null
             and to_regprocedure('cita_cliente_reagendar(text, date, text, uuid, text, text, text, text)') is not null
             and to_regprocedure('cita_cliente_cancelar(text, text)') is not null
            then 'ok' else 'revisar' end as v77;
