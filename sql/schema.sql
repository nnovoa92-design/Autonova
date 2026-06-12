-- ============================================================
-- Esquema: Autonova — Sistema de Gestión de Taller Mecánico
-- Ejecutar completo en el SQL Editor de Supabase
-- ============================================================

create extension if not exists "uuid-ossp";

-- ------------------------------------------------------------
-- Perfiles de usuario (vinculado a auth.users de Supabase)
-- ------------------------------------------------------------
create table if not exists perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null,
  rol text not null default 'recepcion' check (rol in ('admin', 'mecanico', 'recepcion')),
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Configuración del taller (una sola fila)
-- ------------------------------------------------------------
create table if not exists taller_config (
  id integer primary key default 1 check (id = 1),
  nombre text not null,
  rut text,
  direccion text,
  telefono text,
  email text,
  valor_hora numeric(12,2) not null default 0,  -- valor hora de taller (mano de obra)
  iva_pct numeric(5,2) not null default 19,
  moneda text not null default 'CLP'
);

-- ------------------------------------------------------------
-- Clientes y vehículos
-- ------------------------------------------------------------
create table if not exists clientes (
  id uuid primary key default uuid_generate_v4(),
  nombre text not null,
  rut text unique,
  telefono text,
  email text,
  direccion text,
  notas text,
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

create index if not exists idx_clientes_nombre on clientes (nombre);

create table if not exists vehiculos (
  id uuid primary key default uuid_generate_v4(),
  cliente_id uuid not null references clientes(id) on delete cascade,
  patente text not null unique,
  marca text,
  modelo text,
  anio integer,
  motor text,
  vin text,
  kilometraje integer,
  notas text,
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

create index if not exists idx_vehiculos_cliente on vehiculos (cliente_id);
create index if not exists idx_vehiculos_patente on vehiculos (patente);

-- ------------------------------------------------------------
-- Personal / Mecánicos
-- ------------------------------------------------------------
create table if not exists personal (
  id uuid primary key default uuid_generate_v4(),
  perfil_id uuid references perfiles(id) on delete set null,
  nombre text not null,
  especialidad text,            -- ej: motor, frenos, electricidad
  telefono text,
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Catálogo de trabajos (trabajos precargados / "modelos")
-- ------------------------------------------------------------
create table if not exists categorias_trabajos (
  id uuid primary key default uuid_generate_v4(),
  nombre text not null unique,
  orden integer not null default 0
);

create table if not exists trabajos (
  id uuid primary key default uuid_generate_v4(),
  categoria_id uuid references categorias_trabajos(id) on delete set null,
  nombre text not null,
  descripcion text,
  horas_estimadas numeric(6,2) not null default 1,   -- horas de taller
  precio_fijo numeric(12,2),    -- si es null, el precio = horas_estimadas * valor_hora
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

create index if not exists idx_trabajos_categoria on trabajos (categoria_id);

-- ------------------------------------------------------------
-- Inventario de repuestos
-- ------------------------------------------------------------
create table if not exists repuestos (
  id uuid primary key default uuid_generate_v4(),
  sku text unique,
  nombre text not null,
  marca text,
  ubicacion text,               -- estantería / bodega
  stock_actual numeric(12,2) not null default 0,
  stock_minimo numeric(12,2) not null default 0,
  costo numeric(12,2),          -- costo de compra
  precio_venta numeric(12,2),   -- precio al cliente
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

create table if not exists movimientos_stock (
  id uuid primary key default uuid_generate_v4(),
  repuesto_id uuid not null references repuestos(id) on delete cascade,
  tipo text not null check (tipo in ('entrada', 'salida', 'ajuste')),
  cantidad numeric(12,2) not null,
  motivo text,
  orden_id uuid,                -- referencia blanda a la OT (se agrega FK más abajo)
  fecha timestamptz not null default now()
);

create index if not exists idx_movimientos_repuesto on movimientos_stock (repuesto_id);

-- ------------------------------------------------------------
-- Cotizaciones
-- ------------------------------------------------------------
create table if not exists cotizaciones (
  id uuid primary key default uuid_generate_v4(),
  numero bigserial,
  cliente_id uuid not null references clientes(id) on delete cascade,
  vehiculo_id uuid references vehiculos(id) on delete set null,
  fecha date not null default current_date,
  validez_dias integer not null default 15,
  estado text not null default 'borrador'
    check (estado in ('borrador', 'enviada', 'aprobada', 'rechazada', 'convertida')),
  descuento_pct numeric(5,2) not null default 0,
  notas text,
  creado_en timestamptz not null default now()
);

create index if not exists idx_cotizaciones_cliente on cotizaciones (cliente_id);
create index if not exists idx_cotizaciones_estado on cotizaciones (estado);

create table if not exists cotizacion_items (
  id uuid primary key default uuid_generate_v4(),
  cotizacion_id uuid not null references cotizaciones(id) on delete cascade,
  tipo text not null check (tipo in ('mano_obra', 'repuesto', 'otro')),
  trabajo_id uuid references trabajos(id) on delete set null,
  repuesto_id uuid references repuestos(id) on delete set null,
  descripcion text not null,
  cantidad numeric(10,2) not null default 1,   -- para mano_obra = horas
  precio_unitario numeric(12,2) not null default 0,
  orden integer not null default 0
);

create index if not exists idx_cotizacion_items_cot on cotizacion_items (cotizacion_id);

-- ------------------------------------------------------------
-- Órdenes de trabajo (OT)
-- ------------------------------------------------------------
create table if not exists ordenes (
  id uuid primary key default uuid_generate_v4(),
  numero bigserial,
  cotizacion_id uuid references cotizaciones(id) on delete set null,
  cliente_id uuid not null references clientes(id) on delete cascade,
  vehiculo_id uuid references vehiculos(id) on delete set null,
  estado text not null default 'recepcion'
    check (estado in ('recepcion', 'diagnostico', 'en_proceso', 'listo', 'entregado', 'cancelado')),
  km_ingreso integer,
  fecha_ingreso timestamptz not null default now(),
  fecha_entrega timestamptz,
  diagnostico text,
  notas text,
  creado_en timestamptz not null default now()
);

create index if not exists idx_ordenes_cliente on ordenes (cliente_id);
create index if not exists idx_ordenes_estado on ordenes (estado);

create table if not exists orden_items (
  id uuid primary key default uuid_generate_v4(),
  orden_id uuid not null references ordenes(id) on delete cascade,
  tipo text not null check (tipo in ('mano_obra', 'repuesto', 'otro')),
  trabajo_id uuid references trabajos(id) on delete set null,
  repuesto_id uuid references repuestos(id) on delete set null,
  descripcion text not null,
  cantidad numeric(10,2) not null default 1,
  precio_unitario numeric(12,2) not null default 0,
  orden integer not null default 0
);

create index if not exists idx_orden_items_orden on orden_items (orden_id);

-- Horas reales trabajadas por mecánico en cada OT
create table if not exists registro_horas (
  id uuid primary key default uuid_generate_v4(),
  orden_id uuid not null references ordenes(id) on delete cascade,
  personal_id uuid references personal(id) on delete set null,
  fecha date not null default current_date,
  horas numeric(6,2) not null,
  detalle text
);

create index if not exists idx_registro_horas_orden on registro_horas (orden_id);

-- FK blanda de movimientos de stock hacia órdenes
alter table movimientos_stock
  drop constraint if exists movimientos_stock_orden_fk;
alter table movimientos_stock
  add constraint movimientos_stock_orden_fk
  foreign key (orden_id) references ordenes(id) on delete set null;

-- ------------------------------------------------------------
-- Pagos
-- ------------------------------------------------------------
create table if not exists pagos (
  id uuid primary key default uuid_generate_v4(),
  orden_id uuid references ordenes(id) on delete set null,
  cliente_id uuid not null references clientes(id) on delete cascade,
  monto numeric(12,2) not null,
  metodo_pago text check (metodo_pago in ('efectivo', 'tarjeta_debito', 'tarjeta_credito', 'transferencia', 'otro')),
  fecha timestamptz not null default now(),
  notas text
);

create index if not exists idx_pagos_cliente on pagos (cliente_id);
create index if not exists idx_pagos_fecha on pagos (fecha);

-- ============================================================
-- Seguridad: RLS — cualquier usuario autenticado tiene acceso
-- TODO: refinar por rol (admin / mecanico / recepcion)
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array[
    'perfiles','taller_config','clientes','vehiculos','personal',
    'categorias_trabajos','trabajos','repuestos','movimientos_stock',
    'cotizaciones','cotizacion_items','ordenes','orden_items',
    'registro_horas','pagos'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "Usuarios autenticados acceso total" on %I', t);
    execute format(
      'create policy "Usuarios autenticados acceso total" on %I for all using (auth.role() = ''authenticated'') with check (auth.role() = ''authenticated'')', t
    );
  end loop;
end $$;

-- ============================================================
-- Datos precargados
-- ============================================================

-- Configuración del taller (editar con los datos reales)
insert into taller_config (id, nombre, rut, direccion, telefono, email, valor_hora, iva_pct, moneda)
values (1, 'Autonova', '76.000.000-0', 'Av. Principal 1234, Santiago', '+56 9 0000 0000', 'contacto@autonova.cl', 28000, 19, 'CLP')
on conflict (id) do nothing;

-- Mecánicos
insert into personal (nombre, especialidad) values
  ('Juan Pérez', 'Motor y mantención'),
  ('Carlos Soto', 'Frenos y suspensión'),
  ('Diego Fuentes', 'Electricidad y diagnóstico')
on conflict do nothing;

-- Categorías y catálogo de trabajos precargados
insert into categorias_trabajos (nombre, orden) values
  ('Mantención', 1),
  ('Frenos', 2),
  ('Motor', 3),
  ('Suspensión y dirección', 4),
  ('Eléctrico', 5),
  ('Climatización', 6)
on conflict (nombre) do nothing;

insert into trabajos (categoria_id, nombre, descripcion, horas_estimadas, precio_fijo)
select c.id, t.nombre, t.descripcion, t.horas, t.precio_fijo
from (values
  ('Mantención', 'Cambio de aceite y filtro', 'Incluye drenado, cambio de filtro de aceite y revisión de niveles', 0.5, 15000),
  ('Mantención', 'Mantención 10.000 km', 'Aceite, filtros, revisión general de 30 puntos', 1.5, null),
  ('Mantención', 'Mantención 30.000 km', 'Aceite, filtros aire/combustible/polen, rotación neumáticos', 2.5, null),
  ('Mantención', 'Mantención 60.000 km', 'Mantención mayor: fluidos, bujías, revisión completa', 4, null),
  ('Mantención', 'Cambio de filtro de aire', null, 0.3, 8000),
  ('Mantención', 'Scanner / diagnóstico computarizado', 'Lectura de códigos OBD2 e informe', 1, 25000),
  ('Frenos', 'Cambio de pastillas delanteras', 'Incluye limpieza y lubricación de mordazas', 1, null),
  ('Frenos', 'Cambio de pastillas y discos delanteros', null, 1.5, null),
  ('Frenos', 'Cambio de balatas traseras', null, 1.5, null),
  ('Frenos', 'Sangrado y cambio de líquido de frenos', null, 1, null),
  ('Motor', 'Cambio de correa de distribución', 'Incluye tensor y bomba de agua si corresponde', 5, null),
  ('Motor', 'Cambio de bujías', null, 1, null),
  ('Motor', 'Cambio de correa de accesorios', null, 1, null),
  ('Motor', 'Limpieza de inyectores', 'Por ultrasonido, incluye retiro y prueba', 3, null),
  ('Suspensión y dirección', 'Cambio de amortiguadores (par)', null, 2, null),
  ('Suspensión y dirección', 'Cambio de terminales de dirección', null, 1.5, null),
  ('Suspensión y dirección', 'Alineación y balanceo', null, 1, 35000),
  ('Eléctrico', 'Cambio de batería', 'Incluye prueba de carga del alternador', 0.5, 10000),
  ('Eléctrico', 'Revisión de alternador / partida', null, 1.5, null),
  ('Eléctrico', 'Cambio de ampolletas / luces', null, 0.5, null),
  ('Climatización', 'Carga de aire acondicionado', 'Incluye revisión de fugas', 1.5, 60000),
  ('Climatización', 'Cambio de filtro de polen', null, 0.3, 8000)
) as t(categoria, nombre, descripcion, horas, precio_fijo)
join categorias_trabajos c on c.nombre = t.categoria
on conflict do nothing;

-- Inventario de repuestos
insert into repuestos (sku, nombre, marca, ubicacion, stock_actual, stock_minimo, costo, precio_venta) values
  ('AC-1040', 'Aceite 10W-40 semisintético (litro)', 'Mobil', 'Estante A1', 48, 12, 5500, 9500),
  ('AC-0530', 'Aceite 5W-30 sintético (litro)', 'Shell', 'Estante A1', 36, 12, 7500, 12500),
  ('FO-201', 'Filtro de aceite', 'Mann', 'Estante A2', 25, 8, 3500, 7000),
  ('FA-310', 'Filtro de aire', 'Mann', 'Estante A2', 18, 6, 5000, 9500),
  ('FC-115', 'Filtro de combustible', 'Bosch', 'Estante A2', 10, 4, 7000, 13000),
  ('FP-090', 'Filtro de polen', 'Mann', 'Estante A3', 12, 4, 4500, 9000),
  ('PF-450', 'Pastillas de freno delanteras', 'Brembo', 'Estante B1', 14, 4, 18000, 32000),
  ('DF-280', 'Disco de freno delantero (unidad)', 'Brembo', 'Estante B2', 8, 2, 25000, 45000),
  ('LF-DOT4', 'Líquido de frenos DOT4 (500ml)', 'Bosch', 'Estante B3', 15, 5, 4000, 8000),
  ('BAT-65', 'Batería 65Ah', 'Bosch', 'Bodega', 6, 2, 55000, 89000),
  ('BUJ-IR', 'Bujía iridio (unidad)', 'NGK', 'Estante C1', 32, 8, 6500, 12000),
  ('KD-201', 'Kit correa de distribución', 'Gates', 'Bodega', 4, 1, 65000, 110000),
  ('CA-110', 'Correa de accesorios', 'Gates', 'Estante C2', 7, 2, 12000, 22000),
  ('AM-D2', 'Amortiguador delantero (unidad)', 'KYB', 'Bodega', 6, 2, 45000, 78000),
  ('RF-1L', 'Refrigerante concentrado (litro)', 'Prestone', 'Estante C3', 20, 6, 4500, 9000),
  ('ESC-22', 'Escobillas limpiaparabrisas (par)', 'Bosch', 'Estante C3', 10, 3, 9000, 16500)
on conflict (sku) do nothing;

-- Clientes y vehículos de ejemplo
insert into clientes (nombre, rut, telefono, email, direccion) values
  ('María González', '12.345.678-9', '+56 9 8765 4321', 'maria.gonzalez@gmail.com', 'Los Aromos 567, Maipú'),
  ('Pedro Ramírez', '9.876.543-2', '+56 9 1234 5678', 'pedro.ramirez@gmail.com', 'San Martín 89, Santiago Centro'),
  ('Transportes Andes Ltda.', '77.111.222-3', '+56 2 2345 6789', 'flota@transportesandes.cl', 'Camino a Melipilla km 12'),
  ('Carolina Muñoz', '15.222.333-4', '+56 9 5555 1111', 'caro.munoz@gmail.com', 'Av. Las Condes 4321'),
  ('Jorge Castillo', '11.444.555-6', '+56 9 7777 2222', 'jcastillo@gmail.com', 'Pasaje Los Olmos 23, Puente Alto')
on conflict (rut) do nothing;

insert into vehiculos (cliente_id, patente, marca, modelo, anio, kilometraje)
select c.id, v.patente, v.marca, v.modelo, v.anio, v.km
from (values
  ('12.345.678-9', 'GHXB23', 'Toyota', 'Yaris', 2019, 68000),
  ('9.876.543-2', 'JKLP45', 'Chevrolet', 'Sail', 2021, 35000),
  ('77.111.222-3', 'HTRS78', 'Hyundai', 'H-1', 2018, 142000),
  ('77.111.222-3', 'KWPD12', 'Toyota', 'Hilux', 2020, 98000),
  ('15.222.333-4', 'LMNB90', 'Suzuki', 'Swift', 2022, 21000),
  ('11.444.555-6', 'FGTR56', 'Kia', 'Rio 4', 2017, 89000)
) as v(rut, patente, marca, modelo, anio, km)
join clientes c on c.rut = v.rut
on conflict (patente) do nothing;

-- Cotización de ejemplo (mantención 60.000 km para el Kia Rio de Jorge)
do $$
declare
  v_cliente uuid;
  v_vehiculo uuid;
  v_cot uuid;
  v_orden uuid;
  v_mecanico uuid;
begin
  select id into v_cliente from clientes where rut = '11.444.555-6';
  select id into v_vehiculo from vehiculos where patente = 'FGTR56';
  if v_cliente is null or exists (select 1 from cotizaciones) then return; end if;

  insert into cotizaciones (cliente_id, vehiculo_id, estado, notas)
  values (v_cliente, v_vehiculo, 'enviada', 'Cliente pide confirmar antes del viernes')
  returning id into v_cot;

  insert into cotizacion_items (cotizacion_id, tipo, trabajo_id, repuesto_id, descripcion, cantidad, precio_unitario, orden) values
    (v_cot, 'mano_obra', (select id from trabajos where nombre = 'Mantención 60.000 km'), null, 'Mantención 60.000 km', 4, 28000, 1),
    (v_cot, 'repuesto', null, (select id from repuestos where sku = 'AC-0530'), 'Aceite 5W-30 sintético (litro)', 4, 12500, 2),
    (v_cot, 'repuesto', null, (select id from repuestos where sku = 'FO-201'), 'Filtro de aceite', 1, 7000, 3),
    (v_cot, 'repuesto', null, (select id from repuestos where sku = 'BUJ-IR'), 'Bujía iridio (unidad)', 4, 12000, 4);

  -- OT de ejemplo en proceso (frenos del Yaris de María)
  select id into v_cliente from clientes where rut = '12.345.678-9';
  select id into v_vehiculo from vehiculos where patente = 'GHXB23';
  select id into v_mecanico from personal where nombre = 'Carlos Soto';

  insert into ordenes (cliente_id, vehiculo_id, estado, km_ingreso, diagnostico)
  values (v_cliente, v_vehiculo, 'en_proceso', 68000, 'Ruido al frenar: pastillas delanteras al límite, discos OK')
  returning id into v_orden;

  insert into orden_items (orden_id, tipo, trabajo_id, repuesto_id, descripcion, cantidad, precio_unitario, orden) values
    (v_orden, 'mano_obra', (select id from trabajos where nombre = 'Cambio de pastillas delanteras'), null, 'Cambio de pastillas delanteras', 1, 28000, 1),
    (v_orden, 'repuesto', null, (select id from repuestos where sku = 'PF-450'), 'Pastillas de freno delanteras', 1, 32000, 2);

  insert into registro_horas (orden_id, personal_id, horas, detalle)
  values (v_orden, v_mecanico, 0.5, 'Diagnóstico y desarme rueda delantera');

  insert into pagos (orden_id, cliente_id, monto, metodo_pago, notas)
  values (v_orden, v_cliente, 30000, 'transferencia', 'Abono 50%');
end $$;

-- ============================================================
-- Storage: fotos de órdenes de trabajo
-- ============================================================
insert into storage.buckets (id, name, public)
values ('fotos-ot', 'fotos-ot', true)
on conflict (id) do nothing;

drop policy if exists "fotos_ot_select" on storage.objects;
create policy "fotos_ot_select" on storage.objects
  for select using (bucket_id = 'fotos-ot');

drop policy if exists "fotos_ot_insert" on storage.objects;
create policy "fotos_ot_insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'fotos-ot');

drop policy if exists "fotos_ot_delete" on storage.objects;
create policy "fotos_ot_delete" on storage.objects
  for delete to authenticated using (bucket_id = 'fotos-ot');

-- ============================================================
-- Portal público (acceso anónimo controlado por funciones)
-- ============================================================

-- Consulta del estado de una OT: requiere patente + número de orden.
create or replace function portal_consultar_orden(p_patente text, p_numero bigint)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'orden_id', o.id,
    'numero', o.numero,
    'estado', o.estado,
    'fecha_ingreso', o.fecha_ingreso,
    'fecha_entrega', o.fecha_entrega,
    'diagnostico', o.diagnostico,
    'vehiculo', jsonb_build_object('patente', v.patente, 'marca', v.marca, 'modelo', v.modelo),
    'taller', (
      select jsonb_build_object(
        'nombre', nombre, 'telefono', telefono,
        'direccion', direccion, 'iva_pct', iva_pct
      ) from taller_config where id = 1
    ),
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'descripcion', i.descripcion,
        'cantidad', i.cantidad,
        'precio_unitario', i.precio_unitario
      ) order by i.orden), '[]'::jsonb)
      from orden_items i where i.orden_id = o.id
    )
  )
  from ordenes o
  join vehiculos v on v.id = o.vehiculo_id
  where upper(replace(v.patente, ' ', '')) = upper(replace(p_patente, ' ', ''))
    and o.numero = p_numero
  limit 1;
$$;

-- Consulta de una cotización por su id (el UUID del link actúa como clave).
create or replace function portal_consultar_cotizacion(p_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'numero', c.numero,
    'fecha', c.fecha,
    'estado', c.estado,
    'validez_dias', c.validez_dias,
    'descuento_pct', c.descuento_pct,
    'notas', c.notas,
    'cliente', jsonb_build_object('nombre', cl.nombre),
    'vehiculo', case when v.id is null then null
      else jsonb_build_object('patente', v.patente, 'marca', v.marca, 'modelo', v.modelo) end,
    'taller', (
      select jsonb_build_object(
        'nombre', nombre, 'telefono', telefono,
        'direccion', direccion, 'iva_pct', iva_pct
      ) from taller_config where id = 1
    ),
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'descripcion', i.descripcion,
        'cantidad', i.cantidad,
        'precio_unitario', i.precio_unitario
      ) order by i.orden), '[]'::jsonb)
      from cotizacion_items i where i.cotizacion_id = c.id
    )
  )
  from cotizaciones c
  join clientes cl on cl.id = c.cliente_id
  left join vehiculos v on v.id = c.vehiculo_id
  where c.id = p_id;
$$;

-- El cliente aprueba o rechaza la cotización desde el link público.
create or replace function portal_responder_cotizacion(p_id uuid, p_respuesta text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_respuesta not in ('aprobada', 'rechazada') then
    raise exception 'Respuesta inválida';
  end if;
  update cotizaciones
  set estado = p_respuesta
  where id = p_id and estado in ('borrador', 'enviada');
  if not found then
    return 'no_actualizada';
  end if;
  return 'ok';
end $$;

grant execute on function portal_consultar_orden(text, bigint) to anon;
grant execute on function portal_consultar_cotizacion(uuid) to anon;
grant execute on function portal_responder_cotizacion(uuid, text) to anon;

-- ============================================================
-- v2: Inspecciones precompra + porcentajes de reparto
-- (ver sql/actualizacion-v2.sql para bases ya existentes)
-- ============================================================
alter table taller_config add column if not exists pct_mecanico numeric(5,2) not null default 0;
alter table taller_config add column if not exists pct_dueno    numeric(5,2) not null default 0;
alter table taller_config add column if not exists pct_taller   numeric(5,2) not null default 0;

create table if not exists inspecciones (
  id uuid primary key default uuid_generate_v4(),
  numero bigserial,
  nombre_comprador text not null,
  telefono text,
  patente text,
  marca text,
  modelo text,
  km text,
  precio_pedido numeric(12,2),
  datos jsonb not null default '{}'::jsonb,  -- respuestas del checklist
  score integer,
  ok integer not null default 0,
  warn integer not null default 0,
  bad integer not null default 0,
  na integer not null default 0,
  total integer not null default 0,
  recomendacion text,
  observaciones text,
  fecha timestamptz not null default now()
);

create index if not exists idx_inspecciones_fecha on inspecciones (fecha);

alter table inspecciones enable row level security;
drop policy if exists "Usuarios autenticados acceso total" on inspecciones;
create policy "Usuarios autenticados acceso total" on inspecciones
  for all using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

create or replace function portal_consultar_inspeccion(p_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'numero', i.numero,
    'fecha', i.fecha,
    'nombre_comprador', i.nombre_comprador,
    'patente', i.patente,
    'marca', i.marca,
    'modelo', i.modelo,
    'km', i.km,
    'precio_pedido', i.precio_pedido,
    'datos', i.datos,
    'score', i.score,
    'ok', i.ok, 'warn', i.warn, 'bad', i.bad, 'na', i.na, 'total', i.total,
    'recomendacion', i.recomendacion,
    'observaciones', i.observaciones,
    'taller', (
      select jsonb_build_object(
        'nombre', nombre, 'telefono', telefono,
        'direccion', direccion, 'email', email
      ) from taller_config where id = 1
    )
  )
  from inspecciones i
  where i.id = p_id;
$$;

grant execute on function portal_consultar_inspeccion(uuid) to anon;
