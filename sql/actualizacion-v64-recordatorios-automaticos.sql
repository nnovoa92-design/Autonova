-- ============================================================
-- v64 — Recordatorios automáticos: cotizaciones sin respuesta y cobranza de OT
--
--  * Cotizaciones: al marcarlas «enviada» se guarda la fecha (enviada_en). Si el cliente no responde, le llega
--    un correo a los 3 y 5 días y el último día de validez (siempre con el link para aprobarla, el de reserva
--    y los días que le quedan).
--  * OT entregadas con saldo: aparecen en Inicio para confirmar o rechazar la cobranza. Confirmada, le llega
--    un correo a los 3, 5 y 15 días de iniciada la cobranza, hasta que el saldo quede pagado.
--  * Los envía Supabase solo, cada hora desde las 10:00 (hora de Chile), aunque la app esté cerrada, con el
--    script de Gmail de Configuración. Cada envío queda en «Correos enviados» y en la campanita.
--  * Las cotizaciones que ya estaban enviadas antes de este script no reciben correos automáticos (puedes
--    recordárselas con los botones de Inicio).
--
-- Requiere v58 (correo automático) y v62 (registro de correos). Seguro de correr más de una vez.
-- ============================================================

alter table cotizaciones add column if not exists enviada_en timestamptz;
alter table cotizaciones add column if not exists recordatorios_enviados jsonb not null default '[]'::jsonb;
alter table ordenes add column if not exists cobranza_estado text;          -- null: por decidir · activa · omitida · pagada
alter table ordenes add column if not exists cobranza_desde timestamptz;
alter table ordenes add column if not exists cobranza_total numeric(12,2);  -- total de la OT al confirmar la cobranza
alter table ordenes add column if not exists cobranza_enviados jsonb not null default '[]'::jsonb;
alter table taller_config add column if not exists app_url text;           -- dirección de la app, para los links

comment on column cotizaciones.recordatorios_enviados is 'Recordatorios automáticos ya enviados: 1 = día 3, 2 = día 5, 3 = último día de validez';
comment on column ordenes.cobranza_enviados is 'Avisos de cobranza ya enviados: 1 = día 3, 2 = día 5, 3 = día 15 desde que se inició la cobranza';

update taller_config set app_url = 'https://autonova.nnovoa92.workers.dev' where id = 1 and coalesce(app_url, '') = '';

-- Las que ya estaban enviadas: sin correos automáticos (se avisan desde Inicio con los botones)
update cotizaciones
   set enviada_en = coalesce(fecha::timestamptz, creado_en), recordatorios_enviados = '[1,2,3]'::jsonb
 where estado = 'enviada' and enviada_en is null;

-- ---------- Ayudantes ----------
create or replace function _fmt_pesos(n numeric) returns text language sql immutable as $$
  select '$' || replace(to_char(round(coalesce(n, 0)), 'FM999,999,999,990'), ',', '.')
$$;

create or replace function _num_doc(p_prefijo text, p_numero bigint) returns text language sql immutable as $$
  select p_prefijo || '-' || case when length(p_numero::text) >= 4 then p_numero::text else lpad(p_numero::text, 4, '0') end
$$;

-- Total de un documento: el descuento corre solo sobre la mano de obra (o sobre el total en documentos antiguos)
create or replace function _total_documento(p_sub numeric, p_sub_mo numeric, p_tipo text, p_pct numeric, p_monto numeric,
                                            p_base text, p_con_iva boolean, p_iva numeric)
returns numeric language sql immutable as $$
  select (p_sub - case when coalesce(p_tipo, 'pct') = 'monto'
                       then least(greatest(coalesce(p_monto, 0), 0), case when p_base = 'total' then p_sub else p_sub_mo end)
                       else (case when p_base = 'total' then p_sub else p_sub_mo end) * least(100, greatest(0, coalesce(p_pct, 0))) / 100
                  end)
         * case when p_con_iva is false then 1 else 1 + coalesce(p_iva, 19) / 100 end
$$;

-- Texto editado en Configuración → Mensajes al cliente, o el original
create or replace function _plantilla(p_plantillas jsonb, p_clave text, p_campo text, p_defecto text) returns text
language sql immutable as $$
  select coalesce(nullif(btrim(p_plantillas -> p_clave ->> p_campo), ''), p_defecto)
$$;

create or replace function _rellenar(p_texto text, p_valores jsonb) returns text language plpgsql immutable as $$
declare k text; v text; t text := p_texto;
begin
  for k, v in select * from jsonb_each_text(p_valores) loop
    t := replace(t, '{' || k || '}', coalesce(v, ''));
  end loop;
  t := regexp_replace(t, E'[ \\t]+\\n', E'\n', 'g');
  return btrim(regexp_replace(t, E'\\n{3,}', E'\n\n', 'g'));
end $$;

-- Envía un correo con el script de Gmail del taller. Devuelve { estado: enviado | error | incierto, error }
create or replace function _enviar_correo_script(p_url text, p_clave text, p_nombre text, p_para text, p_asunto text, p_texto text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_resp extensions.http_response; v_j jsonb;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '25');
  v_resp := extensions.http((
    'POST', p_url, null, 'text/plain;charset=utf-8',
    jsonb_build_object('clave', p_clave, 'para', p_para, 'asunto', p_asunto, 'texto', p_texto, 'nombre', coalesce(p_nombre, 'Autonova'))::text
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

-- Respaldo: registro de correos (v62) y aviso en la campanita
create or replace function _registrar_correo_auto(p_para text, p_asunto text, p_texto text, p_evento text, p_res jsonb,
                                                  p_tabla text, p_id uuid, p_cliente uuid, p_vehiculo uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_ok boolean := (p_res ->> 'estado') = 'enviado';
begin
  if to_regclass('public.correos_enviados') is not null then
    insert into correos_enviados (para, asunto, texto, evento, estado, error, ref_tabla, ref_id, cliente_id, vehiculo_id)
    values (p_para, p_asunto, p_texto, p_evento, coalesce(p_res ->> 'estado', 'incierto'), p_res ->> 'error', p_tabla, p_id, p_cliente, p_vehiculo);
  end if;
  insert into notificaciones (tipo, titulo, detalle, url, leida)
  values (case when v_ok then 'correo_enviado' else 'correo_error' end,
          case when v_ok then '✉ Recordatorio enviado a ' || p_para else '⚠ No se confirmó el recordatorio a ' || p_para end,
          p_asunto || coalesce(' — ' || (p_res ->> 'error'), ''),
          'configuracion.html#registro-correos', v_ok);
exception when others then null;
end $$;

-- ---------- Envío diario ----------
create or replace function recordatorios_automaticos() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  cfg taller_config%rowtype;
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_hora int := extract(hour from (now() at time zone 'America/Santiago'))::int;
  v_url text; v_plant jsonb; v_firma text; v_contacto text; v_copia boolean;
  r record; v_paso int; v_dias int; v_vence date; v_total numeric; v_saldo numeric;
  v_vals jsonb; v_veh text; v_clave text; v_asunto text; v_texto text; v_res jsonb;
  v_cot int := 0; v_cob int := 0;
begin
  select * into cfg from taller_config where id = 1;
  if coalesce(btrim(cfg.correo_script_url), '') = '' or coalesce(btrim(cfg.correo_script_clave), '') = '' then
    return jsonb_build_object('estado', 'correo_sin_configurar');
  end if;
  if v_hora < 10 then return jsonb_build_object('estado', 'antes_de_las_10'); end if;

  v_url := rtrim(coalesce(nullif(btrim(cfg.app_url), ''), 'https://autonova.nnovoa92.workers.dev'), '/');
  v_plant := coalesce(cfg.correo_plantillas, '{}'::jsonb);
  v_contacto := concat_ws(' · ', nullif(btrim(cfg.direccion), ''), nullif(btrim(cfg.telefono), ''));
  v_firma := E'Saludos,\n' || coalesce(nullif(btrim(cfg.nombre), ''), 'El taller') || case when v_contacto <> '' then E'\n' || v_contacto else '' end;
  v_copia := coalesce(cfg.correo_eventos ->> '_copia', '') = 'true'
             and coalesce(cfg.email, '') ~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$';

  -- 1) Cotizaciones enviadas sin respuesta: día 3, día 5 y último día de validez
  if coalesce(cfg.correo_eventos ->> 'recordatorio_cotizacion', '') <> 'false' then
    for r in
      select c.*, cl.nombre as cli_nombre, cl.email as cli_email, v.patente, v.marca, v.modelo,
             coalesce(sum(i.cantidad * i.precio_unitario), 0) as subtotal,
             coalesce(sum(i.cantidad * i.precio_unitario) filter (
               where (case when i.tipo = 'otro' and coalesce(i.tipo_otro, '') <> '' then i.tipo_otro else i.tipo end) = 'mano_obra'), 0) as subtotal_mo
        from cotizaciones c
        join clientes cl on cl.id = c.cliente_id
        left join vehiculos v on v.id = c.vehiculo_id
        left join cotizacion_items i on i.cotizacion_id = c.id
       where c.estado = 'enviada' and c.enviada_en is not null
       group by c.id, cl.nombre, cl.email, v.patente, v.marca, v.modelo
    loop
      continue when coalesce(r.cli_email, '') !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$';
      v_vence := coalesce(r.fecha, (r.enviada_en at time zone 'America/Santiago')::date) + coalesce(r.validez_dias, 15);
      continue when v_hoy > v_vence;
      v_dias := v_hoy - (r.enviada_en at time zone 'America/Santiago')::date;
      v_paso := case when v_hoy = v_vence and v_dias >= 1 then 3 when v_dias >= 5 then 2 when v_dias >= 3 then 1 else 0 end;
      continue when v_paso = 0
        or exists (select 1 from jsonb_array_elements_text(r.recordatorios_enviados) x where x::int >= v_paso);

      v_total := _total_documento(r.subtotal, r.subtotal_mo, r.descuento_tipo, r.descuento_pct, r.descuento_monto,
                                  r.descuento_base, r.con_iva, cfg.iva_pct);
      v_veh := case when r.patente is not null
                    then 'su vehículo ' || r.patente || coalesce(' (' || nullif(concat_ws(' ', r.marca, r.modelo), '') || ')', '')
                    else 'su vehículo' end;
      v_vals := jsonb_build_object(
        'nombre', r.cli_nombre,
        'cotizacion', _num_doc('COT', r.numero),
        'vehiculo', v_veh,
        'total', _fmt_pesos(v_total),
        'iva', case when r.con_iva is false then 'sin IVA' else 'IVA incluido' end,
        'dias_restantes', (v_vence - v_hoy)::text || case when v_vence - v_hoy = 1 then ' día' else ' días' end,
        'vence', to_char(v_vence, 'DD-MM-YY'),
        'link', v_url || '/cotizacion.html?id=' || r.id,
        'link_reserva', v_url || '/reservar.html?cotizacion=' || _num_doc('COT', r.numero),
        'taller', coalesce(cfg.nombre, 'el taller'),
        'firma', v_firma);
      v_clave := 'cotizacion_recordatorio_' || v_paso;
      v_asunto := _rellenar(_plantilla(v_plant, v_clave, 'asunto', case v_paso
        when 1 then 'Su cotización {cotizacion} sigue disponible - {taller}'
        when 2 then '¿Agendamos su trabajo? Cotización {cotizacion} - {taller}'
        else 'Último día de su cotización {cotizacion} - {taller}' end), v_vals);
      v_texto := _rellenar(_plantilla(v_plant, v_clave, 'texto', case v_paso
        when 1 then E'Hola {nombre},\n\nLe recordamos la cotización {cotizacion} para {vehiculo}, por un total de {total} ({iva}). Aún le quedan {dias_restantes} de validez (hasta el {vence}).\n\nPuede revisarla y aprobarla aquí:\n{link}\n\nSi desea agendar el trabajo, reserve su hora aquí:\n{link_reserva}\n\nCualquier duda, estamos para ayudarle.\n\n{firma}'
        when 2 then E'Hola {nombre},\n\nQueríamos saber si pudo revisar la cotización {cotizacion} para {vehiculo} ({total}, {iva}). Le quedan {dias_restantes} de validez (hasta el {vence}); después de esa fecha los valores pueden cambiar.\n\nVer y aprobar la cotización:\n{link}\n\nReservar su hora:\n{link_reserva}\n\n{firma}'
        else E'Hola {nombre},\n\nHoy es el último día de validez de la cotización {cotizacion} para {vehiculo} ({total}, {iva}). A partir de mañana deja de ser válida y los valores pueden cambiar.\n\nSi desea mantener estos valores, apruébela hoy aquí:\n{link}\n\nO reserve su hora directamente:\n{link_reserva}\n\n{firma}' end), v_vals);
      v_asunto := regexp_replace(v_asunto, '\s+', ' ', 'g');

      v_res := _enviar_correo_script(cfg.correo_script_url, cfg.correo_script_clave, cfg.nombre, r.cli_email, v_asunto, v_texto);
      perform _registrar_correo_auto(r.cli_email, v_asunto, v_texto, 'recordatorio_cotizacion', v_res, 'cotizaciones', r.id, r.cliente_id, r.vehiculo_id);
      if v_copia and (v_res ->> 'estado') = 'enviado' and lower(cfg.email) <> lower(r.cli_email) then
        perform _enviar_correo_script(cfg.correo_script_url, cfg.correo_script_clave, cfg.nombre, cfg.email,
          'Copia: ' || v_asunto, 'Copia del recordatorio enviado a ' || r.cli_email || E'.\n\n────────────────\n\n' || v_texto);
      end if;
      -- Queda hecho este paso (y los anteriores): no se repite aunque haya fallado; el aviso queda en la campanita
      update cotizaciones set recordatorios_enviados = (select jsonb_agg(s) from generate_series(1, v_paso) s) where id = r.id;
      v_cot := v_cot + 1;
    end loop;
  end if;

  -- 2) Cobranza de OT entregadas con saldo (confirmada en Inicio): día 3, 5 y 15 desde que se inició
  if coalesce(cfg.correo_eventos ->> 'cobranza_ot', '') <> 'false' then
    for r in
      select o.*, cl.nombre as cli_nombre, cl.email as cli_email, v.patente, v.marca, v.modelo,
             coalesce((select sum(p.monto) from pagos p where p.orden_id = o.id), 0)
           + coalesce((select sum(a.monto) from abonos a where a.orden_id = o.id), 0) as pagado
        from ordenes o
        join clientes cl on cl.id = o.cliente_id
        left join vehiculos v on v.id = o.vehiculo_id
       where o.estado = 'entregado' and o.cobranza_estado = 'activa'
    loop
      v_saldo := coalesce(r.cobranza_total, 0) - r.pagado;
      if v_saldo <= 1 then
        update ordenes set cobranza_estado = 'pagada' where id = r.id;   -- ya pagó: se terminan los avisos
        continue;
      end if;
      continue when coalesce(r.cli_email, '') !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$';
      -- Los avisos cuentan desde que se inició la cobranza en Inicio
      v_dias := v_hoy - (coalesce(r.cobranza_desde, r.fecha_entrega) at time zone 'America/Santiago')::date;
      v_paso := case when v_dias >= 15 then 3 when v_dias >= 5 then 2 when v_dias >= 3 then 1 else 0 end;
      continue when v_paso = 0
        or exists (select 1 from jsonb_array_elements_text(r.cobranza_enviados) x where x::int >= v_paso);

      v_veh := case when r.patente is not null
                    then 'su vehículo ' || r.patente || coalesce(' (' || nullif(concat_ws(' ', r.marca, r.modelo), '') || ')', '')
                    else 'su vehículo' end;
      v_vals := jsonb_build_object(
        'nombre', r.cli_nombre,
        'ot', _num_doc('OT', r.numero),
        'vehiculo', v_veh,
        'fecha_entrega', to_char(coalesce(r.fecha_entrega, r.cobranza_desde) at time zone 'America/Santiago', 'DD-MM-YY'),
        'saldo', _fmt_pesos(v_saldo),
        'total', _fmt_pesos(r.cobranza_total),
        'pagado', _fmt_pesos(r.pagado),
        'taller', coalesce(cfg.nombre, 'el taller'),
        'firma', v_firma);
      v_clave := 'cobranza_' || v_paso;
      v_asunto := _rellenar(_plantilla(v_plant, v_clave, 'asunto', case v_paso
        when 1 then 'Saldo pendiente de su {ot} - {taller}'
        when 2 then 'Recordatorio de pago - {ot} · {taller}'
        else 'Último aviso: saldo pendiente de su {ot} - {taller}' end), v_vals);
      v_texto := _rellenar(_plantilla(v_plant, v_clave, 'texto', case v_paso
        when 1 then E'Hola {nombre},\n\nLe recordamos que el servicio de {vehiculo} ({ot}), entregado el {fecha_entrega}, tiene un saldo pendiente de {saldo} (total {total}, pagado {pagado}).\n\nSi ya realizó el pago, por favor envíenos el comprobante y disculpe la molestia.\n\n{firma}'
        when 2 then E'Hola {nombre},\n\nLe escribimos nuevamente por el saldo pendiente de {saldo} del servicio de {vehiculo} ({ot}), entregado el {fecha_entrega}.\n\nLe agradeceremos regularizarlo a la brevedad. Si ya pagó, envíenos el comprobante para actualizar su cuenta.\n\n{firma}'
        else E'Hola {nombre},\n\nEste es nuestro último aviso por el saldo pendiente de {saldo} del servicio de {vehiculo} ({ot}), entregado el {fecha_entrega}.\n\nLe pedimos regularizar el pago o comunicarse con nosotros para acordar cómo hacerlo. Si ya pagó, envíenos el comprobante y disculpe la molestia.\n\n{firma}' end), v_vals);
      v_asunto := regexp_replace(v_asunto, '\s+', ' ', 'g');

      v_res := _enviar_correo_script(cfg.correo_script_url, cfg.correo_script_clave, cfg.nombre, r.cli_email, v_asunto, v_texto);
      perform _registrar_correo_auto(r.cli_email, v_asunto, v_texto, 'cobranza_ot', v_res, 'ordenes', r.id, r.cliente_id, r.vehiculo_id);
      if v_copia and (v_res ->> 'estado') = 'enviado' and lower(cfg.email) <> lower(r.cli_email) then
        perform _enviar_correo_script(cfg.correo_script_url, cfg.correo_script_clave, cfg.nombre, cfg.email,
          'Copia: ' || v_asunto, 'Copia del aviso enviado a ' || r.cli_email || E'.\n\n────────────────\n\n' || v_texto);
      end if;
      update ordenes set cobranza_enviados = (select jsonb_agg(s) from generate_series(1, v_paso) s) where id = r.id;
      v_cob := v_cob + 1;
    end loop;
  end if;

  return jsonb_build_object('estado', 'ok', 'cotizaciones', v_cot, 'cobranza', v_cob);
end $$;

-- Solo la base los ejecuta (nadie desde afuera)
revoke execute on function recordatorios_automaticos() from public, anon, authenticated;
revoke execute on function _enviar_correo_script(text, text, text, text, text, text) from public, anon, authenticated;
revoke execute on function _registrar_correo_auto(text, text, text, text, jsonb, text, uuid, uuid, uuid) from public, anon, authenticated;

-- ---------- Programación: cada hora (a los 5 minutos); envía desde las 10:00 de Chile ----------
do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'autonova-recordatorios';
  perform cron.schedule('autonova-recordatorios', '5 * * * *', 'select public.recordatorios_automaticos()');
exception when others then
  raise notice 'No se pudo programar el envío automático: %. Activa la extensión pg_cron en Database → Extensions y vuelve a correr este script.', sqlerrm;
end $$;

-- Verificación: ambas extensiones activas (1 y 1)
select (select count(*) from pg_extension where extname = 'pg_cron') as pg_cron_activo,
       (select count(*) from pg_extension where extname = 'http') as http_activo;
