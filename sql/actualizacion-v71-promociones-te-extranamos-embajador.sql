-- ============================================================
-- v71 — Club Autonova, fase 3: promociones para captar clientes
--
--  * PROMOCIONES Y ALIANZAS: códigos que creas tú en Club Autonova (ej. INSTA10 para Instagram, FLOTA-UBER para
--    una alianza), con %, tope, fechas, cupos, «solo clientes nuevos» y «una vez por cliente». Se usan igual que
--    los demás códigos (en la reserva en línea o en la OT) y cada uno muestra cuántos clientes y ventas trajo.
--  * TE EXTRAÑAMOS: a los clientes que no vienen hace X meses les llega un correo con un cupón personal de regreso.
--    Sale en tandas diarias (por defecto 20 al día) para no pasar el límite diario de Gmail. Parte APAGADO:
--    se enciende en Configuración → Club Autonova.
--  * EMBAJADOR: cada 3 amigos que traiga un cliente, su cupón de premio es mayor (por defecto 30%, máx. $60.000).
--
-- Requiere v70. Seguro de correr más de una vez.
-- ============================================================

-- ---------- Configuración (mismos valores por defecto que layout.js → CLUB_POR_DEFECTO) ----------
create or replace function _club_cfg() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('activo', true, 'pct', 15, 'tope', 30000, 'premio_dias', 90, 'instagram', '_autonova_',
                            'embajador', jsonb_build_object('cada', 3, 'pct', 30, 'tope', 60000),
                            'te_extranamos', jsonb_build_object('activo', false, 'meses', 6, 'pct', 10, 'tope', 20000, 'dias', 30, 'por_dia', 20))
         || coalesce((select club from taller_config where id = 1), '{}'::jsonb)
$$;
revoke execute on function _club_cfg() from public, anon, authenticated;

-- ---------- Promociones y alianzas ----------
create table if not exists promociones (
  id uuid primary key default uuid_generate_v4(),
  codigo text not null,
  nombre text not null,
  tipo text not null default 'campana' check (tipo in ('campana', 'alianza')),
  canal text,                                     -- instagram, facebook, volante, alianza, otro
  pct numeric(5,2) not null check (pct > 0 and pct <= 100),
  tope numeric(12,0),
  desde date,
  hasta date,
  max_usos int check (max_usos is null or max_usos > 0),
  solo_nuevos boolean not null default false,
  un_uso_por_cliente boolean not null default true,
  activa boolean not null default true,
  notas text,
  creado_en timestamptz not null default now()
);
create unique index if not exists idx_promociones_codigo on promociones (upper(codigo));
alter table promociones enable row level security;
drop policy if exists "Acceso solo usuarios autorizados" on promociones;
create policy "Acceso solo usuarios autorizados" on promociones for all using (es_autorizado()) with check (es_autorizado());

-- Un código nuevo (de cliente o cupón) tampoco puede chocar con una promoción
create or replace function _codigo_libre(p_codigo text) returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from clientes where upper(codigo_referido) = upper(p_codigo))
     and not exists (select 1 from cupones where upper(codigo) = upper(p_codigo))
     and not exists (select 1 from promociones where upper(codigo) = upper(p_codigo))
$$;
revoke execute on function _codigo_libre(text) from public, anon, authenticated;

-- Veces que se ha usado (OT no canceladas con ese código)
create or replace function _promo_usos(p_codigo text) returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from ordenes
   where codigo_tipo = 'promo' and upper(codigo_descuento) = upper(p_codigo) and estado <> 'cancelado'
$$;
revoke execute on function _promo_usos(text) from public, anon, authenticated;

-- ¿Se puede usar hoy? null = sí; si no, el motivo
create or replace function _promo_error(p_id uuid) returns text language plpgsql stable security definer set search_path = public as $$
declare pr promociones%rowtype; v_hoy date := (now() at time zone 'America/Santiago')::date;
begin
  select * into pr from promociones where id = p_id;
  if not found then return 'No encontramos ese código.'; end if;
  if not pr.activa then return 'Esa promoción no está activa por ahora.'; end if;
  if pr.desde is not null and v_hoy < pr.desde then return 'Esa promoción parte el ' || to_char(pr.desde, 'DD-MM-YYYY') || '.'; end if;
  if pr.hasta is not null and v_hoy > pr.hasta then return 'Esa promoción terminó el ' || to_char(pr.hasta, 'DD-MM-YYYY') || '.'; end if;
  if pr.max_usos is not null and _promo_usos(pr.codigo) >= pr.max_usos then return 'Se acabaron los cupos de esa promoción.'; end if;
  return null;
end $$;
revoke execute on function _promo_error(uuid) from public, anon, authenticated;

-- Personas y vehículos que corresponden a un RUT, teléfono o patente (también si tienen fichas repetidas)
create or replace function _identificar(p_rut text, p_telefono text, p_patente text,
                                        out personas uuid[], out vehs uuid[], out duenos_veh uuid[])
language plpgsql stable security definer set search_path = public as $$
declare
  v_rut text := upper(regexp_replace(coalesce(p_rut, ''), '[^0-9kK]', '', 'g'));
  v_tel text := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  v_pat text := upper(regexp_replace(coalesce(p_patente, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if length(v_rut) < 7 then v_rut := ''; end if;
  v_tel := case when length(v_tel) >= 8 then right(v_tel, 8) else '' end;
  if length(v_pat) < 5 then v_pat := ''; end if;
  select coalesce(array_agg(id), '{}') into personas from clientes
   where (v_rut <> '' and upper(regexp_replace(coalesce(rut, ''), '[^0-9kK]', '', 'g')) = v_rut)
      or (v_tel <> '' and right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 8) = v_tel);
  select coalesce(array_agg(id), '{}'), coalesce(array_agg(cliente_id), '{}') into vehs, duenos_veh from vehiculos
   where v_pat <> '' and upper(regexp_replace(coalesce(patente, ''), '[^A-Za-z0-9]', '', 'g')) = v_pat;
end $$;
revoke execute on function _identificar(text, text, text) from public, anon, authenticated;

-- ¿La promoción le aplica a esta persona? (reserva en línea)
create or replace function _promo_motivo(p_codigo text, p_rut text, p_telefono text, p_patente text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pr promociones%rowtype; idf record;
begin
  select * into pr from promociones where upper(codigo) = upper(p_codigo);
  if not found then return jsonb_build_object('aplica', null); end if;
  if not pr.solo_nuevos and not pr.un_uso_por_cliente then return jsonb_build_object('aplica', true); end if;
  select * into idf from _identificar(p_rut, p_telefono, p_patente);
  if cardinality(idf.personas) = 0 and cardinality(idf.vehs) = 0 then
    if coalesce(p_rut, '') = '' and coalesce(p_telefono, '') = '' and coalesce(p_patente, '') = '' then
      return jsonb_build_object('aplica', null, 'motivo', 'faltan_datos');
    end if;
    return jsonb_build_object('aplica', true);       -- nadie con esos datos: es nuevo
  end if;
  if pr.solo_nuevos and exists (select 1 from ordenes o where o.estado <> 'cancelado'
                                   and (o.cliente_id = any(idf.personas) or o.vehiculo_id = any(idf.vehs))) then
    return jsonb_build_object('aplica', false, 'motivo', 'no_nuevo',
      'mensaje', 'Esta promoción es solo para clientes nuevos y ya te has atendido con nosotros, así que no aplica.',
      'nota', 'No aplica: la promoción es solo para clientes nuevos y ya se atendió antes.');
  end if;
  if pr.un_uso_por_cliente and exists (select 1 from ordenes o where o.estado <> 'cancelado' and o.codigo_tipo = 'promo'
                                          and upper(o.codigo_descuento) = upper(pr.codigo)
                                          and (o.cliente_id = any(idf.personas) or o.vehiculo_id = any(idf.vehs))) then
    return jsonb_build_object('aplica', false, 'motivo', 'ya_uso',
      'mensaje', 'Ya usaste esta promoción: es una vez por persona.',
      'nota', 'No aplica: ya usó esta promoción.');
  end if;
  return jsonb_build_object('aplica', true);
end $$;
revoke execute on function _promo_motivo(text, text, text, text) from public, anon, authenticated;

-- ---------- Validar un código (página del Club, reserva en línea) ----------
create or replace function club_info(p_codigo text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cfg jsonb := _club_cfg();
  v_cod text := upper(btrim(coalesce(p_codigo, '')));
  v_ip text := reservar_ip();
  v_taller jsonb;
  r record;
  pr promociones%rowtype;
  v_n int;
  v_err text;
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

  if length(v_cod) < 4 then
    return jsonb_build_object('ok', false, 'error', 'Escribe el código completo.', 'taller', v_taller);
  end if;

  -- 1) Promoción o alianza
  select * into pr from promociones where upper(codigo) = v_cod;
  if found then
    v_err := _promo_error(pr.id);
    if v_err is not null then return jsonb_build_object('ok', false, 'error', v_err, 'taller', v_taller); end if;
    return jsonb_build_object('ok', true, 'tipo', 'promo', 'codigo', pr.codigo, 'nombre', pr.nombre, 'pct', pr.pct, 'tope', pr.tope,
                              'desde', pr.desde, 'hasta', pr.hasta, 'max_usos', pr.max_usos,
                              'quedan', case when pr.max_usos is null then null else greatest(pr.max_usos - _promo_usos(pr.codigo), 0) end,
                              'solo_nuevos', pr.solo_nuevos, 'un_uso', pr.un_uso_por_cliente, 'taller', v_taller);
  end if;

  -- 2) Código de un cliente (recomendación)
  select codigo_referido, initcap(split_part(btrim(nombre), ' ', 1)) as nombre into r
    from clientes where upper(codigo_referido) = v_cod limit 1;
  if found then
    if coalesce((cfg ->> 'activo')::boolean, true) is false then
      return jsonb_build_object('ok', false, 'error', 'El programa de referidos no está activo por ahora.', 'taller', v_taller);
    end if;
    return jsonb_build_object('ok', true, 'tipo', 'referido', 'codigo', r.codigo_referido, 'nombre', r.nombre,
                              'pct', (cfg ->> 'pct')::numeric, 'tope', (cfg ->> 'tope')::numeric,
                              'premio_dias', (cfg ->> 'premio_dias')::int, 'embajador', cfg -> 'embajador', 'taller', v_taller);
  end if;

  -- 3) Cupón personal (premio, embajador o «te extrañamos»)
  select codigo, pct, tope, vence, estado, tipo into r from cupones where upper(codigo) = v_cod limit 1;
  if found then
    if r.estado <> 'vigente' then
      return jsonb_build_object('ok', false, 'error', 'Ese cupón ya fue usado.', 'taller', v_taller);
    end if;
    if r.vence is not null and r.vence < (now() at time zone 'America/Santiago')::date then
      return jsonb_build_object('ok', false, 'error', 'Ese cupón venció el ' || to_char(r.vence, 'DD-MM-YYYY') || '.', 'taller', v_taller);
    end if;
    return jsonb_build_object('ok', true, 'tipo', 'premio', 'cupon_tipo', r.tipo, 'codigo', r.codigo, 'pct', r.pct, 'tope', r.tope,
                              'vence', r.vence, 'premio_dias', (cfg ->> 'premio_dias')::int, 'taller', v_taller);
  end if;

  return jsonb_build_object('ok', false, 'error', 'No encontramos ese código. Revisa que esté bien escrito.', 'taller', v_taller);
end $$;
grant execute on function club_info(text) to anon, authenticated;

-- Reserva en línea: con los datos de la persona, ¿le aplica? (ahora también las promociones)
create or replace function club_validar_reserva(p_codigo text, p_rut text default null, p_telefono text default null, p_patente text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb; v_dueno uuid;
begin
  v := club_info(p_codigo);
  if not coalesce((v ->> 'ok')::boolean, false) then return v; end if;
  if v ->> 'tipo' = 'promo' then
    return v || _promo_motivo(v ->> 'codigo', p_rut, p_telefono, p_patente);
  end if;
  if v ->> 'tipo' = 'premio' then
    select cliente_id into v_dueno from cupones where upper(codigo) = upper(v ->> 'codigo');
  else
    select id into v_dueno from clientes where upper(codigo_referido) = upper(v ->> 'codigo');
  end if;
  return v || _club_motivo(v ->> 'tipo', v_dueno, p_rut, p_telefono, p_patente);
end $$;
grant execute on function club_validar_reserva(text, text, text, text) to anon, authenticated;

-- ---------- Código en la OT: ahora también promociones ----------
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
  pr promociones%rowtype;
  v_err text;
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

  -- 2) Promoción o alianza (códigos creados en Club Autonova)
  select * into pr from promociones where upper(codigo) = v_cod;
  if found then
    v_err := _promo_error(pr.id);
    if v_err is not null then return jsonb_build_object('ok', false, 'error', v_err); end if;
    select * into c from clientes where id = o.cliente_id;
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
    if pr.solo_nuevos and exists (select 1 from ordenes x where x.id <> o.id and x.estado <> 'cancelado' and x.creado_en < o.creado_en
                                     and (x.cliente_id = any(v_personas) or x.vehiculo_id = any(v_vehs))) then
      return jsonb_build_object('ok', false, 'error', 'No aplica: la promoción ' || pr.nombre || ' es solo para clientes nuevos y este cliente (o este vehículo) ya se atendió antes.');
    end if;
    if pr.un_uso_por_cliente and exists (select 1 from ordenes x where x.id <> o.id and x.estado <> 'cancelado' and x.codigo_tipo = 'promo'
                                            and upper(x.codigo_descuento) = upper(pr.codigo)
                                            and (x.cliente_id = any(v_personas) or x.vehiculo_id = any(v_vehs))) then
      return jsonb_build_object('ok', false, 'error', 'No aplica: este cliente ya usó la promoción ' || pr.nombre || ' (es una vez por cliente).');
    end if;
    update ordenes set codigo_descuento = pr.codigo, codigo_tipo = 'promo', codigo_pct = pr.pct, codigo_tope = pr.tope,
                       descuento_tipo = 'monto', descuento_base = 'total',
                       descuento_monto = round(least(v_sub * pr.pct / 100, coalesce(nullif(pr.tope, 0), v_sub))),
                       descuento_pct = case when v_sub > 0 then round(least(v_sub * pr.pct / 100, coalesce(nullif(pr.tope, 0), v_sub)) / v_sub * 100, 2) else 0 end
     where id = o.id;
    return jsonb_build_object('ok', true, 'tipo', 'promo', 'codigo', pr.codigo, 'nombre', pr.nombre, 'pct', pr.pct, 'tope', pr.tope);
  end if;

  -- 3) Código de un cliente: descuento de referido en la primera visita
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

-- ---------- Premio por referido: cada N amigos, cupón Embajador ----------
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
  v_num_amigo int; v_cada int := greatest(coalesce((_club_cfg() -> 'embajador' ->> 'cada')::int, 0), 0);
  v_tipo text; v_pct numeric; v_tope_n numeric; v_bloque text;
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
    -- EMBAJADOR: cada N amigos (por defecto 3), el cupón es mayor
    select count(*) + 1 into v_num_amigo from referidos where referente_id = r.referente_id and estado = 'premiado';
    if v_cada > 0 and v_num_amigo % v_cada = 0 then
      v_tipo := 'embajador';
      v_pct := coalesce((club -> 'embajador' ->> 'pct')::numeric, (club ->> 'pct')::numeric);
      v_tope_n := (club -> 'embajador' ->> 'tope')::numeric;
      v_bloque := '🏆 ¡Ya son ' || v_num_amigo || E' amigos recomendados! Por ser EMBAJADOR del club, este cupón es más grande.\n\n';
    else
      v_tipo := 'premio_referido';
      v_pct := (club ->> 'pct')::numeric;
      v_tope_n := (club ->> 'tope')::numeric;
      v_bloque := '';
    end if;
    insert into cupones (codigo, cliente_id, tipo, pct, tope, vence, referido_id)
    values (v_cod, r.referente_id, v_tipo, v_pct, v_tope_n, v_vence, r.id)
    returning id into v_cupon;
    update referidos set estado = 'premiado', cupon_id = v_cupon, premiado_en = now() where id = r.id;
    v_n := v_n + 1;

    insert into notificaciones (tipo, titulo, detalle, url)
    values ('premio_referido',
            case when v_tipo = 'embajador' then '🏆 ' else '🎁 ' end || coalesce(r.ref_nombre, 'Un cliente') || ' ganó un cupón de ' || v_pct || '%'
              || case when v_tipo = 'embajador' then ' (Embajador: ' || v_num_amigo || ' amigos)' else '' end,
            'Su referido ' || r.amigo || ' pagó la ' || _num_doc('OT', r.ot_numero) || '. Cupón ' || v_cod
              || ' (vence el ' || to_char(v_vence, 'DD-MM-YY') || ')'
              || case when coalesce(r.ref_email, '') !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$' then ' — no tiene correo: avísale por WhatsApp desde Referidos.' else '.' end,
            'referidos.html?codigo=' || v_cod);

    -- Correo al cliente que recomendó (si tiene correo, hay envío configurado y el aviso está activo)
    continue when coalesce(r.ref_email, '') !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$'
              or coalesce(btrim(cfg.correo_script_url), '') = '' or coalesce(btrim(cfg.correo_script_clave), '') = ''
              or coalesce(cfg.correo_eventos ->> 'premio_referido', '') = 'false';
    v_tope := case when coalesce(v_tope_n, 0) > 0 then ' (máximo ' || _fmt_pesos(v_tope_n) || ')' else '' end;
    v_vals := jsonb_build_object(
      'nombre', r.ref_nombre,
      'referido', r.amigo,
      'descuento', v_pct || '%',
      'tope_texto', v_tope,
      'bloque_embajador', v_bloque,
      'amigos', v_num_amigo,
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

{bloque_embajador}¡Gracias por recomendarnos! {referido} ya hizo su servicio con nosotros gracias a ti, así que ganaste un cupón de {descuento} de descuento{tope_texto} para tu próxima visita.

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

-- ---------- TE EXTRAÑAMOS: cupón de regreso a clientes que no vienen hace X meses ----------
-- Sale entre las 11:00 y las 18:00, en tandas (por defecto 20 al día) para no pasar el límite diario de Gmail.
-- A cada cliente se le envía como máximo una vez cada X meses. No se envía si tiene una cita futura.
create or replace function te_extranamos() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  cfg taller_config%rowtype;
  te jsonb := _club_cfg() -> 'te_extranamos';
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_hora int := extract(hour from (now() at time zone 'America/Santiago'))::int;
  v_meses int := greatest(coalesce((te ->> 'meses')::int, 6), 1);
  v_pct numeric := coalesce((te ->> 'pct')::numeric, 10);
  v_tope numeric := nullif((te ->> 'tope')::numeric, 0);
  v_dias int := greatest(coalesce((te ->> 'dias')::int, 30), 7);
  v_por_dia int := least(greatest(coalesce((te ->> 'por_dia')::int, 20), 1), 60);
  v_hechos int; v_url text; v_plant jsonb; v_firma text; v_contacto text;
  r record; v_cod text; i int; v_cupon uuid; v_vence date; v_vals jsonb; v_asunto text; v_texto text; v_res jsonb;
  v_n int := 0;
begin
  if coalesce((te ->> 'activo')::boolean, false) is false then return jsonb_build_object('estado', 'apagado'); end if;
  if v_hora < 11 or v_hora > 18 then return jsonb_build_object('estado', 'fuera_de_horario'); end if;
  select * into cfg from taller_config where id = 1;
  if coalesce(btrim(cfg.correo_script_url), '') = '' or coalesce(btrim(cfg.correo_script_clave), '') = ''
     or coalesce(cfg.correo_eventos ->> 'te_extranamos', '') = 'false' then
    return jsonb_build_object('estado', 'sin_correo');
  end if;
  select count(*) into v_hechos from cupones where tipo = 'te_extranamos' and (creado_en at time zone 'America/Santiago')::date = v_hoy;
  if v_hechos >= v_por_dia then return jsonb_build_object('estado', 'tanda_de_hoy_lista', 'hoy', v_hechos); end if;

  v_url := rtrim(coalesce(nullif(btrim(cfg.app_url), ''), 'https://autonova.nnovoa92.workers.dev'), '/');
  v_plant := coalesce(cfg.correo_plantillas, '{}'::jsonb);
  v_contacto := concat_ws(' · ', nullif(btrim(cfg.direccion), ''), nullif(btrim(cfg.telefono), ''));
  v_firma := E'Saludos,\n' || coalesce(nullif(btrim(cfg.nombre), ''), 'El taller') || case when v_contacto <> '' then E'\n' || v_contacto else '' end;

  for r in
    with ultima as (
      select o.cliente_id, max(coalesce(o.fecha_entrega, o.creado_en)) as ultima_visita
        from ordenes o
       where o.estado <> 'cancelado' and o.cliente_id is not null
       group by o.cliente_id
    )
    select cl.id, cl.nombre, cl.email, u.ultima_visita,
           (select v.patente || coalesce(' (' || nullif(concat_ws(' ', v.marca, v.modelo), '') || ')', '')
              from vehiculos v where v.cliente_id = cl.id order by v.creado_en desc limit 1) as vehiculo
      from clientes cl
      join ultima u on u.cliente_id = cl.id
     where coalesce(cl.activo, true)
       and coalesce(cl.email, '') ~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$'
       and u.ultima_visita < now() - make_interval(months => v_meses)
       and not exists (select 1 from citas ci where ci.cliente_id = cl.id and ci.estado in ('pendiente', 'confirmado') and ci.fecha_hora > now())
       and not exists (select 1 from cupones cu where cu.cliente_id = cl.id and cu.tipo = 'te_extranamos'
                          and cu.creado_en > now() - make_interval(months => v_meses))
     order by u.ultima_visita desc
     limit v_por_dia - v_hechos
  loop
    i := 0;
    loop
      i := i + 1;
      v_cod := 'VUELVE-' || _codigo_aleatorio(5);
      exit when _codigo_libre(v_cod) or i > 20;
    end loop;
    v_vence := v_hoy + v_dias;
    insert into cupones (codigo, cliente_id, tipo, pct, tope, vence)
    values (v_cod, r.id, 'te_extranamos', v_pct, v_tope, v_vence)
    returning id into v_cupon;

    v_vals := jsonb_build_object(
      'nombre', initcap(split_part(btrim(coalesce(r.nombre, '')), ' ', 1)),
      'vehiculo', case when r.vehiculo is not null then 'tu vehículo ' || r.vehiculo else 'tu vehículo' end,
      'descuento', v_pct || '%',
      'tope_texto', case when v_tope is not null then ' (máximo ' || _fmt_pesos(v_tope) || ')' else '' end,
      'cupon', v_cod,
      'vence', to_char(v_vence, 'DD-MM-YYYY'),
      'link_reserva', v_url || '/reservar.html?codigo=' || v_cod,
      'taller', coalesce(cfg.nombre, 'el taller'),
      'firma', v_firma);
    -- Mismo texto por defecto que layout.js (PLANTILLAS_CORREO.te_extranamos): si se cambia uno, cambiar el otro
    v_asunto := _rellenar(_plantilla(v_plant, 'te_extranamos', 'asunto',
      '💌 {nombre}, te extrañamos: {descuento} de regalo para tu vuelta · {taller}'), v_vals);
    v_texto := _rellenar(_plantilla(v_plant, 'te_extranamos', 'texto',
      E'Hola {nombre},\n\nHace un tiempo que no vemos {vehiculo} por el taller y queremos que siga andando como nuevo.\n\nPor eso te regalamos un cupón de {descuento} de descuento{tope_texto} para tu próxima visita:\n\n🎟 Tu cupón: {cupon}\n📅 Válido hasta el {vence}.\n\nReserva tu hora aquí (el cupón ya va puesto):\n{link_reserva}\n\n¿Toca mantención, revisión de frenos o la revisión técnica? Escríbenos y te ayudamos.\n\nCondiciones: es personal, de un solo uso, sobre el valor del trabajo sin IVA{tope_texto}, no se acumula con otras promociones y se usa al reservar o al dejar tu vehículo.\n\n{firma}'), v_vals);
    v_res := _enviar_correo_script(cfg.correo_script_url, cfg.correo_script_clave, cfg.nombre, r.email, v_asunto, v_texto);
    if to_regclass('public.correos_enviados') is not null then
      insert into correos_enviados (para, asunto, texto, evento, estado, error, ref_tabla, ref_id, cliente_id)
      values (r.email, v_asunto, v_texto, 'te_extranamos', coalesce(v_res ->> 'estado', 'incierto'), v_res ->> 'error',
              'cupones', v_cupon, r.id);
    end if;
    if (v_res ->> 'estado') = 'enviado' then
      update cupones set correo_enviado_en = now() where id = v_cupon;
    end if;
    v_n := v_n + 1;
  end loop;

  if v_n > 0 then
    insert into notificaciones (tipo, titulo, detalle, url)
    values ('te_extranamos', '💌 Te extrañamos: cupón de regreso enviado a ' || v_n || ' cliente' || case when v_n = 1 then '' else 's' end,
            'Clientes que no venían hace más de ' || v_meses || ' meses. Los verás en Club Autonova → Cupones.', 'referidos.html');
  end if;
  return jsonb_build_object('estado', 'ok', 'enviados', v_n);
end $$;
revoke execute on function te_extranamos() from public, anon, authenticated;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'autonova-te-extranamos';
  perform cron.schedule('autonova-te-extranamos', '25 * * * *', 'select public.te_extranamos()');
exception when others then
  raise notice 'No se pudo programar «Te extrañamos»: %', sqlerrm;
end $$;

-- Verificación: tabla de promociones y tarea programada (1)
select to_regclass('public.promociones') is not null as tabla_promociones,
       (select count(*) from cron.job where jobname = 'autonova-te-extranamos') as tarea_te_extranamos;
