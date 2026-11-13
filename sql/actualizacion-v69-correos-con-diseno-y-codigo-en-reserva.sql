-- ============================================================
-- v69 — Correos automáticos con diseño + código del Club validado al reservar
--
--  * Los correos que manda Supabase solo (recordatorios de cotización, cobranza y premios del Club) salen con
--    el mismo diseño que los de la app: logo, colores, botones, «Síguenos en Instagram» y el botón de reserva.
--    Necesita el script de Gmail versión 2 (Configuración → Correo automático → «Correos con diseño»).
--  * Reserva en línea: el código se valida al instante con los datos de la persona (RUT, teléfono, patente):
--    si ya se atendió antes, si es su propio código, si ya usó uno o si el cupón es de otra persona.
--  * En la agenda queda anotado si el código de una reserva no aplica, y por qué.
--  * En la OT, «cliente nuevo» se revisa también por RUT, teléfono y patente (aunque tenga otra ficha).
--
-- Requiere v68. Seguro de correr más de una vez.
-- ============================================================

alter table citas add column if not exists codigo_nota text;

-- ---------- ¿Aplica el código para esta persona? ----------
create or replace function _club_motivo(p_tipo text, p_dueno uuid, p_rut text, p_telefono text, p_patente text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_rut text := upper(regexp_replace(coalesce(p_rut, ''), '[^0-9kK]', '', 'g'));
  v_tel text := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  v_pat text := upper(regexp_replace(coalesce(p_patente, ''), '[^A-Za-z0-9]', '', 'g'));
  v_personas uuid[]; v_vehs uuid[]; v_duenos_veh uuid[];
begin
  if length(v_rut) < 7 then v_rut := ''; end if;
  v_tel := case when length(v_tel) >= 8 then right(v_tel, 8) else '' end;
  if length(v_pat) < 5 then v_pat := ''; end if;
  if v_rut = '' and v_tel = '' and v_pat = '' then
    return jsonb_build_object('aplica', null, 'motivo', 'faltan_datos');
  end if;
  select coalesce(array_agg(id), '{}') into v_personas from clientes
   where (v_rut <> '' and upper(regexp_replace(coalesce(rut, ''), '[^0-9kK]', '', 'g')) = v_rut)
      or (v_tel <> '' and right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 8) = v_tel);
  select coalesce(array_agg(id), '{}'), coalesce(array_agg(cliente_id), '{}') into v_vehs, v_duenos_veh from vehiculos
   where v_pat <> '' and upper(regexp_replace(coalesce(patente, ''), '[^A-Za-z0-9]', '', 'g')) = v_pat;

  if p_tipo = 'premio' then
    if p_dueno = any(v_personas) or p_dueno = any(v_duenos_veh) then
      return jsonb_build_object('aplica', true);
    end if;
    if v_rut <> '' or v_tel <> '' then
      return jsonb_build_object('aplica', false, 'motivo', 'cupon_ajeno',
        'mensaje', 'Este cupón es personal y no corresponde a tus datos: solo lo puede usar la persona que lo ganó.',
        'nota', 'No aplica: el cupón es de otro cliente.');
    end if;
    return jsonb_build_object('aplica', null, 'motivo', 'faltan_datos');
  end if;

  -- Código de un cliente (recomendación)
  if p_dueno = any(v_personas) or p_dueno = any(v_duenos_veh) then
    return jsonb_build_object('aplica', false, 'motivo', 'propio',
      'mensaje', 'Es tu propio código: no aplica para ti. Compártelo con tus amigos y gana cupones.',
      'nota', 'No aplica: es el código del mismo cliente.');
  end if;
  if exists (select 1 from ordenes o where o.estado <> 'cancelado'
                and (o.cliente_id = any(v_personas) or o.vehiculo_id = any(v_vehs))) then
    return jsonb_build_object('aplica', false, 'motivo', 'no_nuevo',
      'mensaje', 'Este código es solo para clientes nuevos y ya te has atendido con nosotros, así que no aplica. Pregúntanos por tu propio código: compártelo y gana cupones.',
      'nota', 'No aplica: ya es cliente (se atendió antes, por RUT, teléfono o patente).');
  end if;
  if exists (select 1 from referidos r where r.estado <> 'anulado' and r.referido_cliente_id = any(v_personas)) then
    return jsonb_build_object('aplica', false, 'motivo', 'ya_uso',
      'mensaje', 'Ya usaste un código de recomendación: es uno por persona.',
      'nota', 'No aplica: ya usó un código de recomendación.');
  end if;
  return jsonb_build_object('aplica', true);
end $$;
revoke execute on function _club_motivo(text, uuid, text, text, text) from public, anon, authenticated;

-- Para la reserva en línea: valida el código y, con los datos que ya escribió la persona, si le aplica
create or replace function club_validar_reserva(p_codigo text, p_rut text default null, p_telefono text default null, p_patente text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb; v_dueno uuid;
begin
  v := club_info(p_codigo);
  if not coalesce((v ->> 'ok')::boolean, false) then return v; end if;
  if v ->> 'tipo' = 'premio' then
    select cliente_id into v_dueno from cupones where upper(codigo) = upper(v ->> 'codigo');
  else
    select id into v_dueno from clientes where upper(codigo_referido) = upper(v ->> 'codigo');
  end if;
  return v || _club_motivo(v ->> 'tipo', v_dueno, p_rut, p_telefono, p_patente);
end $$;
grant execute on function club_validar_reserva(text, text, text, text) to anon, authenticated;

-- Reserva con código: además deja anotado en la cita si el código no aplica (lo ve el taller en la agenda)
create or replace function reservar_cita_v5(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha date, p_hora text, p_trabajo_id uuid, p_servicio_otro text, p_notas text,
  p_rut text, p_vehiculo_id uuid, p_marca text, p_modelo text, p_anio integer,
  p_km integer default null, p_motor text default null, p_combustible text default null,
  p_email text default null, p_modalidad text default null, p_direccion text default null,
  p_codigo text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_res jsonb; v_info jsonb; v_num bigint; v_pat text;
begin
  v_res := reservar_cita_v4(p_nombre, p_telefono, p_patente, p_fecha, p_hora, p_trabajo_id, p_servicio_otro, p_notas,
                            p_rut, p_vehiculo_id, p_marca, p_modelo, p_anio, p_km, p_motor, p_combustible,
                            p_email, p_modalidad, p_direccion);
  if coalesce((v_res ->> 'ok')::boolean, false) and nullif(btrim(coalesce(p_codigo, '')), '') is not null then
    v_num := (v_res ->> 'numero')::bigint;
    v_pat := coalesce(nullif(btrim(coalesce(p_patente, '')), ''), (select patente from vehiculos where id = p_vehiculo_id));
    v_info := club_validar_reserva(p_codigo, p_rut, p_telefono, v_pat);
    if coalesce((v_info ->> 'ok')::boolean, false) then
      update citas set codigo_descuento = v_info ->> 'codigo',
                       codigo_nota = case when v_info ->> 'aplica' = 'false' then v_info ->> 'nota' else null end
       where numero = v_num;
      v_res := v_res || jsonb_build_object('codigo', v_info ->> 'codigo', 'codigo_aplica', v_info -> 'aplica');
    else
      update citas set codigo_descuento = left(upper(btrim(p_codigo)), 30),
                       codigo_nota = 'No aplica: ' || coalesce(v_info ->> 'error', 'código no válido')
       where numero = v_num;
    end if;
  end if;
  return v_res;
end $$;
grant execute on function reservar_cita_v5(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer, integer, text, text, text, text, text, text) to anon;

-- ---------- Correos con diseño: MISMO diseño que layout.js (correoHtml). Si se cambia uno, cambiar el otro ----------
create or replace function _esc_html(p text) returns text language sql immutable as $$
  select replace(replace(replace(replace(coalesce(p, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;')
$$;

create or replace function _club_instagram() returns text language sql stable security definer set search_path = public as $$
  select case when u <> '' then 'https://instagram.com/' || u else null end
    from (select regexp_replace(regexp_replace(regexp_replace(btrim(coalesce(_club_cfg() ->> 'instagram', '')), '^@', ''),
                 '^https?://(www\.)?instagram\.com/', '', 'i'), '/.*$', '') as u) x
$$;

create or replace function _boton_correo(p_url text) returns text language sql immutable as $$
  select '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:4px 0 20px;"><tr><td style="border-radius:10px;background:#d4a84b;">'
      || '<a href="' || _esc_html(p_url) || '" target="_blank" style="display:inline-block;padding:13px 24px;font-family:Arial,Helvetica,sans-serif;font-size:15px;font-weight:bold;color:#15181e;text-decoration:none;border-radius:10px;">'
      || case when p_url like '%#condiciones%' then '📋 Ver condiciones completas'
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

create or replace function _linea_correo(p text) returns text language plpgsql immutable as $$
declare h text;
begin
  h := regexp_replace(_esc_html(p), '(https?://[^\s<]+)', '<a href="\1" target="_blank" style="color:#b8260c;word-break:break-all;">\1</a>', 'g');
  if p ~ '^[▸•-] ' then
    h := '<span style="color:#d4a84b;font-weight:bold;">▸</span>&nbsp;' || substr(h, 3);
  end if;
  -- Línea en MAYÚSCULAS = subtítulo destacado (ej. «CLUB AUTONOVA · RECOMIENDA Y GANA»)
  if p !~ '[a-záéíóúüñ]' and p ~ '[A-ZÁÉÍÓÚÑ]{3}' then
    h := '<strong style="font-family:Impact,Arial Black,Arial,sans-serif;font-weight:normal;font-size:20px;letter-spacing:1px;color:#0d0e11;">' || h || '</strong>';
  end if;
  return h;
end $$;

create or replace function _correo_html(p_asunto text, p_texto text) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  cfg taller_config%rowtype;
  v_app text; v_taller text; v_ig text; v_ig_usr text; v_tit text; v_previa text;
  v_partes text := ''; v_parrafo text := null; v_l text; m text[]; v_bloque_ig text := '';
  c_p constant text := 'margin:0 0 16px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.6;color:#2b3038;';
  c_f constant text := 'font-family:Impact,''Arial Black'',Arial,Helvetica,sans-serif;';
  c_hr constant text := '<div style="height:2px;background:#d4a84b;margin:6px 0 20px;font-size:0;line-height:0;">&nbsp;</div>';
begin
  select * into cfg from taller_config where id = 1;
  v_app := rtrim(coalesce(nullif(btrim(cfg.app_url), ''), 'https://autonova.nnovoa92.workers.dev'), '/');
  v_taller := coalesce(nullif(btrim(cfg.nombre), ''), 'Autonova');
  v_ig := _club_instagram();
  v_ig_usr := case when v_ig is not null then '@' || replace(v_ig, 'https://instagram.com/', '') else '' end;
  v_tit := btrim(coalesce(p_asunto, ''));
  if right(lower(v_tit), length(v_taller)) = lower(v_taller) then
    v_tit := btrim(regexp_replace(left(v_tit, length(v_tit) - length(v_taller)), '\s*[·—-]\s*$', ''));
  end if;

  for v_l in select btrim(x, E' \t\r') from regexp_split_to_table(coalesce(p_texto, ''), E'\n') with ordinality as t(x, n) order by n loop
    if v_l ~* 'instagram\.com' then continue; end if;      -- Instagram va destacado al final
    if v_l = '' or v_l ~ '^━+$' or v_l ~ '^https?://\S+$' or v_l ~ '^(.*):\s*(https?://\S+)$' then
      m := case when v_l ~ '^https?://\S+$' or v_l = '' or v_l ~ '^━+$' then null else regexp_match(v_l, '^(.*):\s*(https?://\S+)$') end;
      if m is not null then v_parrafo := coalesce(v_parrafo || '<br>', '') || _linea_correo(m[1] || ':'); end if;
      if v_parrafo is not null then
        v_partes := v_partes || '<p style="' || c_p || '">' || v_parrafo || '</p>';
        v_parrafo := null;
      end if;
      if v_l ~ '^━+$' then v_partes := v_partes || c_hr;
      elsif v_l ~ '^https?://\S+$' then v_partes := v_partes || _boton_correo(v_l);
      elsif m is not null then v_partes := v_partes || _boton_correo(m[2]);
      end if;
      continue;
    end if;
    v_parrafo := coalesce(v_parrafo || '<br>', '') || _linea_correo(v_l);
  end loop;
  if v_parrafo is not null then v_partes := v_partes || '<p style="' || c_p || '">' || v_parrafo || '</p>'; end if;

  select left(btrim(x, E' \t\r'), 110) into v_previa
    from regexp_split_to_table(coalesce(p_texto, ''), E'\n') with ordinality as t(x, n)
   where btrim(x, E' \t\r') <> '' and btrim(x, E' \t\r') !~* '^hola\M' and x !~ 'https?:'
   order by n limit 1;

  if v_ig is not null then
    v_bloque_ig :=
      '<tr><td class="pad" style="padding:6px 36px 6px;">'
      || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0d0e11;border-radius:14px;"><tr><td align="center" style="padding:26px 22px;">'
      || '<div style="' || c_f || 'font-size:13px;letter-spacing:4px;color:#d4a84b;text-transform:uppercase;">📸 Síguenos en Instagram</div>'
      || '<div style="' || c_f || 'font-size:30px;line-height:1.2;color:#ffffff;margin:8px 0 6px;">' || _esc_html(v_ig_usr) || '</div>'
      || '<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#c9ced6;margin:0 0 18px;">Mecánica honesta, explicada para que entiendas qué se le hace a tu auto.</div>'
      || '<a href="' || _esc_html(v_ig) || '" target="_blank" style="display:inline-block;background:#d6249f;background-image:linear-gradient(45deg,#fdb045,#fd5949 40%,#d6249f 70%,#285aeb);color:#ffffff;text-decoration:none;font-family:Arial,Helvetica,sans-serif;font-weight:bold;font-size:15px;padding:13px 28px;border-radius:999px;">Seguir a ' || _esc_html(v_ig_usr) || ' →</a>'
      || '</td></tr></table></td></tr>';
  end if;

  return '<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>' || _esc_html(v_tit) || '</title>'
    || '<style>@keyframes latido{0%,100%{transform:scale(1)}50%{transform:scale(1.05)}}.latido{animation:latido 2.4s ease-in-out infinite}@media (max-width:620px){.contenedor{width:100%!important}.pad{padding-left:20px!important;padding-right:20px!important}}</style></head>'
    || '<body style="margin:0;padding:0;background:#eceef2;">'
    || '<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">' || _esc_html(coalesce(v_previa, '')) || '</div>'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#eceef2;"><tr><td align="center" style="padding:24px 10px;">'
    || '<table role="presentation" class="contenedor" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:600px;background:#ffffff;border-radius:16px;overflow:hidden;">'
    || '<tr><td align="center" style="background:#0d0e11;padding:22px 20px 16px;"><a href="' || _esc_html(v_app) || '/reservar.html" target="_blank"><img src="' || _esc_html(v_app) || '/assets/img/logo-correo.jpg" width="200" alt="' || _esc_html(v_taller) || '" style="display:block;width:200px;max-width:70%;height:auto;border:0;"></a></td></tr>'
    || '<tr><td style="height:5px;background:#e1341e;background-image:linear-gradient(90deg,#e1341e,#d4a84b);font-size:0;line-height:0;">&nbsp;</td></tr>'
    || '<tr><td class="pad" style="padding:30px 36px 6px;">'
    || '<h1 style="margin:0 0 20px;' || c_f || 'font-weight:normal;font-size:26px;line-height:1.2;letter-spacing:0.5px;text-transform:uppercase;color:#0d0e11;">' || _esc_html(v_tit) || '</h1>'
    || v_partes
    || '</td></tr>' || v_bloque_ig
    || '<tr><td class="pad" align="center" style="padding:22px 36px 30px;">'
    || '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#3a3f48;margin:0 0 14px;">¿Necesitas otra hora? Reserva en línea en menos de 1 minuto.</div>'
    || '<a class="latido" href="' || _esc_html(v_app) || '/reservar.html" target="_blank" style="display:inline-block;background:#e1341e;color:#ffffff;text-decoration:none;font-family:Arial,Helvetica,sans-serif;font-weight:bold;font-size:17px;padding:15px 34px;border-radius:12px;">📅 Reservar hora</a>'
    || '</td></tr>'
    || '<tr><td style="background:#f4f5f7;padding:18px 36px;font-family:Arial,Helvetica,sans-serif;font-size:12px;line-height:1.6;color:#6a727f;text-align:center;">'
    || '<strong style="color:#15181e;">' || _esc_html(v_taller) || '</strong>'
    || case when nullif(btrim(cfg.telefono), '') is not null then ' · ' || _esc_html(cfg.telefono) else '' end
    || '<br>Recibes este correo por un servicio o una reserva en ' || _esc_html(v_taller) || '.'
    || '</td></tr></table></td></tr></table></body></html>';
end $$;
revoke execute on function _correo_html(text, text) from public, anon, authenticated;
revoke execute on function _club_instagram() from public, anon, authenticated;

-- Envío por el script de Gmail: ahora con el diseño (html) y el texto de respaldo con Instagram y reserva.
-- Mismo pie que layout.js (textoCorreoConPie).
create or replace function _enviar_correo_script(p_url text, p_clave text, p_nombre text, p_para text, p_asunto text, p_texto text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_resp extensions.http_response; v_j jsonb;
  v_txt text := coalesce(p_texto, ''); v_extra text := ''; v_ig text; v_app text; v_html text;
begin
  v_ig := _club_instagram();
  select rtrim(coalesce(nullif(btrim(app_url), ''), 'https://autonova.nnovoa92.workers.dev'), '/') into v_app from taller_config where id = 1;
  if v_ig is not null and v_txt !~* 'instagram\.com' then v_extra := v_extra || E'\n📸 Síguenos en Instagram: ' || v_ig; end if;
  if position('/reservar.html' in v_txt) = 0 then v_extra := v_extra || E'\n📅 Reserva tu hora en línea: ' || v_app || '/reservar.html'; end if;
  if v_extra <> '' then v_txt := v_txt || E'\n' || v_extra; end if;
  begin
    v_html := _correo_html(p_asunto, p_texto);
  exception when others then
    v_html := null;      -- si algo falla en el diseño, sale igual el texto
  end;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '25');
  v_resp := extensions.http((
    'POST', p_url, null, 'text/plain;charset=utf-8',
    jsonb_build_object('clave', p_clave, 'para', p_para, 'asunto', p_asunto, 'texto', v_txt, 'html', v_html,
                       'nombre', coalesce(p_nombre, 'Autonova'))::text
  )::extensions.http_request);
  -- Google responde con una redirección cuando el script ya se ejecutó
  if v_resp.status in (301, 302, 303) then return jsonb_build_object('estado', 'enviado'); end if;
  begin v_j := v_resp.content::jsonb; exception when others then v_j := null; end;
  if v_j ->> 'ok' = 'true' then return jsonb_build_object('estado', 'enviado'); end if;
  if v_j ? 'error' then return jsonb_build_object('estado', 'error', 'error', v_j ->> 'error'); end if;
  return jsonb_build_object('estado', 'incierto', 'error', 'respuesta inesperada (HTTP ' || v_resp.status || ')');
exception when others then
  return jsonb_build_object('estado', 'incierto', 'error', sqlerrm);
end $$;
revoke execute on function _enviar_correo_script(text, text, text, text, text, text) from public, anon, authenticated;

-- ---------- Código en la OT: «cliente nuevo» también por RUT, teléfono y patente ----------
create or replace function aplicar_codigo_ot(p_orden uuid, p_codigo text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cfg jsonb := _club_cfg();
  v_cod text := upper(btrim(coalesce(p_codigo, '')));
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  o ordenes%rowtype;
  c clientes%rowtype;
  ref clientes%rowtype;
  cup cupones%rowtype;
  v_dueno text;
  v_sub numeric;
  v_personas uuid[];
  v_vehs uuid[];
begin
  if not es_autorizado() then
    return jsonb_build_object('ok', false, 'error', 'No autorizado.');
  end if;
  select coalesce(sum(cantidad * precio_unitario), 0) into v_sub from orden_items where orden_id = p_orden;
  select * into o from ordenes where id = p_orden;
  if not found then return jsonb_build_object('ok', false, 'error', 'No encontré la OT.'); end if;
  if o.estado = 'cancelado' then return jsonb_build_object('ok', false, 'error', 'La OT está cancelada.'); end if;
  if o.codigo_descuento is not null then
    return jsonb_build_object('ok', false, 'error', 'Esta OT ya tiene el código ' || o.codigo_descuento || '. Quítalo primero.');
  end if;
  if length(v_cod) < 4 then return jsonb_build_object('ok', false, 'error', 'Escribe el código completo.'); end if;
  -- Plazo: el código se informa al reservar o al dejar el vehículo. Con la OT lista, entregada o con pagos, ya no corre.
  if o.estado in ('listo', 'entregado') then
    return jsonb_build_object('ok', false, 'error', 'El código se informa al reservar o al dejar el vehículo: esta OT ya está '
                              || case when o.estado = 'listo' then 'lista para retiro' else 'entregada' end || '.');
  end if;
  if exists (select 1 from pagos where orden_id = o.id) or exists (select 1 from abonos where orden_id = o.id) then
    return jsonb_build_object('ok', false, 'error', 'El código se informa al reservar o al dejar el vehículo: esta OT ya tiene pagos registrados.');
  end if;

  -- 1) Cupón de premio: personal, un solo uso, vigente
  select * into cup from cupones where upper(codigo) = v_cod;
  if found then
    if cup.estado = 'canjeado' then return jsonb_build_object('ok', false, 'error', 'Ese cupón ya se usó.'); end if;
    if cup.estado <> 'vigente' then return jsonb_build_object('ok', false, 'error', 'Ese cupón está anulado.'); end if;
    if cup.vence is not null and cup.vence < v_hoy then
      return jsonb_build_object('ok', false, 'error', 'Ese cupón venció el ' || to_char(cup.vence, 'DD-MM-YYYY') || '.');
    end if;
    if cup.cliente_id is distinct from o.cliente_id then
      select nombre into v_dueno from clientes where id = cup.cliente_id;
      return jsonb_build_object('ok', false, 'error', 'Ese cupón es personal de ' || coalesce(v_dueno, 'otro cliente') || '.');
    end if;
    update cupones set estado = 'canjeado', orden_canje_id = o.id, canjeado_en = now() where id = cup.id;
    update ordenes set codigo_descuento = cup.codigo, codigo_tipo = 'premio', codigo_pct = cup.pct, codigo_tope = cup.tope,
                       descuento_tipo = 'monto', descuento_base = 'total',
                       descuento_monto = round(least(v_sub * cup.pct / 100, coalesce(nullif(cup.tope, 0), v_sub))),
                       descuento_pct = case when v_sub > 0 then round(least(v_sub * cup.pct / 100, coalesce(nullif(cup.tope, 0), v_sub)) / v_sub * 100, 2) else 0 end
     where id = o.id;
    return jsonb_build_object('ok', true, 'tipo', 'premio', 'codigo', cup.codigo, 'pct', cup.pct, 'tope', cup.tope);
  end if;

  -- 2) Código de un cliente: descuento de referido en la primera visita
  select * into ref from clientes where upper(codigo_referido) = v_cod;
  if not found then return jsonb_build_object('ok', false, 'error', 'No encontré ese código.'); end if;
  if coalesce((cfg ->> 'activo')::boolean, true) is false then
    return jsonb_build_object('ok', false, 'error', 'El programa de referidos está desactivado (Configuración → Club Autonova).');
  end if;
  if ref.id = o.cliente_id then
    return jsonb_build_object('ok', false, 'error', 'Es el código del mismo cliente: es para que lo usen sus amigos.');
  end if;
  select * into c from clientes where id = o.cliente_id;
  if (nullif(regexp_replace(coalesce(c.rut, ''), '[^0-9kK]', '', 'g'), '') is not null
        and upper(regexp_replace(coalesce(c.rut, ''), '[^0-9kK]', '', 'g')) = upper(regexp_replace(coalesce(ref.rut, ''), '[^0-9kK]', '', 'g')))
     or (length(regexp_replace(coalesce(c.telefono, ''), '\D', '', 'g')) >= 8
        and right(regexp_replace(coalesce(c.telefono, ''), '\D', '', 'g'), 8) = right(regexp_replace(coalesce(ref.telefono, ''), '\D', '', 'g'), 8)) then
    return jsonb_build_object('ok', false, 'error', 'Este cliente tiene el mismo RUT o teléfono que el dueño del código.');
  end if;
  if o.vehiculo_id is not null and exists (
       select 1 from vehiculos v1 join vehiculos v2 on upper(replace(v2.patente, ' ', '')) = upper(replace(v1.patente, ' ', ''))
        where v1.id = o.vehiculo_id and v2.cliente_id = ref.id) then
    return jsonb_build_object('ok', false, 'error', 'Ese vehículo es del dueño del código.');
  end if;
  -- Cliente nuevo de verdad: la misma persona (mismo RUT o teléfono, aunque tenga otra ficha) o el mismo
  -- vehículo (misma patente) no puede haberse atendido antes
  select coalesce(array_agg(x.id), '{}') into v_personas from clientes x
   where x.id = o.cliente_id
      or (length(regexp_replace(coalesce(c.rut, ''), '[^0-9kK]', '', 'g')) >= 7
          and upper(regexp_replace(coalesce(x.rut, ''), '[^0-9kK]', '', 'g')) = upper(regexp_replace(c.rut, '[^0-9kK]', '', 'g')))
      or (length(regexp_replace(coalesce(c.telefono, ''), '\D', '', 'g')) >= 8
          and right(regexp_replace(coalesce(x.telefono, ''), '\D', '', 'g'), 8) = right(regexp_replace(c.telefono, '\D', '', 'g'), 8));
  select coalesce(array_agg(v2.id), '{}') into v_vehs
    from vehiculos v1 join vehiculos v2
      on upper(regexp_replace(coalesce(v2.patente, ''), '[^A-Za-z0-9]', '', 'g')) = upper(regexp_replace(coalesce(v1.patente, ''), '[^A-Za-z0-9]', '', 'g'))
   where v1.id = o.vehiculo_id and length(regexp_replace(coalesce(v1.patente, ''), '[^A-Za-z0-9]', '', 'g')) >= 5;
  if exists (select 1 from ordenes x where x.id <> o.id and x.estado <> 'cancelado' and x.creado_en < o.creado_en
                and (x.cliente_id = any(v_personas) or x.vehiculo_id = any(v_vehs))) then
    return jsonb_build_object('ok', false, 'error', 'No aplica: el código de referido es solo para clientes nuevos y este cliente (o este vehículo) ya se atendió antes en el taller.');
  end if;
  if exists (select 1 from referidos where referido_cliente_id = any(v_personas) and estado <> 'anulado') then
    return jsonb_build_object('ok', false, 'error', 'No aplica: este cliente ya usó un código de recomendación (es uno por persona).');
  end if;

  insert into referidos (codigo, referente_id, referido_cliente_id, orden_id)
  values (ref.codigo_referido, ref.id, o.cliente_id, o.id);
  update ordenes set codigo_descuento = ref.codigo_referido, codigo_tipo = 'referido',
                     codigo_pct = (cfg ->> 'pct')::numeric, codigo_tope = (cfg ->> 'tope')::numeric,
                     descuento_tipo = 'monto', descuento_base = 'total',
                     descuento_monto = round(least(v_sub * (cfg ->> 'pct')::numeric / 100, coalesce(nullif((cfg ->> 'tope')::numeric, 0), v_sub))),
                     descuento_pct = case when v_sub > 0 then round(least(v_sub * (cfg ->> 'pct')::numeric / 100, coalesce(nullif((cfg ->> 'tope')::numeric, 0), v_sub)) / v_sub * 100, 2) else 0 end
   where id = o.id;
  return jsonb_build_object('ok', true, 'tipo', 'referido', 'codigo', ref.codigo_referido, 'referente', ref.nombre,
                            'pct', (cfg ->> 'pct')::numeric, 'tope', (cfg ->> 'tope')::numeric);
end $$;
revoke execute on function aplicar_codigo_ot(uuid, text) from public, anon;
grant execute on function aplicar_codigo_ot(uuid, text) to authenticated;

-- Verificación: debe decir «ok»
select case when to_regprocedure('club_validar_reserva(text, text, text, text)') is not null
             and to_regprocedure('_correo_html(text, text)') is not null
             and pg_get_functiondef('aplicar_codigo_ot(uuid, text)'::regprocedure) like '%v_personas%'
            then 'ok' else 'revisar' end as v69;
