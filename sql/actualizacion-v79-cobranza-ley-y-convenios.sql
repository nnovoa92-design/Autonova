-- ============================================================
-- v79 — Cobranza de OT dentro de la ley (Ley 19.496 modificada por la Ley 21.320) + convenio de pago
--
--  * Avisos automáticos por correo mientras la cobranza esté activa y quede saldo:
--      - solo días hábiles (lunes a viernes, sin feriados ni días bloqueados completos en la agenda);
--      - como máximo 2 por semana y con al menos 3 días entre uno y otro (cuentan también los WhatsApp y
--        correos que mandes a mano desde Inicio);
--      - el primero de la semana sale desde las 09:00 y el segundo desde las 17:00 (siempre antes de las 20:00);
--      - el primer aviso, a los 3 días de iniciada la cobranza; tras N avisos sin respuesta (8 por defecto)
--        se detiene y te avisa para que lo llames tú.
--  * Cada aviso trae un link privado (pago.html): ver el saldo y cómo pagar, «Ya pagué» (pausa los avisos
--    4 días mientras lo revisas) y el banner «¿No puede pagar todo ahora?» para PROPONER UN CONVENIO DE PAGO
--    en cuotas. Tú lo aceptas, lo ajustas o lo rechazas en Inicio. Con convenio activo ya no hay cobranza
--    general: solo un aviso el día antes de cada cuota y otro si una cuota se atrasa. Si se atrasa más de
--    15 días el convenio queda incumplido y vuelve la cobranza normal.
--  * Todo queda registrado (cobranza_gestiones) para respaldar que se cumplió la ley.
--
-- Requiere v64 y v74. Seguro de correr más de una vez.
-- ============================================================

-- 1) Columnas y tablas nuevas
alter table ordenes add column if not exists token_pago text default replace(gen_random_uuid()::text, '-', '');
update ordenes set token_pago = replace(gen_random_uuid()::text, '-', '') where token_pago is null;
create unique index if not exists idx_ordenes_token_pago on ordenes (token_pago);
alter table ordenes add column if not exists cobranza_pausa_hasta timestamptz;
alter table ordenes add column if not exists pago_informado jsonb;            -- {monto, fecha, medio, comentario, en}
alter table ordenes add column if not exists cobranza_tope_avisado boolean not null default false;
alter table taller_config add column if not exists cobranza jsonb;            -- {max_avisos, max_cuotas, dias_entre_cuotas, primer_pago_dias, datos_pago}

create table if not exists cobranza_gestiones (
  id uuid primary key default uuid_generate_v4(),
  orden_id uuid not null references ordenes(id) on delete cascade,
  canal text not null check (canal in ('correo', 'whatsapp')),
  origen text not null default 'auto' check (origen in ('auto', 'manual')),
  plantilla text,
  detalle text,
  estado text,
  creado_en timestamptz not null default now()
);
create index if not exists idx_cobranza_gestiones_orden on cobranza_gestiones (orden_id, creado_en);
alter table cobranza_gestiones enable row level security;
drop policy if exists "Acceso solo usuarios autorizados" on cobranza_gestiones;
create policy "Acceso solo usuarios autorizados" on cobranza_gestiones for all using (es_autorizado()) with check (es_autorizado());

create table if not exists convenios (
  id uuid primary key default uuid_generate_v4(),
  orden_id uuid not null references ordenes(id) on delete cascade,
  estado text not null default 'propuesto' check (estado in ('propuesto', 'activo', 'rechazado', 'cumplido', 'incumplido', 'anulado')),
  propuesto_por text not null default 'cliente' check (propuesto_por in ('cliente', 'taller')),
  saldo numeric(12,2) not null,
  pagado_base numeric(12,2) not null default 0,     -- lo pagado al momento del convenio: las cuotas se cubren con lo que se pague después
  cuotas jsonb not null default '[]'::jsonb,        -- [{n, fecha 'AAAA-MM-DD', monto}]
  comentario text,
  respuesta text,
  creado_en timestamptz not null default now(),
  respondido_en timestamptz
);
create index if not exists idx_convenios_orden on convenios (orden_id, creado_en);
alter table convenios enable row level security;
drop policy if exists "Acceso solo usuarios autorizados" on convenios;
create policy "Acceso solo usuarios autorizados" on convenios for all using (es_autorizado()) with check (es_autorizado());

-- Los avisos de cobranza que ya salieron (v64) cuentan para los límites y el historial
insert into cobranza_gestiones (orden_id, canal, origen, plantilla, estado, creado_en)
select ce.ref_id, 'correo', case when ce.evento = 'cobranza_ot' then 'auto' else 'manual' end, 'cobranza_anterior', ce.estado, ce.creado_en
  from correos_enviados ce
 where ce.ref_tabla = 'ordenes' and ce.evento = 'cobranza_ot' and ce.ref_id in (select id from ordenes)
   and not exists (select 1 from cobranza_gestiones g where g.orden_id = ce.ref_id and g.creado_en = ce.creado_en);

-- 2) Configuración de cobranza (valores por defecto; se cambian en Configuración → Cobranza)
create or replace function _cobranza_cfg() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('max_avisos', 8, 'max_cuotas', 3, 'dias_entre_cuotas', 30, 'primer_pago_dias', 15, 'datos_pago', '')
         || coalesce((select cobranza from taller_config where id = 1), '{}'::jsonb);
$$;
revoke execute on function _cobranza_cfg() from public, anon, authenticated;

-- 3) Día hábil para cobranza: lunes a viernes, sin feriados nacionales ni días bloqueados completos en la agenda
create or replace function _dia_habil_cobranza(p_dia date) returns boolean
language sql stable security definer set search_path = public as $$
  select extract(isodow from p_dia) between 1 and 5
     and p_dia <> all (array[
       '2026-01-01','2026-04-03','2026-04-04','2026-05-01','2026-05-21','2026-06-29','2026-07-16','2026-08-15',
       '2026-09-18','2026-09-19','2026-10-12','2026-10-31','2026-11-01','2026-12-08','2026-12-25',
       '2027-01-01','2027-03-26','2027-03-27','2027-05-01','2027-05-21','2027-06-21','2027-06-28','2027-07-16',
       '2027-08-15','2027-09-18','2027-09-19','2027-10-11','2027-11-01','2027-12-08','2027-12-25']::date[])
     and not exists (select 1 from bloqueos_agenda b where p_dia between b.fecha_desde and b.fecha_hasta and b.hora_desde is null);
$$;
grant execute on function _dia_habil_cobranza(date) to authenticated;

-- 4) Saldo de una OT en cobranza (total fijado al iniciar la cobranza − pagos − abonos)
create or replace function _pagado_ot(p_orden uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select sum(monto) from pagos where orden_id = p_orden), 0)
       + coalesce((select sum(monto) from abonos where orden_id = p_orden), 0);
$$;
revoke execute on function _pagado_ot(uuid) from public, anon, authenticated;

-- 5) Envío automático de cobranza (cada hora; decide qué OT pueden recibir aviso ahora según la ley)
--    Textos por defecto = layout.js → PLANTILLAS_CORREO (cobranza_1, cobranza_2, cobranza_3, cobranza_ultimo,
--    convenio_cuota, convenio_cuota_vencida). Si se cambia uno, cambiar el otro.
create or replace function cobranza_automatica() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  cfg taller_config%rowtype;
  v_cc jsonb := _cobranza_cfg();
  v_ahora timestamp := now() at time zone 'America/Santiago';
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_hora int := extract(hour from (now() at time zone 'America/Santiago'))::int;
  v_lunes date := date_trunc('week', now() at time zone 'America/Santiago')::date;
  v_url text; v_plant jsonb; v_firma text; v_contacto text; v_copia boolean; v_pie text; v_bloque text;
  r record; v_conv convenios%rowtype; v_cuota jsonb;
  v_saldo numeric; v_sem int; v_ult date; v_n int; v_max int; v_acum numeric; v_pagado_conv numeric;
  v_clave text; v_detalle text; v_vals jsonb; v_veh text; v_asunto text; v_texto text; v_res jsonb; v_link text;
  v_env int := 0;
  v_default_asunto text; v_default_texto text;
begin
  select * into cfg from taller_config where id = 1;
  if coalesce(btrim(cfg.correo_script_url), '') = '' or coalesce(btrim(cfg.correo_script_clave), '') = '' then
    return jsonb_build_object('estado', 'correo_sin_configurar');
  end if;
  if coalesce(cfg.correo_eventos ->> 'cobranza_ot', '') = 'false' then return jsonb_build_object('estado', 'apagado'); end if;
  if not _dia_habil_cobranza(v_hoy) then return jsonb_build_object('estado', 'dia_no_habil'); end if;
  if v_hora < 9 or v_hora >= 20 then return jsonb_build_object('estado', 'fuera_de_horario'); end if;

  v_url := rtrim(coalesce(nullif(btrim(cfg.app_url), ''), 'https://autonova.nnovoa92.workers.dev'), '/');
  v_plant := coalesce(cfg.correo_plantillas, '{}'::jsonb);
  v_contacto := concat_ws(' · ', nullif(btrim(cfg.direccion), ''), nullif(btrim(cfg.telefono), ''));
  v_firma := E'Saludos,\n' || coalesce(nullif(btrim(cfg.nombre), ''), 'El taller') || case when v_contacto <> '' then E'\n' || v_contacto else '' end;
  v_copia := coalesce(cfg.correo_eventos ->> '_copia', '') = 'true' and coalesce(cfg.email, '') ~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$';
  v_pie := E'\n\nAviso de cobranza extrajudicial conforme a la Ley 19.496 (modificada por la Ley 21.320): enviamos como máximo 2 avisos por semana, en días hábiles entre las 8:00 y las 20:00, y no cobramos gastos de cobranza.';
  v_max := greatest(coalesce((v_cc ->> 'max_avisos')::int, 8), 2);

  for r in
    select o.*, cl.nombre as cli_nombre, cl.email as cli_email, v.patente, v.marca, v.modelo, _pagado_ot(o.id) as pagado
      from ordenes o
      join clientes cl on cl.id = o.cliente_id
      left join vehiculos v on v.id = o.vehiculo_id
     where o.estado = 'entregado' and o.cobranza_estado = 'activa'
  loop
    v_saldo := coalesce(r.cobranza_total, 0) - r.pagado;
    if v_saldo <= 1 then
      update ordenes set cobranza_estado = 'pagada', pago_informado = null, cobranza_pausa_hasta = null where id = r.id;
      update convenios set estado = 'cumplido' where orden_id = r.id and estado = 'activo';
      continue;
    end if;
    continue when r.cobranza_pausa_hasta is not null and r.cobranza_pausa_hasta > now();   -- «Ya pagué»: en revisión
    continue when coalesce(r.cli_email, '') !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$';

    -- Límites de la ley: máx. 2 por semana, al menos 3 días entre avisos, el segundo de la semana desde las 17:00
    select count(*) filter (where (g.creado_en at time zone 'America/Santiago')::date >= v_lunes),
           max((g.creado_en at time zone 'America/Santiago')::date)
      into v_sem, v_ult
      from cobranza_gestiones g where g.orden_id = r.id;
    continue when v_sem >= 2;
    continue when v_ult is not null and v_hoy - v_ult < 3;
    continue when v_sem = 1 and v_hora < 17;

    v_clave := null; v_detalle := null;
    v_link := v_url || '/pago.html?t=' || r.token_pago;
    v_veh := case when r.patente is not null
                  then 'su vehículo ' || r.patente || coalesce(' (' || nullif(concat_ws(' ', r.marca, r.modelo), '') || ')', '')
                  else 'su vehículo' end;
    v_vals := jsonb_build_object(
      'nombre', r.cli_nombre, 'ot', _num_doc('OT', r.numero), 'vehiculo', v_veh,
      'fecha_entrega', to_char(coalesce(r.fecha_entrega, r.cobranza_desde) at time zone 'America/Santiago', 'DD-MM-YY'),
      'saldo', _fmt_pesos(v_saldo), 'total', _fmt_pesos(r.cobranza_total), 'pagado', _fmt_pesos(r.pagado),
      'link_pago', v_link, 'max_cuotas', (v_cc ->> 'max_cuotas'),
      'bloque_convenio', E'\n\n━━━━━━━━━━━━\n¿NO PUEDE PAGAR TODO AHORA?\nPuede pagarlo en hasta ' || (v_cc ->> 'max_cuotas')
                         || E' cuotas con un convenio de pago. Propóngalo aquí en 1 minuto, sin trámites:\n' || v_link || '&convenio=1',
      'pie_legal', v_pie,
      'taller', coalesce(cfg.nombre, 'el taller'), 'firma', v_firma);

    select * into v_conv from convenios where orden_id = r.id and estado in ('propuesto', 'activo') order by creado_en desc limit 1;
    if found and v_conv.estado = 'propuesto' then
      continue;   -- el cliente propuso un convenio: no se le cobra mientras lo revisas
    elsif found and v_conv.estado = 'activo' then
      -- Convenio activo: la primera cuota que lo pagado desde el convenio aún no cubre
      v_pagado_conv := r.pagado - coalesce(v_conv.pagado_base, 0);
      v_acum := 0; v_cuota := null;
      for v_cuota in select x from jsonb_array_elements(v_conv.cuotas) x order by (x ->> 'n')::int loop
        v_acum := v_acum + (v_cuota ->> 'monto')::numeric;
        exit when v_pagado_conv < v_acum - 1;
        v_cuota := null;
      end loop;
      continue when v_cuota is null;
      if v_hoy > (v_cuota ->> 'fecha')::date + 15 then
        update convenios set estado = 'incumplido', respondido_en = now() where id = v_conv.id;
        insert into notificaciones (tipo, titulo, detalle, url, ref_id)
        values ('convenio_incumplido', '⚠ Convenio de pago incumplido · ' || _num_doc('OT', r.numero),
                coalesce(r.cli_nombre, 'Cliente') || ' · la cuota ' || (v_cuota ->> 'n') || ' venció el ' || to_char((v_cuota ->> 'fecha')::date, 'DD-MM')
                  || ' y no se ha pagado. Vuelve la cobranza normal.', 'dashboard.html', r.id);
        continue;
      elsif v_hoy >= (v_cuota ->> 'fecha')::date + 3 then
        v_clave := 'convenio_cuota_vencida'; v_detalle := 'cuota_vencida:' || (v_cuota ->> 'n');
      elsif v_hoy >= (v_cuota ->> 'fecha')::date - 1 and v_hoy <= (v_cuota ->> 'fecha')::date then
        v_clave := 'convenio_cuota'; v_detalle := 'cuota:' || (v_cuota ->> 'n');
      end if;
      continue when v_clave is null
        or exists (select 1 from cobranza_gestiones g where g.orden_id = r.id and g.detalle = v_detalle and g.creado_en >= v_conv.creado_en);
      v_vals := v_vals || jsonb_build_object(
        'cuota', (v_cuota ->> 'n') || ' de ' || jsonb_array_length(v_conv.cuotas)::text,
        'monto_cuota', _fmt_pesos((v_cuota ->> 'monto')::numeric),
        'vence', to_char((v_cuota ->> 'fecha')::date, 'DD-MM-YY'),
        'cuando', case when (v_cuota ->> 'fecha')::date = v_hoy then 'hoy' else 'mañana, ' || to_char((v_cuota ->> 'fecha')::date, 'DD-MM-YY') end);
    else
      -- Cobranza normal: el primer aviso a los 3 días de iniciada; tope de avisos sin respuesta
      select count(*) into v_n from cobranza_gestiones g
       where g.orden_id = r.id and coalesce(g.plantilla, '') not like 'convenio%'
         and g.creado_en >= coalesce(r.cobranza_desde, r.fecha_entrega, now() - interval '10 years');
      if v_n >= v_max then
        if not r.cobranza_tope_avisado then
          update ordenes set cobranza_tope_avisado = true where id = r.id;
          insert into notificaciones (tipo, titulo, detalle, url, ref_id)
          values ('cobranza_tope', '📞 Cobranza sin respuesta · ' || _num_doc('OT', r.numero),
                  coalesce(r.cli_nombre, 'Cliente') || ' · saldo ' || _fmt_pesos(v_saldo) || ' · ya salieron ' || v_n
                    || ' avisos sin respuesta: los automáticos se detuvieron. Llámalo o decide en Inicio.', 'dashboard.html', r.id);
        end if;
        continue;
      end if;
      continue when v_n = 0 and v_hoy - (coalesce(r.cobranza_desde, now()) at time zone 'America/Santiago')::date < 3;
      v_clave := case when v_n = 0 then 'cobranza_1' when v_n >= v_max - 1 then 'cobranza_ultimo'
                      when v_n = 1 then 'cobranza_2' else 'cobranza_3' end;
    end if;

    v_default_asunto := case v_clave
      when 'cobranza_1' then 'Saldo pendiente de su {ot} - {taller}'
      when 'cobranza_2' then 'Recordatorio de pago - {ot} · {taller}'
      when 'cobranza_3' then 'Seguimos atentos a su pago - {ot} · {taller}'
      when 'cobranza_ultimo' then 'Último aviso automático: saldo pendiente de su {ot} - {taller}'
      when 'convenio_cuota' then 'Su cuota {cuota} vence {cuando} - {ot} · {taller}'
      else 'Cuota {cuota} pendiente - {ot} · {taller}' end;
    v_default_texto := case v_clave
      when 'cobranza_1' then E'Hola {nombre},\n\nLe recordamos que el servicio de {vehiculo} ({ot}), entregado el {fecha_entrega}, tiene un saldo pendiente de {saldo} (total {total}, pagado {pagado}).\n\nPuede ver el detalle, cómo pagar o avisarnos si ya pagó aquí:\n{link_pago}\n\nSi ya realizó el pago, disculpe la molestia.{bloque_convenio}\n\n{firma}{pie_legal}'
      when 'cobranza_2' then E'Hola {nombre},\n\nLe escribimos nuevamente por el saldo pendiente de {saldo} del servicio de {vehiculo} ({ot}), entregado el {fecha_entrega}.\n\nPuede ver el detalle, cómo pagar o avisarnos si ya pagó aquí:\n{link_pago}{bloque_convenio}\n\n{firma}{pie_legal}'
      when 'cobranza_3' then E'Hola {nombre},\n\nSu {ot} ({vehiculo}) mantiene un saldo pendiente de {saldo}. Si tiene alguna dificultad para pagarlo, cuéntenos: queremos ayudarle a encontrar una forma cómoda de hacerlo.\n\nVer el detalle, cómo pagar o avisar un pago:\n{link_pago}{bloque_convenio}\n\n{firma}{pie_legal}'
      when 'cobranza_ultimo' then E'Hola {nombre},\n\nEste es nuestro último aviso automático por el saldo pendiente de {saldo} del servicio de {vehiculo} ({ot}), entregado el {fecha_entrega}. Desde ahora le contactaremos directamente.\n\nLe pedimos regularizar el pago o acordar con nosotros cómo hacerlo:\n{link_pago}{bloque_convenio}\n\n{firma}{pie_legal}'
      when 'convenio_cuota' then E'Hola {nombre},\n\nLe recordamos que la cuota {cuota} de su convenio de pago de la {ot} ({monto_cuota}) vence {cuando}.\n\nVer su convenio, cómo pagar o avisar el pago:\n{link_pago}\n\n¡Gracias por cumplir su convenio!\n\n{firma}{pie_legal}'
      else E'Hola {nombre},\n\nNo hemos registrado el pago de la cuota {cuota} de su convenio de la {ot} ({monto_cuota}), que venció el {vence}. Si ya pagó, avísenos aquí para actualizar su cuenta; si tuvo algún problema, cuéntenos y lo vemos juntos:\n{link_pago}\n\n{firma}{pie_legal}' end;
    v_asunto := regexp_replace(_rellenar(_plantilla(v_plant, v_clave, 'asunto', v_default_asunto), v_vals), '\s+', ' ', 'g');
    v_texto := _rellenar(_plantilla(v_plant, v_clave, 'texto', v_default_texto), v_vals);

    v_res := _enviar_correo_script(cfg.correo_script_url, cfg.correo_script_clave, cfg.nombre, r.cli_email, v_asunto, v_texto);
    perform _registrar_correo_auto(r.cli_email, v_asunto, v_texto, 'cobranza_ot', v_res, 'ordenes', r.id, r.cliente_id, r.vehiculo_id);
    insert into cobranza_gestiones (orden_id, canal, origen, plantilla, detalle, estado)
    values (r.id, 'correo', 'auto', v_clave, v_detalle, coalesce(v_res ->> 'estado', 'incierto'));
    if v_copia and (v_res ->> 'estado') = 'enviado' and lower(cfg.email) <> lower(r.cli_email) then
      perform _enviar_correo_script(cfg.correo_script_url, cfg.correo_script_clave, cfg.nombre, cfg.email,
        'Copia: ' || v_asunto, 'Copia del aviso enviado a ' || r.cli_email || E'.\n\n────────────────\n\n' || v_texto);
    end if;
    if v_clave = 'cobranza_ultimo' then
      insert into notificaciones (tipo, titulo, detalle, url, ref_id)
      values ('cobranza_tope', '📞 Salió el último aviso automático · ' || _num_doc('OT', r.numero),
              coalesce(r.cli_nombre, 'Cliente') || ' · saldo ' || _fmt_pesos(v_saldo) || '. Desde ahora conviene llamarlo.', 'dashboard.html', r.id);
    end if;
    v_env := v_env + 1;
  end loop;
  return jsonb_build_object('estado', 'ok', 'enviados', v_env);
end $$;
revoke execute on function cobranza_automatica() from public, anon, authenticated;

-- 6) Los recordatorios de cotizaciones siguen igual (v74), pero sin la cobranza (ahora va aparte, con la ley)
create or replace function recordatorios_automaticos() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  cfg taller_config%rowtype;
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_hora int := extract(hour from (now() at time zone 'America/Santiago'))::int;
  v_url text; v_plant jsonb; v_firma text; v_contacto text; v_copia boolean;
  r record; v_paso int; v_dias int; v_vence date; v_total numeric;
  v_vals jsonb; v_veh text; v_clave text; v_asunto text; v_texto text; v_res jsonb;
  v_cot int := 0; v_rech int := 0;
begin
  select * into cfg from taller_config where id = 1;
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
      update cotizaciones set recordatorios_enviados = (select jsonb_agg(s) from generate_series(1, v_paso) s) where id = r.id;
      v_cot := v_cot + 1;
    end loop;
  end if;
  return jsonb_build_object('estado', 'ok', 'cotizaciones', v_cot, 'rechazadas', v_rech);
end $$;
revoke execute on function recordatorios_automaticos() from public, anon, authenticated;

-- 7) Página pública del cliente (pago.html?t=...): saldo, cómo pagar, «Ya pagué» y convenio
create or replace function pago_info(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o ordenes%rowtype; v_cfg taller_config%rowtype; v_cc jsonb := _cobranza_cfg(); v_pagado numeric; v_conv convenios%rowtype;
        v_cli clientes%rowtype; v_veh vehiculos%rowtype;
begin
  if p_token is null or length(p_token) < 20 then return jsonb_build_object('ok', false, 'error', 'El link no es válido.'); end if;
  select * into o from ordenes where token_pago = p_token;
  if not found then return jsonb_build_object('ok', false, 'error', 'No encontramos esta cuenta.'); end if;
  select * into v_cfg from taller_config where id = 1;
  select * into v_cli from clientes where id = o.cliente_id;
  select * into v_veh from vehiculos where id = o.vehiculo_id;
  v_pagado := _pagado_ot(o.id);
  select * into v_conv from convenios where orden_id = o.id and estado in ('propuesto', 'activo', 'rechazado', 'cumplido', 'incumplido')
   order by creado_en desc limit 1;
  return jsonb_build_object(
    'ok', true,
    'ot', _num_doc('OT', o.numero),
    'estado', case when o.cobranza_estado = 'pagada' or (o.cobranza_total is not null and o.cobranza_total - v_pagado <= 1) then 'pagada'
                   when o.cobranza_total is null then 'sin_cobranza' else coalesce(o.cobranza_estado, 'por_decidir') end,
    'nombre', split_part(btrim(coalesce(v_cli.nombre, 'cliente')), ' ', 1),
    'patente', v_veh.patente,
    'vehiculo', nullif(btrim(concat_ws(' ', v_veh.marca, v_veh.modelo)), ''),
    'fecha_entrega', to_char(o.fecha_entrega at time zone 'America/Santiago', 'YYYY-MM-DD'),
    'total', o.cobranza_total, 'pagado', v_pagado, 'saldo', greatest(coalesce(o.cobranza_total, 0) - v_pagado, 0),
    'pago_informado', o.pago_informado,
    'convenio', case when v_conv.id is null then null else jsonb_build_object(
        'estado', v_conv.estado, 'cuotas', v_conv.cuotas, 'saldo', v_conv.saldo, 'respuesta', v_conv.respuesta,
        'pagado_convenio', v_pagado - coalesce(v_conv.pagado_base, 0), 'creado_en', v_conv.creado_en) end,
    'limites', jsonb_build_object('max_cuotas', (v_cc ->> 'max_cuotas')::int, 'dias_entre_cuotas', (v_cc ->> 'dias_entre_cuotas')::int,
                                  'primer_pago_dias', (v_cc ->> 'primer_pago_dias')::int),
    'datos_pago', nullif(btrim(coalesce(v_cc ->> 'datos_pago', '')), ''),
    'taller', jsonb_build_object('nombre', v_cfg.nombre, 'telefono', v_cfg.telefono, 'direccion', v_cfg.direccion, 'email', v_cfg.email));
end $$;
grant execute on function pago_info(text) to anon, authenticated;

create or replace function pago_proponer_convenio(p_token text, p_cuotas int, p_primera date, p_cada_dias int, p_comentario text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o ordenes%rowtype; v_cc jsonb := _cobranza_cfg(); v_pagado numeric; v_saldo numeric; v_monto numeric; v_resto numeric;
        v_hoy date := (now() at time zone 'America/Santiago')::date; v_cuotas jsonb := '[]'::jsonb; v_cada int;
        v_ip text := reservar_ip(); v_n int; v_max int := coalesce((v_cc ->> 'max_cuotas')::int, 3);
begin
  if p_token is null or length(p_token) < 20 then return jsonb_build_object('ok', false, 'error', 'El link no es válido.'); end if;
  select * into o from ordenes where token_pago = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'No encontramos esta cuenta.'); end if;
  if o.cobranza_total is null or coalesce(o.cobranza_estado, '') not in ('activa') then
    return jsonb_build_object('ok', false, 'error', 'Esta cuenta no tiene cobranza activa. Escríbenos y lo vemos.');
  end if;
  select count(*) into v_n from reservar_limites where ip = v_ip and tipo = 'pago' and creado_en > now() - interval '1 hour';
  if v_n >= 10 then return jsonb_build_object('ok', false, 'error', 'Hiciste varios intentos seguidos. Espera un momento o escríbenos.'); end if;
  if exists (select 1 from convenios where orden_id = o.id and estado = 'activo') then
    return jsonb_build_object('ok', false, 'error', 'Ya tienes un convenio de pago activo.');
  end if;
  v_pagado := _pagado_ot(o.id);
  v_saldo := o.cobranza_total - v_pagado;
  if v_saldo <= 1 then return jsonb_build_object('ok', false, 'error', 'Esta cuenta ya está pagada. ¡Gracias!'); end if;
  if p_cuotas is null or p_cuotas < 2 or p_cuotas > v_max then
    return jsonb_build_object('ok', false, 'error', 'Puedes elegir entre 2 y ' || v_max || ' cuotas.');
  end if;
  if p_primera is null or p_primera < v_hoy or p_primera > v_hoy + coalesce((v_cc ->> 'primer_pago_dias')::int, 15) then
    return jsonb_build_object('ok', false, 'error', 'El primer pago debe ser dentro de los próximos ' || coalesce((v_cc ->> 'primer_pago_dias')::int, 15) || ' días.');
  end if;
  v_cada := case when p_cada_dias = 15 then 15 else 30 end;
  v_cada := least(v_cada, greatest(coalesce((v_cc ->> 'dias_entre_cuotas')::int, 30), 7));
  -- Cuotas iguales redondeadas a $100; la última ajusta la diferencia
  v_monto := round(v_saldo / p_cuotas / 100) * 100;
  v_resto := v_saldo;
  for i in 1 .. p_cuotas loop
    v_cuotas := v_cuotas || jsonb_build_object('n', i, 'fecha', (p_primera + (i - 1) * v_cada)::text,
                                               'monto', case when i = p_cuotas then v_resto else v_monto end);
    v_resto := v_resto - v_monto;
  end loop;
  insert into reservar_limites (ip, tipo) values (v_ip, 'pago');
  update convenios set estado = 'anulado' where orden_id = o.id and estado = 'propuesto';   -- una nueva propuesta reemplaza a la anterior
  insert into convenios (orden_id, estado, propuesto_por, saldo, pagado_base, cuotas, comentario)
  values (o.id, 'propuesto', 'cliente', v_saldo, v_pagado, v_cuotas, nullif(left(btrim(coalesce(limpiar_marcado(p_comentario), '')), 500), ''));
  begin
    insert into notificaciones (tipo, titulo, detalle, url, ref_id)
    values ('convenio_propuesto', '🤝 Propuesta de convenio de pago · ' || _num_doc('OT', o.numero),
            coalesce((select nombre from clientes where id = o.cliente_id), 'Cliente') || ' propone pagar ' || _fmt_pesos(v_saldo)
              || ' en ' || p_cuotas || ' cuotas desde el ' || to_char(p_primera, 'DD-MM') || '. Acéptala o recházala en Inicio.', 'dashboard.html', o.id);
  exception when others then null;
  end;
  return jsonb_build_object('ok', true, 'cuotas', v_cuotas, 'saldo', v_saldo);
end $$;
grant execute on function pago_proponer_convenio(text, int, date, int, text) to anon, authenticated;

create or replace function pago_informar(p_token text, p_monto numeric, p_fecha date, p_medio text, p_comentario text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o ordenes%rowtype; v_ip text := reservar_ip(); v_n int; v_hoy date := (now() at time zone 'America/Santiago')::date;
begin
  if p_token is null or length(p_token) < 20 then return jsonb_build_object('ok', false, 'error', 'El link no es válido.'); end if;
  select * into o from ordenes where token_pago = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'No encontramos esta cuenta.'); end if;
  select count(*) into v_n from reservar_limites where ip = v_ip and tipo = 'pago' and creado_en > now() - interval '1 hour';
  if v_n >= 10 then return jsonb_build_object('ok', false, 'error', 'Hiciste varios intentos seguidos. Espera un momento o escríbenos.'); end if;
  if p_monto is null or p_monto <= 0 or p_monto > 100000000 then return jsonb_build_object('ok', false, 'error', 'Indica el monto que pagaste.'); end if;
  if p_fecha is null or p_fecha > v_hoy or p_fecha < v_hoy - 60 then return jsonb_build_object('ok', false, 'error', 'Indica la fecha en que pagaste.'); end if;
  insert into reservar_limites (ip, tipo) values (v_ip, 'pago');
  update ordenes set pago_informado = jsonb_build_object('monto', round(p_monto), 'fecha', p_fecha, 'medio', left(coalesce(limpiar_marcado(p_medio), ''), 40),
                                                          'comentario', nullif(left(btrim(coalesce(limpiar_marcado(p_comentario), '')), 300), ''), 'en', now()),
                     cobranza_pausa_hasta = now() + interval '4 days'
   where id = o.id;
  begin
    insert into notificaciones (tipo, titulo, detalle, url, ref_id)
    values ('pago_informado', '💳 Un cliente avisa que pagó · ' || _num_doc('OT', o.numero),
            coalesce((select nombre from clientes where id = o.cliente_id), 'Cliente') || ' dice que pagó ' || _fmt_pesos(round(p_monto))
              || ' el ' || to_char(p_fecha, 'DD-MM') || coalesce(' por ' || nullif(p_medio, ''), '') || '. Revisa tu cuenta y regístralo en la OT (los avisos se pausaron 4 días).',
            'ordenes.html?id=' || o.id, o.id);
  exception when others then null;
  end;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function pago_informar(text, numeric, date, text, text) to anon, authenticated;

-- 8) Botón del correo para el link de pago (mismo texto que layout.js → BOTONES_CORREO)
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
              when p_url like '%/pago.html%convenio=1%' then '🤝 Proponer un convenio de pago'
              when p_url like '%/pago.html%' then '💳 Ver mi saldo y cómo pagar'
              when p_url like '%/reservar.html%' then '📅 Reservar hora'
              when p_url like '%/club.html%' then '🎁 Compartir mi código'
              else 'Abrir enlace' end
      || '</a></td></tr></table>'
$$;

-- 9) Envío cada hora (en punto). El trabajo de recordatorios de cotizaciones sigue a los :05.
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'autonova-cobranza';
  perform cron.schedule('autonova-cobranza', '0 * * * *', 'select public.cobranza_automatica()');
exception when others then
  raise notice 'No se pudo programar la cobranza automática: %', sqlerrm;
end $$;

-- Verificación: debe decir «ok»
select case when to_regprocedure('cobranza_automatica()') is not null
             and to_regprocedure('pago_info(text)') is not null
             and exists (select 1 from information_schema.columns where table_name = 'ordenes' and column_name = 'token_pago')
             and exists (select 1 from cron.job where jobname = 'autonova-cobranza')
            then 'ok' else 'revisar' end as v79,
       (select count(*) from cobranza_gestiones) as gestiones_registradas;
