-- ============================================================
-- v78 — Criterio de agenda: el servicio tiene que alcanzar a terminar
--
--  * La reserva en línea usa la DURACIÓN DEL SERVICIO (horas del catálogo), no solo el bloque de 1 hora:
--    - si se cruza con otra reserva o un bloqueo ese día, esa hora no se ofrece;
--    - si pasa del cierre: en el taller o con retiro, el vehículo QUEDA EN EL TALLER y se le muestra
--      la devolución estimada (el resto del trabajo sigue el próximo día hábil); a domicilio (en terreno)
--      no se ofrece esa hora;
--    - si el próximo día hábil está bloqueado todo el día, o su mañana ya está tomada, esa hora no se ofrece.
--  * La cita guarda queda_taller, continua_desde y devolucion_estimada; la continuación del día siguiente
--    también ocupa esas horas para nuevas reservas.
--  * Tú confirmas: en la Agenda decides si queda en el taller (con la devolución estimada que le llega al
--    cliente) o, si no puede quedar, liberas la hora y le pides que elija otro día (con sus datos guardados).
--  * El link del correo también sirve para elegir otro día cuando el taller canceló pidiendo reagendar.
--
-- Seguro de correr más de una vez.
-- ============================================================

alter table citas add column if not exists queda_taller boolean not null default false;
alter table citas add column if not exists continua_desde timestamptz;
alter table citas add column if not exists devolucion_estimada timestamptz;

-- 1) Duración de un servicio para la agenda (horas del catálogo; mínimo un bloque)
create or replace function _duracion_servicio(p_trabajo_id uuid) returns int
language sql stable security definer set search_path = public as $$
  select greatest(coalesce((select slot_min from taller_config where id = 1), 60),
                  coalesce((select round(horas_estimadas * 60)::int from trabajos where id = p_trabajo_id), 0));
$$;
revoke execute on function _duracion_servicio(uuid) from public, anon, authenticated;

-- 2) ¿Está ocupado un tramo de un día? (bloqueos por horas, citas con su traslado y vehículos que siguen del día anterior)
create or replace function _agenda_ocupada(p_fecha date, p_ini int, p_fin int) returns boolean
language sql stable security definer set search_path = public as $$
  with r as (select (p_fecha::timestamp + make_interval(mins => p_ini)) at time zone 'America/Santiago' as d,
                    (p_fecha::timestamp + make_interval(mins => p_fin)) at time zone 'America/Santiago' as h)
  select exists (select 1 from bloqueos_agenda b
                  where p_fecha between b.fecha_desde and b.fecha_hasta and b.hora_desde is not null
                    and p_ini < hhmm_a_min(b.hora_hasta) and hhmm_a_min(b.hora_desde) < p_fin)
      or exists (select 1 from citas c, r
                  where c.estado <> 'cancelado' and c.bloquea
                    and r.d < c.fecha_hora + make_interval(mins => c.duracion_min + coalesce(c.margen_despues_min, 0))
                    and c.fecha_hora - make_interval(mins => coalesce(c.margen_antes_min, 0)) < r.h)
      or exists (select 1 from citas c, r
                  where c.estado <> 'cancelado' and c.bloquea and c.queda_taller
                    and c.continua_desde is not null and c.devolucion_estimada is not null
                    and r.d < c.devolucion_estimada and c.continua_desde < r.h);
$$;
revoke execute on function _agenda_ocupada(date, int, int) from public, anon, authenticated;

-- 3) Criterio de una hora para un servicio: ¿alcanza?, ¿queda en el taller?, ¿hasta cuándo?
--    p_modalidad: 'taller' | 'terreno' (a domicilio en terreno) | 'retiro'
create or replace function _criterio_slot(p_fecha date, p_hora text, p_dur int, p_modalidad text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_h horario_atencion%rowtype; v_h2 horario_atencion%rowtype;
  v_ini int := hhmm_a_min(p_hora);
  v_dur int := greatest(coalesce(p_dur, 0), 1);
  v_fin int; v_cierre int; v_resto int; v_d date; v_ap int; v_ci int; v_hasta int;
  v_cont timestamptz; v_dev timestamptz;
  v_mod text := lower(coalesce(p_modalidad, 'taller'));
  v_txt text;
begin
  select * into v_h from horario_atencion where dow = extract(dow from p_fecha)::int;
  if not found or not v_h.abierto then return jsonb_build_object('ok', false, 'error', 'Ese día el taller no atiende.'); end if;
  v_cierre := hhmm_a_min(v_h.cierre);
  v_fin := v_ini + v_dur;
  -- La colación interrumpe el trabajo: el término se corre
  if v_h.pausa_desde is not null and v_h.pausa_hasta is not null
     and v_ini < hhmm_a_min(v_h.pausa_desde) and hhmm_a_min(v_h.pausa_desde) < v_fin then
    v_fin := v_fin + (hhmm_a_min(v_h.pausa_hasta) - hhmm_a_min(v_h.pausa_desde));
  end if;
  v_txt := 'Este servicio dura aprox. ' || regexp_replace(replace(to_char(v_dur / 60.0, 'FM990.9'), '.', ','), ',$', '') || ' h';

  -- Lo que se hace ese mismo día no puede cruzarse con otra reserva ni con un bloqueo
  if least(v_fin, v_cierre) > v_ini and _agenda_ocupada(p_fecha, v_ini, least(v_fin, v_cierre)) then
    return jsonb_build_object('ok', false, 'error', v_txt || ' y a esa hora se cruza con otra reserva. Elige otra hora.');
  end if;
  if v_fin <= v_cierre then
    return jsonb_build_object('ok', true, 'queda', false,
                              'termino', (p_fecha::timestamp + make_interval(mins => v_fin)) at time zone 'America/Santiago');
  end if;
  if v_mod = 'terreno' then
    return jsonb_build_object('ok', false, 'error', v_txt || ' y a domicilio no alcanza a terminar antes de las ' || v_h.cierre || '. Elige una hora más temprano.');
  end if;

  -- Pasa del cierre: el vehículo queda en el taller y el resto se hace el próximo día hábil
  v_resto := v_fin - v_cierre;
  v_d := p_fecha;
  for i in 1 .. 14 loop
    v_d := v_d + 1;
    select * into v_h2 from horario_atencion where dow = extract(dow from v_d)::int;
    if not found or not v_h2.abierto then continue; end if;
    if exists (select 1 from bloqueos_agenda b where v_d between b.fecha_desde and b.fecha_hasta and b.hora_desde is null) then
      return jsonb_build_object('ok', false, 'error', v_txt || ': tu vehículo tendría que quedar en el taller y el ' || to_char(v_d, 'DD-MM')
                                || ' el taller no atiende. Elige una hora más temprano u otro día.');
    end if;
    v_ap := hhmm_a_min(v_h2.apertura); v_ci := hhmm_a_min(v_h2.cierre);
    if v_cont is null then v_cont := (v_d::timestamp + make_interval(mins => v_ap)) at time zone 'America/Santiago'; end if;
    v_hasta := least(v_ap + v_resto, v_ci);
    if v_h2.pausa_desde is not null and v_h2.pausa_hasta is not null
       and v_ap < hhmm_a_min(v_h2.pausa_desde) and hhmm_a_min(v_h2.pausa_desde) < v_hasta then
      v_hasta := least(v_hasta + (hhmm_a_min(v_h2.pausa_hasta) - hhmm_a_min(v_h2.pausa_desde)), v_ci);
    end if;
    if _agenda_ocupada(v_d, v_ap, v_hasta) then
      return jsonb_build_object('ok', false, 'error', v_txt || ': tu vehículo tendría que quedar en el taller y el ' || to_char(v_d, 'DD-MM')
                                || ' a primera hora ya está tomado. Elige una hora más temprano u otro día.');
    end if;
    v_resto := v_resto - (v_hasta - v_ap)
               + case when v_h2.pausa_desde is not null and v_h2.pausa_hasta is not null
                       and v_ap < hhmm_a_min(v_h2.pausa_desde) and hhmm_a_min(v_h2.pausa_desde) < v_hasta
                      then hhmm_a_min(v_h2.pausa_hasta) - hhmm_a_min(v_h2.pausa_desde) else 0 end;
    if v_resto <= 0 then
      v_dev := (v_d::timestamp + make_interval(mins => v_hasta)) at time zone 'America/Santiago';
      return jsonb_build_object('ok', true, 'queda', true, 'continua', v_cont, 'devolucion', v_dev);
    end if;
  end loop;
  return jsonb_build_object('ok', false, 'error', v_txt || ' y no encontramos días hábiles para terminarlo. Llámanos y lo coordinamos.');
end $$;
revoke execute on function _criterio_slot(date, text, int, text) from public, anon, authenticated;

-- 4) Horas libres de un día: igual que v57, más los vehículos que siguen del día anterior
create or replace function agenda_slots_libres(p_fecha date, p_margen int default 0)
returns text[]
language plpgsql stable security definer set search_path = public as $$
declare
  v_h horario_atencion%rowtype;
  v_slot int; v_m int; v_ini int; v_fin int;
  v_margen int := greatest(coalesce(p_margen, 0), 0);
  v_ahora timestamp := (now() at time zone 'America/Santiago');
  v_desde timestamptz; v_hasta timestamptz;
  v_res text[] := '{}';
begin
  select * into v_h from horario_atencion where dow = extract(dow from p_fecha)::int;
  if not found or not v_h.abierto then return v_res; end if;
  if exists (select 1 from bloqueos_agenda b
             where p_fecha between b.fecha_desde and b.fecha_hasta and b.hora_desde is null) then
    return v_res;
  end if;
  v_slot := greatest(coalesce((select slot_min from taller_config where id = 1), 60), 5);
  v_ini := hhmm_a_min(v_h.apertura);
  v_fin := hhmm_a_min(v_h.cierre);
  v_m := v_ini;
  while v_m < v_fin loop
    v_desde := (p_fecha::timestamp + make_interval(mins => v_m - v_margen)) at time zone 'America/Santiago';
    v_hasta := (p_fecha::timestamp + make_interval(mins => v_m + v_slot + v_margen)) at time zone 'America/Santiago';
    if (p_fecha::timestamp + make_interval(mins => v_m)) > v_ahora
       and not (v_h.pausa_desde is not null and v_h.pausa_hasta is not null
                and v_m < hhmm_a_min(v_h.pausa_hasta) and hhmm_a_min(v_h.pausa_desde) < v_m + v_slot)
       and not exists (select 1 from bloqueos_agenda b
                       where p_fecha between b.fecha_desde and b.fecha_hasta
                         and b.hora_desde is not null
                         and v_m - v_margen < hhmm_a_min(b.hora_hasta) and hhmm_a_min(b.hora_desde) < v_m + v_slot + v_margen)
       and not exists (select 1 from citas c
                       where c.estado <> 'cancelado' and c.bloquea
                         and v_desde < c.fecha_hora + make_interval(mins => c.duracion_min + coalesce(c.margen_despues_min, 0))
                         and c.fecha_hora - make_interval(mins => coalesce(c.margen_antes_min, 0)) < v_hasta)
       -- vehículo que quedó en el taller y sigue en la mañana (v78)
       and not exists (select 1 from citas c
                       where c.estado <> 'cancelado' and c.bloquea and c.queda_taller
                         and c.continua_desde is not null and c.devolucion_estimada is not null
                         and v_desde < c.devolucion_estimada and c.continua_desde < v_hasta)
    then
      v_res := v_res || (lpad((v_m / 60)::text, 2, '0') || ':' || lpad((v_m % 60)::text, 2, '0'));
    end if;
    v_m := v_m + v_slot;
  end loop;
  return v_res;
end $$;
grant execute on function agenda_slots_libres(date, int) to anon, authenticated;

-- 5) Semana para la reserva en línea, con el servicio elegido: solo horas en que alcanza,
--    y las que dejan el vehículo en el taller con su devolución estimada
create or replace function reservar_semana_v2(p_desde date, p_dias int, p_modalidad text, p_trabajo_id uuid, p_domicilio_tipo text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_desde date := p_desde;
  v_n int := least(greatest(coalesce(p_dias, 7), 1), 14);
  v_dom boolean := lower(coalesce(p_modalidad, '')) in ('domicilio', 'terreno', 'retiro');
  v_mod text := case when not v_dom then 'taller'
                     when lower(coalesce(p_domicilio_tipo, p_modalidad, '')) = 'retiro' then 'retiro' else 'terreno' end;
  v_margen int := case when v_dom then greatest(coalesce((select domicilio_margen_min from taller_config where id = 1), 60), 0) else 0 end;
  v_dur int := _duracion_servicio(p_trabajo_id);
  v_d date; v_s text; v_c jsonb; v_slots jsonb; v_quedan jsonb;
  v_res jsonb := '[]'::jsonb;
begin
  if v_desde is null or v_desde < v_hoy then v_desde := v_hoy; end if;
  if v_desde > v_hoy + 90 then v_desde := v_hoy + 90; end if;
  for i in 0 .. v_n - 1 loop
    v_d := v_desde + i;
    v_slots := '[]'::jsonb; v_quedan := '{}'::jsonb;
    foreach v_s in array agenda_slots_libres(v_d, v_margen) loop
      v_c := _criterio_slot(v_d, v_s, v_dur, v_mod);
      if coalesce((v_c ->> 'ok')::boolean, false) then
        v_slots := v_slots || to_jsonb(v_s);
        if coalesce((v_c ->> 'queda')::boolean, false) then
          v_quedan := v_quedan || jsonb_build_object(v_s, to_char((v_c ->> 'devolucion')::timestamptz at time zone 'America/Santiago', 'YYYY-MM-DD"T"HH24:MI'));
        end if;
      end if;
    end loop;
    v_res := v_res || jsonb_build_object('fecha', v_d, 'dow', extract(dow from v_d)::int, 'slots', v_slots, 'quedan', v_quedan);
  end loop;
  return v_res;
end $$;
grant execute on function reservar_semana_v2(date, int, text, uuid, text) to anon, authenticated;

-- 6) Reserva (igual que v72) + criterio: valida que el servicio alcance y guarda si queda en el taller
create or replace function reservar_cita_v5(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha date, p_hora text, p_trabajo_id uuid, p_servicio_otro text, p_notas text,
  p_rut text, p_vehiculo_id uuid, p_marca text, p_modelo text, p_anio integer,
  p_km integer default null, p_motor text default null, p_combustible text default null,
  p_email text default null, p_modalidad text default null, p_direccion text default null,
  p_codigo text default null, p_domicilio_tipo text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_res jsonb; v_info jsonb; v_num bigint; v_pat text; v_ret uuid; v_crit jsonb; v_dur int; v_mod text;
begin
  select trabajo_retiro_id into v_ret from taller_config where id = 1;
  v_mod := case when lower(coalesce(p_modalidad, '')) not in ('domicilio', 'terreno') then 'taller'
                when lower(coalesce(p_domicilio_tipo, '')) = 'retiro' and v_ret is not null then 'retiro' else 'terreno' end;
  v_dur := _duracion_servicio(p_trabajo_id);
  if p_fecha is not null and coalesce(p_hora, '') ~ '^[0-2][0-9]:[0-5][0-9]$' then
    v_crit := _criterio_slot(p_fecha, p_hora, v_dur, v_mod);
    if not coalesce((v_crit ->> 'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'error', coalesce(v_crit ->> 'error', 'Ese horario no está disponible. Elige otro.'));
    end if;
  end if;

  v_res := reservar_cita_v4(p_nombre, p_telefono, p_patente, p_fecha, p_hora, p_trabajo_id, p_servicio_otro, p_notas,
                            p_rut, p_vehiculo_id, p_marca, p_modelo, p_anio, p_km, p_motor, p_combustible,
                            p_email, p_modalidad, p_direccion);
  if not coalesce((v_res ->> 'ok')::boolean, false) then return v_res; end if;
  v_num := (v_res ->> 'numero')::bigint;

  -- Duración del servicio y, si pasa del cierre, el vehículo queda en el taller (a confirmar por el taller)
  update citas set duracion_min = v_dur,
                   queda_taller = coalesce((v_crit ->> 'queda')::boolean, false),
                   continua_desde = case when coalesce((v_crit ->> 'queda')::boolean, false) then (v_crit ->> 'continua')::timestamptz end,
                   devolucion_estimada = case when coalesce((v_crit ->> 'queda')::boolean, false) then (v_crit ->> 'devolucion')::timestamptz end
   where numero = v_num;
  if coalesce((v_crit ->> 'queda')::boolean, false) then
    v_res := v_res || jsonb_build_object('queda', true, 'devolucion',
                        to_char((v_crit ->> 'devolucion')::timestamptz at time zone 'America/Santiago', 'YYYY-MM-DD"T"HH24:MI'));
  end if;

  if v_res ->> 'modalidad' = 'terreno' and v_mod = 'retiro' then
    update citas set modalidad = 'retiro' where numero = v_num;
    v_res := v_res || jsonb_build_object('modalidad', 'retiro', 'domicilio', _valor_trabajo(v_ret));
  end if;

  if nullif(btrim(coalesce(p_codigo, '')), '') is not null then
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
grant execute on function reservar_cita_v5(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer, integer, text, text, text, text, text, text, text) to anon;

-- 7) Link del cliente: también sirve cuando el taller canceló pidiéndole reagendar (hasta 30 días)
create or replace function _cita_devuelta(c citas) returns boolean
language sql stable as $$
  select c.estado = 'cancelado'
     and coalesce(((c.reagendamientos -> -1) ->> 'reagendable')::boolean, false)
     and coalesce(((c.reagendamientos -> -1) ->> 'fecha')::timestamptz, now() - interval '1 year') > now() - interval '30 days';
$$;

create or replace function cita_cliente_info(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c citas%rowtype; v_cli clientes%rowtype; v_veh vehiculos%rowtype; v_cfg taller_config%rowtype;
  v_email text; v_mod text; v_otro text; v_dev boolean;
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
  v_dev := _cita_devuelta(c);
  if c.trabajo_id is null and c.descripcion like 'Otro: %' then v_otro := substr(c.descripcion, 8); end if;
  return jsonb_build_object(
    'ok', true,
    'numero', c.numero,
    'estado', c.estado,
    'puede_modificar', (c.estado in ('pendiente', 'confirmado') and c.fecha_hora > now()) or v_dev,
    'devuelta', v_dev,
    'solo_fecha', v_dev and (c.reagendamientos -> -1) ->> 'motivo' = 'no_queda',
    'motivo_devolucion', case when v_dev then (c.reagendamientos -> -1) ->> 'motivo_cliente' end,
    'fecha', to_char(c.fecha_hora at time zone 'America/Santiago', 'YYYY-MM-DD'),
    'hora', to_char(c.fecha_hora at time zone 'America/Santiago', 'HH24:MI'),
    'queda', c.queda_taller and c.devolucion_estimada is not null,
    'devolucion', case when c.queda_taller then to_char(c.devolucion_estimada at time zone 'America/Santiago', 'YYYY-MM-DD"T"HH24:MI') end,
    'servicio', coalesce((select nombre from trabajos where id = c.trabajo_id), c.descripcion),
    'trabajo_id', c.trabajo_id,
    'servicio_otro', v_otro,
    'modalidad', v_mod,
    'direccion', c.direccion,
    'nombre', split_part(btrim(coalesce(nullif(v_cli.nombre, ''), c.nombre_contacto, 'cliente')), ' ', 1),
    'patente', coalesce(v_veh.patente, c.patente_contacto),
    'vehiculo', nullif(btrim(concat_ws(' ', coalesce(v_veh.marca, c.datos_vehiculo ->> 'marca'), coalesce(v_veh.modelo, c.datos_vehiculo ->> 'modelo'))), ''),
    'correo', case when v_email is null then null else left(v_email, 1) || '•••@' || split_part(v_email, '@', 2) end,
    'codigo', case when c.codigo_nota is null then c.codigo_descuento else null end,
    'taller', jsonb_build_object('nombre', v_cfg.nombre, 'telefono', v_cfg.telefono, 'direccion', v_cfg.direccion)
  );
end $$;
grant execute on function cita_cliente_info(text) to anon, authenticated;

create or replace function cita_cliente_reagendar(
  p_token text, p_fecha date, p_hora text, p_trabajo_id uuid, p_servicio_otro text,
  p_modalidad text, p_domicilio_tipo text, p_direccion text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c citas%rowtype;
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_fh timestamptz;
  v_dev boolean; v_solo boolean;
  v_trab uuid := p_trabajo_id;
  v_otro text := nullif(left(btrim(coalesce(p_servicio_otro, '')), 500), '');
  v_mod text := case when lower(coalesce(p_modalidad, '')) in ('domicilio', 'terreno', 'retiro') then 'terreno' else 'taller' end;
  v_dir text := nullif(left(btrim(coalesce(limpiar_marcado(p_direccion), '')), 200), '');
  v_margen int := 0; v_ret uuid; v_dom jsonb := null; v_crit jsonb; v_dur int;
  v_trab_nombre text; v_precio_fijo numeric; v_precio_desde numeric; v_desc text;
  v_ip text := reservar_ip(); v_n int;
begin
  if p_token is null or length(p_token) < 20 then return jsonb_build_object('ok', false, 'error', 'El link no es válido.'); end if;
  select * into c from citas where token_cliente = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'No encontramos esta reserva.'); end if;
  v_dev := _cita_devuelta(c);
  if not ((c.estado in ('pendiente', 'confirmado') and c.fecha_hora > now()) or v_dev) then
    return jsonb_build_object('ok', false, 'error', 'Esta hora ya no se puede cambiar desde aquí. Escríbenos o llámanos y te ayudamos.');
  end if;
  -- Devuelta porque no podía quedar en el taller: solo cambia el día y la hora (mismo servicio y atención)
  v_solo := v_dev and (c.reagendamientos -> -1) ->> 'motivo' = 'no_queda';
  if v_solo then
    v_trab := c.trabajo_id;
    v_otro := case when c.trabajo_id is null and c.descripcion like 'Otro: %' then substr(c.descripcion, 8) else v_otro end;
    v_mod := case when c.modalidad in ('terreno', 'retiro') then 'terreno' else 'taller' end;
    v_dir := c.direccion;
    p_domicilio_tipo := case when c.modalidad = 'retiro' then 'retiro' else p_domicilio_tipo end;
  end if;

  select count(*) into v_n from reservar_limites where ip = v_ip and tipo = 'reagendar' and creado_en > now() - interval '1 hour';
  if v_n >= 6 then return jsonb_build_object('ok', false, 'error', 'Hiciste varios cambios seguidos. Espera un momento o llama al taller.'); end if;

  if v_trab is null and v_otro is null then return jsonb_build_object('ok', false, 'error', 'Cuéntanos qué servicio necesitas.'); end if;
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

  if v_trab is not null then
    select nombre, precio_fijo, nullif(btrim(coalesce(descripcion, '')), ''),
           (select min((o ->> 'precio')::numeric) from jsonb_array_elements(coalesce(opciones, '[]'::jsonb)) o where (o ->> 'precio') is not null)
      into v_trab_nombre, v_precio_fijo, v_desc, v_precio_desde
      from trabajos where id = v_trab and activo;
  end if;
  if v_trab_nombre is null and v_otro is null then
    return jsonb_build_object('ok', false, 'error', 'Ese servicio ya no está disponible. Elige otro o cuéntanos qué necesitas en «Otro».');
  end if;

  v_fh := ((p_fecha::text || ' ' || p_hora)::timestamp) at time zone 'America/Santiago';
  if not v_dev and v_fh = c.fecha_hora and v_mod = coalesce(c.modalidad, 'taller') and coalesce(v_dir, '') = coalesce(c.direccion, '')
     and v_trab is not distinct from c.trabajo_id and (v_trab_nombre is not null or ('Otro: ' || v_otro) = c.descripcion) then
    return jsonb_build_object('ok', false, 'error', 'No cambiaste nada: elige otro día u hora.');
  end if;
  -- Mismo servicio: se mantiene la duración que fijó el taller; servicio nuevo: la del catálogo
  v_dur := case when v_trab is not distinct from c.trabajo_id and c.duracion_min > 0 then c.duracion_min else _duracion_servicio(v_trab) end;

  -- Su propia hora no cuenta como ocupada mientras se revisa la nueva
  update citas set estado = 'cancelado' where id = c.id;
  if not (p_hora = any (agenda_slots_libres(p_fecha, v_margen))) then
    update citas set estado = c.estado where id = c.id;
    return jsonb_build_object('ok', false, 'error', 'Ese horario ya no está disponible (tomado o cerrado). Elige otro.');
  end if;
  v_crit := _criterio_slot(p_fecha, p_hora, v_dur, v_mod);
  if not coalesce((v_crit ->> 'ok')::boolean, false) then
    update citas set estado = c.estado where id = c.id;
    return jsonb_build_object('ok', false, 'error', coalesce(v_crit ->> 'error', 'Ese horario no está disponible. Elige otro.'));
  end if;

  insert into reservar_limites (ip, tipo) values (v_ip, 'reagendar');
  update citas set
    fecha_hora = v_fh,
    estado = 'pendiente',
    origen = 'online',
    trabajo_id = case when v_trab_nombre is not null then v_trab else null end,
    descripcion = coalesce(v_trab_nombre, 'Otro: ' || v_otro),
    duracion_min = v_dur,
    modalidad = v_mod,
    direccion = case when v_mod in ('terreno', 'retiro') then v_dir else null end,
    margen_antes_min = v_margen, margen_despues_min = v_margen,
    queda_taller = coalesce((v_crit ->> 'queda')::boolean, false),
    continua_desde = case when coalesce((v_crit ->> 'queda')::boolean, false) then (v_crit ->> 'continua')::timestamptz end,
    devolucion_estimada = case when coalesce((v_crit ->> 'queda')::boolean, false) then (v_crit ->> 'devolucion')::timestamptz end,
    reagendamientos = coalesce(c.reagendamientos, '[]'::jsonb) || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'desde', c.fecha_hora, 'hacia', v_fh, 'motivo', 'cliente', 'por', 'cliente',
      'motivo_texto', case when v_dev then 'El cliente eligió otra hora desde su correo (el taller se la había devuelto)'
                           else 'El cliente la cambió desde su correo' end,
      'servicio_antes', case when v_trab is distinct from c.trabajo_id or v_trab_nombre is null then c.descripcion end,
      'modalidad_antes', case when v_mod <> coalesce(c.modalidad, 'taller') then coalesce(c.modalidad, 'taller') end,
      'hora_anterior', 'disponible', 'fecha', now())))
  where id = c.id;

  begin
    insert into notificaciones (tipo, titulo, detalle, url, ref_id)
    values ('cita_reagendada_cliente', '🔁 Un cliente reagendó su hora',
            coalesce(nullif(c.nombre_contacto, ''), 'Cliente') || ' · de ' || to_char(c.fecha_hora at time zone 'America/Santiago', 'DD-MM HH24:MI')
              || ' a ' || to_char(v_fh at time zone 'America/Santiago', 'DD-MM HH24:MI') || ' · ' || coalesce(v_trab_nombre, 'Otro: ' || v_otro)
              || case when coalesce((v_crit ->> 'queda')::boolean, false) then ' · 🌙 queda en el taller' else '' end
              || ' · queda pendiente de confirmar',
            'agenda.html?fecha=' || p_fecha::text, c.id);
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'numero', c.numero, 'servicio', v_trab_nombre,
                            'precio_fijo', v_precio_fijo, 'precio_desde', v_precio_desde, 'descripcion', v_desc,
                            'modalidad', v_mod, 'direccion', case when v_mod in ('terreno', 'retiro') then v_dir end,
                            'domicilio', v_dom,
                            'queda', coalesce((v_crit ->> 'queda')::boolean, false),
                            'devolucion', case when coalesce((v_crit ->> 'queda')::boolean, false)
                                               then to_char((v_crit ->> 'devolucion')::timestamptz at time zone 'America/Santiago', 'YYYY-MM-DD"T"HH24:MI') end);
end $$;
grant execute on function cita_cliente_reagendar(text, date, text, uuid, text, text, text, text) to anon, authenticated;

-- Verificación: debe decir «ok»
select case when exists (select 1 from information_schema.columns where table_name = 'citas' and column_name = 'devolucion_estimada')
             and to_regprocedure('reservar_semana_v2(date, integer, text, uuid, text)') is not null
             and to_regprocedure('_criterio_slot(date, text, integer, text)') is not null
            then 'ok' else 'revisar' end as v78;
