-- ============================================================
-- v72 — Reserva a domicilio: EN TERRENO o CON RETIRO, con sus valores a la vista
--
--  * Al elegir «A domicilio» en la reserva en línea, el cliente elige:
--      🔧 En terreno: el mecánico va a su dirección y trabaja ahí (servicio de Configuración → Atención a domicilio).
--      🚚 Retiro y entrega: retiramos el vehículo, se trabaja en el taller y se devuelve (servicio nuevo en la misma sección).
--    Los dos valores se muestran apenas elige «A domicilio» (antes se informaban recién con la reserva hecha).
--  * La cita queda como «retiro» o «terreno» (la agenda ya los distingue) y la OT suma el servicio que corresponde.
--
-- Requiere v71. Seguro de correr más de una vez.
-- ============================================================

alter table taller_config add column if not exists trabajo_retiro_id uuid references trabajos(id) on delete set null;

-- Valor neto de un servicio del catálogo (igual que domicilio_valor de v57)
create or replace function _valor_trabajo(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when t.id is null then null else jsonb_build_object(
    'nombre', t.nombre,
    'descripcion', nullif(btrim(coalesce(t.descripcion, '')), ''),
    'valor', case
      when jsonb_typeof(t.opciones) = 'array' and jsonb_array_length(t.opciones) > 0 then
        (select min(nullif(o ->> 'precio', '')::numeric) from jsonb_array_elements(t.opciones) o)
      when t.precio_fijo is not null then t.precio_fijo
      when t.horas_estimadas > 0 and coalesce(cfg.valor_hora, 0) > 0 then round(t.horas_estimadas * cfg.valor_hora)
      else null end,
    'desde', (jsonb_typeof(t.opciones) = 'array' and jsonb_array_length(t.opciones) > 0)
  ) end
  from taller_config cfg
  left join trabajos t on t.id = p_id and t.activo
  where cfg.id = 1;
$$;
revoke execute on function _valor_trabajo(uuid) from public, anon, authenticated;

-- Para la reserva en línea: solo los valores de estas dos atenciones (el resto del catálogo sigue sin precios públicos)
create or replace function domicilio_opciones() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('terreno', _valor_trabajo(trabajo_domicilio_id), 'retiro', _valor_trabajo(trabajo_retiro_id))
    from taller_config where id = 1;
$$;
grant execute on function domicilio_opciones() to anon, authenticated;

-- Reserva con código y tipo de atención a domicilio (reemplaza a la versión de v69)
drop function if exists reservar_cita_v5(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer, integer, text, text, text, text, text, text);
create or replace function reservar_cita_v5(
  p_nombre text, p_telefono text, p_patente text,
  p_fecha date, p_hora text, p_trabajo_id uuid, p_servicio_otro text, p_notas text,
  p_rut text, p_vehiculo_id uuid, p_marca text, p_modelo text, p_anio integer,
  p_km integer default null, p_motor text default null, p_combustible text default null,
  p_email text default null, p_modalidad text default null, p_direccion text default null,
  p_codigo text default null, p_domicilio_tipo text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_res jsonb; v_info jsonb; v_num bigint; v_pat text; v_ret uuid;
begin
  v_res := reservar_cita_v4(p_nombre, p_telefono, p_patente, p_fecha, p_hora, p_trabajo_id, p_servicio_otro, p_notas,
                            p_rut, p_vehiculo_id, p_marca, p_modelo, p_anio, p_km, p_motor, p_combustible,
                            p_email, p_modalidad, p_direccion);
  if not coalesce((v_res ->> 'ok')::boolean, false) then return v_res; end if;
  v_num := (v_res ->> 'numero')::bigint;

  -- A domicilio con retiro: la cita queda como «retiro» y el valor es el del servicio de retiro y entrega
  if v_res ->> 'modalidad' = 'terreno' and lower(coalesce(p_domicilio_tipo, '')) = 'retiro' then
    select trabajo_retiro_id into v_ret from taller_config where id = 1;
    if v_ret is not null then
      update citas set modalidad = 'retiro' where numero = v_num;
      v_res := v_res || jsonb_build_object('modalidad', 'retiro', 'domicilio', _valor_trabajo(v_ret));
    end if;
  end if;

  -- Código del Club (igual que v69)
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

-- Verificación: debe decir «ok»
select case when to_regprocedure('domicilio_opciones()') is not null
             and to_regprocedure('reservar_cita_v5(text, text, text, date, text, uuid, text, text, text, uuid, text, text, integer, integer, text, text, text, text, text, text, text)') is not null
            then 'ok' else 'revisar' end as v72;
