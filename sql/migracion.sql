-- ============================================================
-- Migración: datos de la app anterior (tabla autonova_data,
-- JSON único) hacia el esquema nuevo del taller.
--
-- EJECUTAR DESPUÉS de schema.sql, en el SQL Editor de Supabase.
-- Es seguro correrlo más de una vez: solo migra la primera vez.
--
-- Qué migra:
--   cfg   -> taller_config (nombre, rut, dirección, teléfono, email)
--   v[]   -> clientes + vehiculos (directorio)
--   cot[] -> clientes + vehiculos faltantes + cotizaciones + items
--            · estados en curso (ingresado/proceso/espera/listo/
--              entregado) generan además su orden de trabajo
--            · los abonos se registran como pagos
-- También elimina los clientes de demostración del schema.
-- Las inspecciones (insp[]) no se migran (no existe módulo aún).
-- ============================================================

create table if not exists _migracion_done (
  id integer primary key,
  fecha timestamptz not null default now()
);

do $$
declare
  raw jsonb;
  vj jsonb;
  cj jsonb;
  ij jsonb;
  v_cliente uuid;
  v_vehiculo uuid;
  v_cot uuid;
  v_orden uuid;
  v_nombre text;
  v_rut text;
  v_pat text;
  v_estado text;
  v_resp text;
  v_estado_cot text;
  v_estado_ot text;
  v_fecha date;
  v_abono numeric;
  v_desc_monto numeric;
  v_notas text;
  idx integer;
begin
  if exists (select 1 from _migracion_done) then
    raise notice 'La migración ya fue ejecutada. No se hace nada.';
    return;
  end if;

  select (data)::jsonb into raw from autonova_data where id = 'autonova_main';
  if raw is null then
    raise notice 'No se encontró autonova_data: no hay datos que migrar.';
    return;
  end if;

  -- ----------------------------------------------------------
  -- 0) Eliminar datos de demostración del schema
  --    (cascada: borra también sus vehículos, cotizaciones,
  --     órdenes y pagos de ejemplo)
  -- ----------------------------------------------------------
  delete from clientes where rut in
    ('12.345.678-9','9.876.543-2','77.111.222-3','15.222.333-4','11.444.555-6');

  -- ----------------------------------------------------------
  -- 1) Configuración del taller
  -- ----------------------------------------------------------
  update taller_config set
    nombre    = coalesce(nullif(raw->'cfg'->>'nombre',''), nombre),
    rut       = coalesce(nullif(raw->'cfg'->>'rut',''), rut),
    direccion = coalesce(nullif(raw->'cfg'->>'dir',''), direccion),
    telefono  = coalesce(nullif(raw->'cfg'->>'tel',''), telefono),
    email     = coalesce(nullif(raw->'cfg'->>'email',''), email)
  where id = 1;

  -- ----------------------------------------------------------
  -- 2) Directorio de vehículos (v[]) -> clientes + vehiculos
  -- ----------------------------------------------------------
  for vj in select * from jsonb_array_elements(coalesce(raw->'v', '[]'::jsonb)) loop
    v_nombre := coalesce(nullif(trim(vj->>'nombre'), ''), 'Sin nombre');
    v_rut := nullif(trim(coalesce(vj->>'rut','')), '');

    v_cliente := null;
    select id into v_cliente from clientes
    where (v_rut is not null and rut = v_rut) or (nombre = v_nombre)
    limit 1;
    if v_cliente is null then
      insert into clientes (nombre, rut, telefono)
      values (v_nombre, v_rut, nullif(trim(coalesce(vj->>'wa','')), ''))
      returning id into v_cliente;
    end if;

    v_pat := upper(replace(coalesce(vj->>'pat',''), ' ', ''));
    if v_pat not in ('', '—', '-') then
      insert into vehiculos (cliente_id, patente, marca, modelo, anio, vin, motor, kilometraje, notas)
      values (
        v_cliente,
        v_pat,
        nullif(trim(coalesce(vj->>'marca','')), ''),
        nullif(trim(coalesce(vj->>'modelo','')), ''),
        nullif(regexp_replace(coalesce(vj->>'anio',''), '\D', '', 'g'), '')::integer,
        nullif(trim(coalesce(vj->>'vin','')), ''),
        nullif(trim(coalesce(vj->>'nmotor','')), ''),
        nullif(regexp_replace(coalesce(vj->>'km',''), '\D', '', 'g'), '')::integer,
        case when nullif(trim(coalesce(vj->>'duenio_legal','')), '') is not null
             then 'Dueño legal: ' || trim(vj->>'duenio_legal') end
      )
      on conflict (patente) do nothing;
    end if;
  end loop;

  -- ----------------------------------------------------------
  -- 3) Cotizaciones (cot[])
  -- ----------------------------------------------------------
  for cj in select * from jsonb_array_elements(coalesce(raw->'cot', '[]'::jsonb)) loop
    v_estado := coalesce(cj->>'estado', 'enviada');
    if v_estado = 'directorio' then continue; end if;  -- entradas solo-directorio

    -- Cliente (buscar o crear)
    v_nombre := coalesce(nullif(trim(cj->>'nombre'), ''), 'Sin nombre');
    v_rut := nullif(trim(coalesce(cj->>'rut','')), '');
    v_cliente := null;
    select id into v_cliente from clientes
    where (v_rut is not null and rut = v_rut) or (nombre = v_nombre)
    limit 1;
    if v_cliente is null then
      insert into clientes (nombre, rut, telefono, email)
      values (v_nombre, v_rut,
        nullif(trim(coalesce(cj->>'wa','')), ''),
        nullif(trim(coalesce(cj->>'email','')), ''))
      returning id into v_cliente;
    end if;

    -- Vehículo (buscar por patente o crear mínimo)
    v_vehiculo := null;
    v_pat := upper(replace(coalesce(cj->>'pat',''), ' ', ''));
    if v_pat not in ('', '—', '-') then
      select id into v_vehiculo from vehiculos where patente = v_pat;
      if v_vehiculo is null then
        insert into vehiculos (cliente_id, patente)
        values (v_cliente, v_pat)
        returning id into v_vehiculo;
      end if;
    end if;

    -- Estado nuevo de la cotización
    v_resp := coalesce(cj->>'respuesta', '');
    v_estado_cot := case
      when v_estado in ('convertida','ingresado','proceso','espera','listo','entregado') then 'convertida'
      when v_resp = 'aceptada' then 'aprobada'
      when v_resp = 'rechazada' then 'rechazada'
      else 'enviada'
    end;

    -- Fecha segura
    v_fecha := case
      when coalesce(cj->>'fecha','') ~ '^\d{4}-\d{2}-\d{2}'
      then substring(cj->>'fecha' from 1 for 10)::date
      else current_date
    end;

    -- Notas (conserva obs y el descuento original si lo había)
    v_desc_monto := coalesce(nullif(regexp_replace(coalesce(cj->>'descuento','0'), '[^0-9.]', '', 'g'), '')::numeric, 0);
    v_notas := nullif(trim(coalesce(cj->>'obs','')), '');
    if v_desc_monto > 0 then
      v_notas := coalesce(v_notas || ' · ', '') || 'Descuento original (app anterior): $' || v_desc_monto::text;
    end if;

    insert into cotizaciones (cliente_id, vehiculo_id, fecha, estado, descuento_pct, notas)
    values (v_cliente, v_vehiculo, v_fecha, v_estado_cot, 0, v_notas)
    returning id into v_cot;

    -- Ítems
    idx := 0;
    for ij in select * from jsonb_array_elements(coalesce(cj->'items', '[]'::jsonb)) loop
      idx := idx + 1;
      insert into cotizacion_items (cotizacion_id, tipo, descripcion, cantidad, precio_unitario, orden)
      values (
        v_cot, 'otro',
        coalesce(nullif(trim(ij->>'desc'), ''), 'Ítem ' || idx::text),
        coalesce(nullif(regexp_replace(coalesce(ij->>'cant','1'), '[^0-9.]', '', 'g'), '')::numeric, 1),
        coalesce(nullif(regexp_replace(coalesce(ij->>'precio','0'), '[^0-9.]', '', 'g'), '')::numeric, 0),
        idx
      );
    end loop;

    -- Trabajos en curso -> orden de trabajo con sus ítems y abono
    if v_estado in ('ingresado','espera','proceso','listo','entregado','convertida') then
      v_estado_ot := case v_estado
        when 'ingresado' then 'recepcion'
        when 'espera' then 'en_proceso'
        when 'proceso' then 'en_proceso'
        when 'listo' then 'listo'
        when 'entregado' then 'entregado'
        else 'recepcion'
      end;

      insert into ordenes (cotizacion_id, cliente_id, vehiculo_id, estado, fecha_ingreso, notas)
      values (v_cot, v_cliente, v_vehiculo, v_estado_ot, v_fecha, v_notas)
      returning id into v_orden;

      insert into orden_items (orden_id, tipo, descripcion, cantidad, precio_unitario, orden)
      select v_orden, tipo, descripcion, cantidad, precio_unitario, orden
      from cotizacion_items where cotizacion_id = v_cot;

      v_abono := coalesce(nullif(regexp_replace(coalesce(cj->>'abono','0'), '[^0-9.]', '', 'g'), '')::numeric, 0);
      if v_abono > 0 then
        insert into pagos (orden_id, cliente_id, monto, metodo_pago, notas)
        values (v_orden, v_cliente, v_abono, 'otro', 'Abono migrado de la app anterior');
      end if;
    end if;
  end loop;

  insert into _migracion_done (id) values (1);
  raise notice 'Migración completada.';
end $$;

-- Resumen de lo migrado
select 'clientes' as tabla, count(*) from clientes
union all select 'vehiculos', count(*) from vehiculos
union all select 'cotizaciones', count(*) from cotizaciones
union all select 'ordenes', count(*) from ordenes
union all select 'pagos', count(*) from pagos;
