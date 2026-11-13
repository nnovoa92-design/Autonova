-- ============================================================
-- v68 — Club Autonova: condiciones claras
--
--  * El código (de un amigo o un cupón) se informa AL RESERVAR o AL DEJAR EL VEHÍCULO: con la OT lista para
--    retiro, entregada o con pagos registrados, ya no se puede aplicar.
--  * La página pública del Club recibe los días de vigencia del cupón (para mostrar las condiciones exactas).
--  * El correo del premio trae las condiciones completas del cupón.
--
-- Requiere v67. Seguro de correr más de una vez.
-- ============================================================

create or replace function club_info(p_codigo text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cfg jsonb := _club_cfg();
  v_cod text := upper(btrim(coalesce(p_codigo, '')));
  v_ip text := reservar_ip();
  v_taller jsonb;
  r record;
  v_n int;
begin
  -- Datos públicos del taller y el mensaje para compartir (editable en Configuración → Mensajes al cliente)
  select jsonb_build_object('nombre', nombre, 'telefono', telefono, 'instagram', cfg ->> 'instagram',
                            'mensaje_compartir', nullif(btrim(coalesce(correo_plantillas -> 'wa_compartir_codigo' ->> 'texto', '')), ''))
    into v_taller
    from taller_config where id = 1;
  -- Límite por conexión: 60 consultas por hora
  select count(*) into v_n from reservar_limites where ip = v_ip and tipo = 'codigo' and creado_en > now() - interval '1 hour';
  if v_n >= 60 then
    return jsonb_build_object('ok', false, 'error', 'Demasiadas consultas seguidas. Intenta en un rato.', 'taller', v_taller);
  end if;
  insert into reservar_limites (ip, tipo) values (v_ip, 'codigo');

  if coalesce((cfg ->> 'activo')::boolean, true) is false then
    return jsonb_build_object('ok', false, 'error', 'El programa de referidos no está activo por ahora.', 'taller', v_taller);
  end if;
  if length(v_cod) < 4 then
    return jsonb_build_object('ok', false, 'error', 'Escribe el código completo.', 'taller', v_taller);
  end if;

  select codigo_referido, initcap(split_part(btrim(nombre), ' ', 1)) as nombre into r
    from clientes where upper(codigo_referido) = v_cod limit 1;
  if found then
    return jsonb_build_object('ok', true, 'tipo', 'referido', 'codigo', r.codigo_referido, 'nombre', r.nombre,
                              'pct', (cfg ->> 'pct')::numeric, 'tope', (cfg ->> 'tope')::numeric,
                              'premio_dias', (cfg ->> 'premio_dias')::int, 'taller', v_taller);
  end if;

  select codigo, pct, tope, vence, estado into r from cupones where upper(codigo) = v_cod limit 1;
  if found then
    if r.estado <> 'vigente' then
      return jsonb_build_object('ok', false, 'error', 'Ese cupón ya fue usado.', 'taller', v_taller);
    end if;
    if r.vence is not null and r.vence < (now() at time zone 'America/Santiago')::date then
      return jsonb_build_object('ok', false, 'error', 'Ese cupón venció el ' || to_char(r.vence, 'DD-MM-YYYY') || '.', 'taller', v_taller);
    end if;
    return jsonb_build_object('ok', true, 'tipo', 'premio', 'codigo', r.codigo, 'pct', r.pct, 'tope', r.tope,
                              'vence', r.vence, 'premio_dias', (cfg ->> 'premio_dias')::int, 'taller', v_taller);
  end if;

  return jsonb_build_object('ok', false, 'error', 'No encontramos ese código. Revisa que esté bien escrito.', 'taller', v_taller);
end $$;
grant execute on function club_info(text) to anon, authenticated;

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
  if exists (select 1 from ordenes x where x.cliente_id = o.cliente_id and x.id <> o.id
                and x.estado <> 'cancelado' and x.creado_en < o.creado_en) then
    return jsonb_build_object('ok', false, 'error', 'El descuento de referido es para la primera visita y este cliente ya tiene OT anteriores.');
  end if;
  if exists (select 1 from referidos where referido_cliente_id = o.cliente_id and estado <> 'anulado') then
    return jsonb_build_object('ok', false, 'error', 'Este cliente ya usó un código de referido.');
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

create or replace function procesar_referidos() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  cfg taller_config%rowtype;
  club jsonb := _club_cfg();
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_url text; v_firma text; v_contacto text; v_plant jsonb;
  r record; v_total numeric; v_pagado numeric; v_cod text; v_cupon uuid; v_vence date; i int;
  v_vals jsonb; v_asunto text; v_texto text; v_res jsonb; v_tope text;
  v_n int := 0;
begin
  select * into cfg from taller_config where id = 1;
  v_url := rtrim(coalesce(nullif(btrim(cfg.app_url), ''), 'https://autonova.nnovoa92.workers.dev'), '/');
  v_plant := coalesce(cfg.correo_plantillas, '{}'::jsonb);
  v_contacto := concat_ws(' · ', nullif(btrim(cfg.direccion), ''), nullif(btrim(cfg.telefono), ''));
  v_firma := E'Saludos,\n' || coalesce(nullif(btrim(cfg.nombre), ''), 'El taller') || case when v_contacto <> '' then E'\n' || v_contacto else '' end;

  for r in
    select rf.id, rf.referente_id, rf.referido_cliente_id, o.id as orden_id, o.numero as ot_numero, o.con_iva,
           o.descuento_tipo, o.descuento_pct, o.descuento_monto, o.descuento_base,
           ref.nombre as ref_nombre, ref.email as ref_email, ref.codigo_referido as ref_codigo,
           initcap(split_part(btrim(coalesce(cl.nombre, 'Tu amigo')), ' ', 1)) as amigo,
           coalesce((select sum(i.cantidad * i.precio_unitario) from orden_items i where i.orden_id = o.id), 0) as subtotal,
           coalesce((select sum(i.cantidad * i.precio_unitario) from orden_items i where i.orden_id = o.id
                      and (case when i.tipo = 'otro' and coalesce(i.tipo_otro, '') <> '' then i.tipo_otro else i.tipo end) = 'mano_obra'), 0) as subtotal_mo,
           coalesce((select sum(monto) from pagos where orden_id = o.id), 0)
             + coalesce((select sum(monto) from abonos where orden_id = o.id), 0) as pagado
      from referidos rf
      join ordenes o on o.id = rf.orden_id
      join clientes ref on ref.id = rf.referente_id
      left join clientes cl on cl.id = rf.referido_cliente_id
     where rf.estado = 'pendiente' and o.estado = 'entregado'
  loop
    v_total := _total_documento(r.subtotal, r.subtotal_mo, r.descuento_tipo, r.descuento_pct, r.descuento_monto,
                                r.descuento_base, r.con_iva, cfg.iva_pct);
    continue when v_total <= 0 or r.pagado < v_total - 1;

    -- Cupón personal para quien recomendó
    i := 0;
    loop
      i := i + 1;
      v_cod := 'PREMIO-' || _codigo_aleatorio(5);
      exit when _codigo_libre(v_cod) or i > 20;
    end loop;
    v_vence := v_hoy + coalesce((club ->> 'premio_dias')::int, 90);
    insert into cupones (codigo, cliente_id, tipo, pct, tope, vence, referido_id)
    values (v_cod, r.referente_id, 'premio_referido', (club ->> 'pct')::numeric, (club ->> 'tope')::numeric, v_vence, r.id)
    returning id into v_cupon;
    update referidos set estado = 'premiado', cupon_id = v_cupon, premiado_en = now() where id = r.id;
    v_n := v_n + 1;

    insert into notificaciones (tipo, titulo, detalle, url)
    values ('premio_referido',
            '🎁 ' || coalesce(r.ref_nombre, 'Un cliente') || ' ganó un cupón de ' || (club ->> 'pct') || '%',
            'Su referido ' || r.amigo || ' pagó la ' || _num_doc('OT', r.ot_numero) || '. Cupón ' || v_cod
              || ' (vence el ' || to_char(v_vence, 'DD-MM-YY') || ')'
              || case when coalesce(r.ref_email, '') !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$' then ' — no tiene correo: avísale por WhatsApp desde Referidos.' else '.' end,
            'referidos.html?codigo=' || v_cod);

    -- Correo al cliente que recomendó (si tiene correo, hay envío configurado y el aviso está activo)
    continue when coalesce(r.ref_email, '') !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$'
              or coalesce(btrim(cfg.correo_script_url), '') = '' or coalesce(btrim(cfg.correo_script_clave), '') = ''
              or coalesce(cfg.correo_eventos ->> 'premio_referido', '') = 'false';
    v_tope := case when coalesce((club ->> 'tope')::numeric, 0) > 0 then ' (máximo ' || _fmt_pesos((club ->> 'tope')::numeric) || ')' else '' end;
    v_vals := jsonb_build_object(
      'nombre', r.ref_nombre,
      'referido', r.amigo,
      'descuento', (club ->> 'pct') || '%',
      'tope_texto', v_tope,
      'cupon', v_cod,
      'vence', to_char(v_vence, 'DD-MM-YYYY'),
      'codigo', r.ref_codigo,
      'link_reserva', v_url || '/reservar.html?codigo=' || v_cod,
      'link_compartir', v_url || '/club.html?c=' || r.ref_codigo || '&compartir=1',
      'taller', coalesce(cfg.nombre, 'el taller'),
      'firma', v_firma);
    -- Mismo texto por defecto que layout.js (PLANTILLAS_CORREO.premio_referido): si se cambia uno, cambiar el otro
    v_asunto := _rellenar(_plantilla(v_plant, 'premio_referido', 'asunto',
      '🎁 Ganaste un cupón de {descuento} en {taller}'), v_vals);
    v_texto := _rellenar(_plantilla(v_plant, 'premio_referido', 'texto',
      E'Hola {nombre},

¡Gracias por recomendarnos! {referido} ya hizo su servicio con nosotros gracias a ti, así que ganaste un cupón de {descuento} de descuento{tope_texto} para tu próxima visita.

🎟 Tu cupón: {cupon}
📅 Válido hasta el {vence}.

Cómo usarlo: escríbelo al reservar en línea o dilo al dejar tu vehículo (después ya no se puede aplicar).
Reserva aquí: {link_reserva}

Condiciones: es personal e intransferible, se usa una sola vez y va un cupón por orden de trabajo. El descuento es sobre el valor del trabajo sin IVA{tope_texto}, no se acumula con otras promociones, no aplica a bodegaje y no es canjeable por dinero.

Sigue compartiendo tu código {codigo}: por cada amigo que venga ganas un cupón nuevo.
{link_compartir}

{firma}'), v_vals);
    v_res := _enviar_correo_script(cfg.correo_script_url, cfg.correo_script_clave, cfg.nombre, r.ref_email, v_asunto, v_texto);
    if to_regclass('public.correos_enviados') is not null then
      insert into correos_enviados (para, asunto, texto, evento, estado, error, ref_tabla, ref_id, cliente_id)
      values (r.ref_email, v_asunto, v_texto, 'premio_referido', coalesce(v_res ->> 'estado', 'incierto'), v_res ->> 'error',
              'cupones', v_cupon, r.referente_id);
    end if;
    if (v_res ->> 'estado') = 'enviado' then
      update cupones set correo_enviado_en = now() where id = v_cupon;
    end if;
  end loop;
  return jsonb_build_object('estado', 'ok', 'premios', v_n);
end $$;

revoke execute on function procesar_referidos() from public, anon, authenticated;

-- Verificación: debe decir «ok»
select case when pg_get_functiondef('aplicar_codigo_ot(uuid, text)'::regprocedure) like '%al dejar el vehículo%'
             and pg_get_functiondef('club_info(text)'::regprocedure) like '%premio_dias%'
            then 'ok' else 'revisar' end as club_condiciones;
