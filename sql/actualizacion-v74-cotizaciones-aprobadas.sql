-- ============================================================
-- v74 — Cotizaciones APROBADAS sin OT: recordatorios hasta que se haga la OT
--
--  * Una cotización aprobada que todavía no tiene OT recibe los mismos recordatorios (día 3, 5 y último día de
--    validez), con un texto que invita a AGENDAR la hora. Se detienen al crear la OT, si el vehículo ingresa,
--    o si tú marcas «🔕 Dejar de recordar».
--  * Mismo criterio de 15 días (la validez de la cotización): si pasa la validez sin OT, queda rechazada por
--    vencimiento, igual que las enviadas. Retroactivo: al correr este script se rechazan las aprobadas que ya
--    vencieron sin OT.
--
-- Requiere v73. Seguro de correr más de una vez.
-- ============================================================

alter table cotizaciones add column if not exists no_recordar boolean not null default false;

-- Rechazo por vencimiento: ahora también las aprobadas sin OT
create or replace function rechazar_cotizaciones_vencidas(p_avisar boolean default true)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  r record;
  v_n integer := 0;
begin
  for r in
    update cotizaciones c
       set estado = 'rechazada', rechazo_motivo = 'vencida',
           -- a la medianoche del día siguiente al último día de validez
           rechazada_en = least(now(), ((coalesce(c.fecha, (coalesce(c.enviada_en, c.creado_en) at time zone 'America/Santiago')::date) + coalesce(c.validez_dias, 15) + 1)::timestamp at time zone 'America/Santiago'))
     where c.estado in ('enviada', 'aprobada')
       and coalesce(c.fecha, (coalesce(c.enviada_en, c.creado_en) at time zone 'America/Santiago')::date) + coalesce(c.validez_dias, 15) < v_hoy
       and not _cotizacion_con_ingreso(c.id, c.vehiculo_id, c.enviada_en)
    returning c.id, c.numero, c.cliente_id, c.vehiculo_id
  loop
    v_n := v_n + 1;
    if p_avisar then
      insert into notificaciones (tipo, titulo, detalle, url)
      select 'cotizacion_vencida',
             'Cotización ' || _num_doc('COT', r.numero) || ' venció sin respuesta',
             coalesce((select nombre from clientes where id = r.cliente_id), 'Cliente')
               || coalesce(' · ' || (select patente from vehiculos where id = r.vehiculo_id), '')
               || ' — quedó rechazada. Si el cliente vuelve, hazle una nueva.',
             'cotizaciones.html?id=' || r.id::text;
    end if;
  end loop;
  return v_n;
end $$;
revoke execute on function rechazar_cotizaciones_vencidas(boolean) from public, anon, authenticated;

-- Recordatorios automáticos: también las aprobadas sin OT (con texto para agendar)
create or replace function recordatorios_automaticos() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  cfg taller_config%rowtype;
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_hora int := extract(hour from (now() at time zone 'America/Santiago'))::int;
  v_url text; v_plant jsonb; v_firma text; v_contacto text; v_copia boolean;
  r record; v_paso int; v_dias int; v_vence date; v_total numeric; v_saldo numeric;
  v_vals jsonb; v_veh text; v_clave text; v_asunto text; v_texto text; v_res jsonb;
  v_cot int := 0; v_cob int := 0; v_rech int := 0;
begin
  select * into cfg from taller_config where id = 1;
  -- 0) Cotizaciones vencidas sin respuesta y sin ingreso: quedan rechazadas (corre a cualquier hora)
  v_rech := rechazar_cotizaciones_vencidas(true);
  if coalesce(btrim(cfg.correo_script_url), '') = '' or coalesce(btrim(cfg.correo_script_clave), '') = '' then
    return jsonb_build_object('estado', 'correo_sin_configurar', 'rechazadas', v_rech);
  end if;
  if v_hora < 10 then return jsonb_build_object('estado', 'antes_de_las_10', 'rechazadas', v_rech); end if;

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
       where c.estado in ('enviada', 'aprobada') and coalesce(c.no_recordar, false) = false
         and (c.enviada_en is not null or c.estado = 'aprobada')
         -- Se detiene si ya hay un ingreso: una OT de esta cotización o el mismo vehículo ingresó después de enviarla
         and not exists (select 1 from ordenes o
                          where o.estado <> 'cancelado'
                            and (o.cotizacion_id = c.id
                                 or (c.vehiculo_id is not null and o.vehiculo_id = c.vehiculo_id and o.creado_en >= c.enviada_en)))
       group by c.id, cl.nombre, cl.email, v.patente, v.marca, v.modelo
    loop
      continue when coalesce(r.cli_email, '') !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$';
      v_vence := coalesce(r.fecha, (coalesce(r.enviada_en, r.creado_en) at time zone 'America/Santiago')::date) + coalesce(r.validez_dias, 15);
      continue when v_hoy > v_vence;
      v_dias := v_hoy - (coalesce(r.enviada_en, r.creado_en) at time zone 'America/Santiago')::date;
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
      -- Cotización ya APROBADA pero sin OT: el recordatorio invita a agendar (mismo texto por defecto que
      -- layout.js → PLANTILLAS_CORREO.cotizacion_aprobada_recordatorio; si se cambia uno, cambiar el otro)
      if r.estado = 'aprobada' then
        v_asunto := _rellenar(_plantilla(v_plant, 'cotizacion_aprobada_recordatorio', 'asunto',
          '¿Agendamos su trabajo? Su cotización {cotizacion} está aprobada - {taller}'), v_vals);
        v_texto := _rellenar(_plantilla(v_plant, 'cotizacion_aprobada_recordatorio', 'texto',
          E'Hola {nombre},\n\n¡Gracias por aprobar la cotización {cotizacion} para {vehiculo} ({total}, {iva})! Aún no tenemos su hora agendada: le quedan {dias_restantes} de validez (hasta el {vence}); después de esa fecha los valores pueden cambiar.\n\nReserve su hora aquí:\n{link_reserva}\n\nVer la cotización:\n{link}\n\n{firma}'), v_vals);
      end if;
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

  return jsonb_build_object('estado', 'ok', 'cotizaciones', v_cot, 'cobranza', v_cob, 'rechazadas', v_rech);
end $$;
revoke execute on function recordatorios_automaticos() from public, anon, authenticated;

-- Retroactivo: aprobadas (y enviadas) que ya vencieron sin OT quedan rechazadas ahora (sin avisos en la campanita)
with r as (select rechazar_cotizaciones_vencidas(false) as n)
select r.n as vencidas_rechazadas_ahora,
       (select count(*) from cotizaciones where estado = 'aprobada') as aprobadas_sin_ot_vigentes
  from r;
