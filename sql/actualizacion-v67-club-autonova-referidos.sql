-- ============================================================
-- v67 — Club Autonova: «Recomienda y gana»
--
--  * Cada cliente tiene su código personal (ej. JUAN-4K7). Se crea solo, también para los clientes que ya existen.
--  * Un amigo que llega con ese código tiene 15% de descuento en su primera visita (sobre todo el trabajo, con tope).
--  * Cuando ese amigo PAGA su OT entregada, el cliente que lo recomendó recibe por correo un cupón personal de 15%
--    (código PREMIO-XXXXX, un solo uso, vence en 90 días). Aviso en la campanita.
--  * Porcentaje, tope, días del cupón e Instagram se cambian en Configuración → Club Autonova.
--  * El código se puede escribir al reservar en línea (queda en la cita) o directo en la OT.
--
-- Requiere v64. Seguro de correr más de una vez.
-- ============================================================

-- ---------- Configuración del programa ----------
alter table taller_config add column if not exists club jsonb not null default '{}'::jsonb;

create or replace function _club_cfg() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('activo', true, 'pct', 15, 'tope', 30000, 'premio_dias', 90, 'instagram', '_autonova_')
         || coalesce((select club from taller_config where id = 1), '{}'::jsonb)
$$;

-- ---------- Cupones (premios) y referidos ----------
create table if not exists cupones (
  id uuid primary key default uuid_generate_v4(),
  codigo text not null,
  cliente_id uuid references clientes(id) on delete cascade,      -- dueño: es personal
  tipo text not null default 'premio_referido',
  pct numeric(5,2) not null default 15,
  tope numeric(12,0),
  vence date,
  estado text not null default 'vigente' check (estado in ('vigente', 'canjeado', 'anulado')),
  referido_id uuid,
  orden_canje_id uuid references ordenes(id) on delete set null,
  canjeado_en timestamptz,
  correo_enviado_en timestamptz,
  notas text,
  creado_en timestamptz not null default now()
);
create unique index if not exists idx_cupones_codigo on cupones (upper(codigo));
create index if not exists idx_cupones_cliente on cupones (cliente_id);

create table if not exists referidos (
  id uuid primary key default uuid_generate_v4(),
  codigo text not null,
  referente_id uuid not null references clientes(id) on delete cascade,     -- quien recomendó
  referido_cliente_id uuid references clientes(id) on delete set null,      -- el amigo que llegó
  orden_id uuid references ordenes(id) on delete set null,                  -- su primera OT (con el descuento)
  estado text not null default 'pendiente' check (estado in ('pendiente', 'premiado', 'anulado')),
  cupon_id uuid references cupones(id) on delete set null,
  premiado_en timestamptz,
  creado_en timestamptz not null default now()
);
create index if not exists idx_referidos_referente on referidos (referente_id);
create index if not exists idx_referidos_orden on referidos (orden_id);
create unique index if not exists idx_referidos_un_referido on referidos (referido_cliente_id) where estado <> 'anulado';

do $$
declare t text;
begin
  foreach t in array array['cupones', 'referidos'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "Acceso solo usuarios autorizados" on %I', t);
    execute format('create policy "Acceso solo usuarios autorizados" on %I for all using (es_autorizado()) with check (es_autorizado())', t);
  end loop;
end $$;

-- Código en la cita (reserva en línea) y en la OT (descuento aplicado)
alter table citas add column if not exists codigo_descuento text;
alter table ordenes add column if not exists codigo_descuento text;
alter table ordenes add column if not exists codigo_tipo text;          -- 'referido' | 'premio'
alter table ordenes add column if not exists codigo_pct numeric(5,2);
alter table ordenes add column if not exists codigo_tope numeric(12,0);

-- ---------- Código personal de cada cliente ----------
alter table clientes add column if not exists codigo_referido text;
create unique index if not exists idx_clientes_codigo_referido on clientes (upper(codigo_referido)) where codigo_referido is not null;

-- Letras y números sin los que se confunden (sin 0/O, 1/I/L)
create or replace function _codigo_aleatorio(p_largo int) returns text language sql volatile as $$
  select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '')
    from generate_series(1, p_largo)
$$;

create or replace function _codigo_libre(p_codigo text) returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from clientes where upper(codigo_referido) = upper(p_codigo))
     and not exists (select 1 from cupones where upper(codigo) = upper(p_codigo))
$$;

-- NOMBRE-XXX con el primer nombre (sin tildes), fácil de decir y de escribir
create or replace function _codigo_cliente(p_nombre text) returns text language plpgsql volatile security definer set search_path = public as $$
declare v_pref text; v_cod text; i int := 0;
begin
  v_pref := upper(translate(split_part(btrim(coalesce(p_nombre, '')), ' ', 1), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN'));
  v_pref := left(regexp_replace(v_pref, '[^A-Z]', '', 'g'), 8);
  if length(v_pref) < 2 then v_pref := 'CLUB'; end if;
  loop
    i := i + 1;
    v_cod := v_pref || '-' || _codigo_aleatorio(case when i > 15 then 5 else 3 end);
    exit when _codigo_libre(v_cod) or i > 30;
  end loop;
  return v_cod;
end $$;

create or replace function cliente_codigo_referido() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.codigo_referido is null or btrim(new.codigo_referido) = '' then
    new.codigo_referido := _codigo_cliente(new.nombre);
  end if;
  return new;
end $$;
drop trigger if exists trg_cliente_codigo_referido on clientes;
create trigger trg_cliente_codigo_referido before insert on clientes
  for each row execute function cliente_codigo_referido();

-- Clientes que ya existen: uno por uno (así cada código nuevo ve los anteriores)
do $$
declare r record;
begin
  for r in select id, nombre from clientes where codigo_referido is null order by creado_en loop
    update clientes set codigo_referido = _codigo_cliente(r.nombre) where id = r.id;
  end loop;
end $$;

-- ---------- Página pública del código y reserva con código ----------
-- Valida un código (de cliente o cupón). Para la página club.html y el formulario de reserva.
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
                              'pct', (cfg ->> 'pct')::numeric, 'tope', (cfg ->> 'tope')::numeric, 'taller', v_taller);
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
                              'vence', r.vence, 'taller', v_taller);
  end if;

  return jsonb_build_object('ok', false, 'error', 'No encontramos ese código. Revisa que esté bien escrito.', 'taller', v_taller);
end $$;
grant execute on function club_info(text) to anon, authenticated;

-- Reserva en línea con código: la misma reserva de siempre (v57) y el código queda anotado en la cita
create or replace function reservar_cita_v5(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha date, p_hora text, p_trabajo_id uuid, p_servicio_otro text, p_notas text,
  p_rut text, p_vehiculo_id uuid, p_marca text, p_modelo text, p_anio integer,
  p_km integer default null, p_motor text default null, p_combustible text default null,
  p_email text default null, p_modalidad text default null, p_direccion text default null,
  p_codigo text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_res jsonb; v_cod text;
begin
  v_res := reservar_cita_v4(p_nombre, p_telefono, p_patente, p_fecha, p_hora, p_trabajo_id, p_servicio_otro, p_notas,
                            p_rut, p_vehiculo_id, p_marca, p_modelo, p_anio, p_km, p_motor, p_combustible,
                            p_email, p_modalidad, p_direccion);
  if coalesce((v_res ->> 'ok')::boolean, false) and nullif(btrim(coalesce(p_codigo, '')), '') is not null then
    select codigo_referido into v_cod from clientes where upper(codigo_referido) = upper(btrim(p_codigo)) limit 1;
    if v_cod is null then
      select codigo into v_cod from cupones where upper(codigo) = upper(btrim(p_codigo)) and estado = 'vigente' limit 1;
    end if;
    if v_cod is not null then
      update citas set codigo_descuento = v_cod where numero = (v_res ->> 'numero')::bigint;
      v_res := v_res || jsonb_build_object('codigo', v_cod);
    end if;
  end if;
  return v_res;
end $$;
grant execute on function reservar_cita_v5(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer, integer, text, text, text, text, text, text) to anon;

-- ---------- Aplicar / quitar un código en una OT (desde la app) ----------
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

create or replace function quitar_codigo_ot(p_orden uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o ordenes%rowtype;
begin
  if not es_autorizado() then return jsonb_build_object('ok', false, 'error', 'No autorizado.'); end if;
  select * into o from ordenes where id = p_orden;
  if not found or o.codigo_descuento is null then return jsonb_build_object('ok', true); end if;
  if exists (select 1 from referidos where orden_id = o.id and estado = 'premiado') then
    return jsonb_build_object('ok', false, 'error', 'El premio de este referido ya se entregó: el código no se puede quitar.');
  end if;
  update cupones set estado = 'vigente', orden_canje_id = null, canjeado_en = null
   where orden_canje_id = o.id and estado = 'canjeado';
  update referidos set estado = 'anulado' where orden_id = o.id and estado = 'pendiente';
  update ordenes set codigo_descuento = null, codigo_tipo = null, codigo_pct = null, codigo_tope = null,
                     descuento_tipo = 'pct', descuento_pct = 0, descuento_monto = 0
   where id = o.id;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function quitar_codigo_ot(uuid) from public, anon;
grant execute on function quitar_codigo_ot(uuid) to authenticated;

-- ---------- Premio automático: el referido pagó su OT entregada ----------
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
      E'Hola {nombre},\n\n¡Gracias por recomendarnos! {referido} ya hizo su servicio con nosotros gracias a ti, así que ganaste un cupón de {descuento} de descuento{tope_texto} para tu próxima visita.\n\nTu cupón: {cupon}\nVálido hasta el {vence}. Es personal y se usa una sola vez: escríbelo al reservar o muéstralo al llegar.\nReserva aquí: {link_reserva}\n\nSigue compartiendo tu código {codigo}: cada amigo que venga te da un cupón nuevo.\n{link_compartir}\n\n{firma}'), v_vals);
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
revoke execute on function _codigo_cliente(text) from public, anon, authenticated;
revoke execute on function _codigo_libre(text) from public, anon, authenticated;
revoke execute on function _club_cfg() from public, anon, authenticated;

-- Cada hora (a los 35 minutos): revisa si algún referido ya pagó y entrega el premio
do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'autonova-referidos';
  perform cron.schedule('autonova-referidos', '35 * * * *', 'select public.procesar_referidos()');
exception when others then
  raise notice 'No se pudo programar la revisión de referidos: %', sqlerrm;
end $$;

-- Verificación: clientes con código y tarea programada
select (select count(*) from clientes where codigo_referido is not null) as clientes_con_codigo,
       (select count(*) from clientes where codigo_referido is null) as clientes_sin_codigo,
       (select count(*) from cron.job where jobname = 'autonova-referidos') as tarea_referidos;
