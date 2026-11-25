-- ============================================================
-- Autonova · Actualización v75 · Pie de firma en todos los correos
-- Los correos automáticos (recordatorios, encuestas, Club, etc.) llevan
-- el logo arriba y, al final del mensaje, la firma del taller
-- (imagen assets/img/firma-correo.jpg). Mismo diseño que los correos
-- que se envían desde la página. Solo cambia el diseño del correo.
-- ============================================================

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
    || '</td></tr>'
    || '<tr><td class="pad" style="padding:4px 36px 18px;"><div style="border-top:1px solid #e3e6eb;padding-top:16px;"><img src="' || _esc_html(v_app) || '/assets/img/firma-correo.jpg" width="420" alt="Firma ' || _esc_html(v_taller) || '" style="display:block;width:420px;max-width:100%;height:auto;border:0;"></div></td></tr>'
    || v_bloque_ig
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

-- Comprobación: debe decir «firma ok»
select case when _correo_html('Prueba', 'Hola') like '%firma-correo.jpg%' then 'firma ok' else 'FALTA la firma' end as resultado;
