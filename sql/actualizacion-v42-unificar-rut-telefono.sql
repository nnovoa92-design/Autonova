-- ============================================================
-- Actualización v42: unificar el formato de RUT y teléfonos ya guardados
--
-- La app ahora escribe todos los RUT como 12.345.678-9 y todos los teléfonos
-- como +56 9 1234 5678. Este script pone en ese mismo formato lo que ya estaba
-- guardado (clientes, taller, personal, inspecciones, contabilidad y citas).
--
-- Reglas de seguridad:
--  * Solo cambia el FORMATO; nunca los números.
--  * Lo ambiguo no se toca: teléfonos que no tengan 9 dígitos, números de otro país
--    (+51, +54…) y documentos con letras (pasaportes).
--  * Si dos clientes quedarían con el mismo RUT, no se toca ninguno de los dos
--    (queda para revisarlos a mano).
--  * Cada valor cambiado queda en la tabla respaldo_formatos_v42, por si hay que volver atrás.
--
-- Es seguro ejecutarlo más de una vez.
-- ============================================================

-- Formatea un RUT: 12345678-5 / 123456785 -> 12.345.678-5
create or replace function _autonova_fmt_rut(p text) returns text
language plpgsql immutable as $$
declare v text; cuerpo text;
begin
  if p is null or btrim(p) = '' then return p; end if;
  if p ~ '[A-JL-Za-jl-z]' then return p; end if;
  v := upper(regexp_replace(p, '[^0-9kK]', '', 'g'));
  if v !~ '^[0-9]{6,8}[0-9K]$' then return p; end if;
  cuerpo := (left(v, length(v) - 1))::bigint::text;
  return replace(to_char(cuerpo::bigint, 'FM999,999,999'), ',', '.') || '-' || right(v, 1);
end $$;

-- Formatea un teléfono chileno: 912345678 / 56912345678 -> +56 9 1234 5678
create or replace function _autonova_fmt_tel(p text) returns text
language plpgsql immutable as $$
declare d text; n text;
begin
  if p is null or btrim(p) = '' then return p; end if;
  d := regexp_replace(p, '\D', '', 'g');
  if btrim(p) like '+%' and d not like '56%' then return p; end if;
  if d like '56%' and length(d) = 11 then n := substr(d, 3);
  else n := regexp_replace(d, '^0+', '');
  end if;
  if length(n) <> 9 then return p; end if;
  if n like '9%' then return '+56 9 ' || substr(n, 2, 4) || ' ' || substr(n, 6, 4);
  elsif n like '2%' then return '+56 2 ' || substr(n, 2, 4) || ' ' || substr(n, 6, 4);
  else return '+56 ' || substr(n, 1, 2) || ' ' || substr(n, 3, 3) || ' ' || substr(n, 6, 4);
  end if;
end $$;

create table if not exists respaldo_formatos_v42 (
  tabla text not null,
  id text,
  campo text not null,
  valor_anterior text,
  cambiado_en timestamptz not null default now()
);

-- 1) RUT de clientes (es único: se evita crear duplicados)
with cand as (
  select id, rut as antes, _autonova_fmt_rut(rut) as despues,
         row_number() over (partition by _autonova_fmt_rut(rut) order by creado_en, id) as rn
  from clientes
  where rut is not null
),
cambios as (
  select c.id, c.antes, c.despues
  from cand c
  where c.antes is distinct from c.despues
    and c.rn = 1
    and not exists (select 1 from clientes x where x.rut = c.despues and x.id <> c.id)
),
resp as (
  insert into respaldo_formatos_v42 (tabla, id, campo, valor_anterior)
  select 'clientes', id::text, 'rut', antes from cambios
  returning 1
)
update clientes cl set rut = cambios.despues
from cambios
where cl.id = cambios.id;

-- 2) Resto de RUT y todos los teléfonos
do $$
declare r record;
begin
  for r in
    select * from (values
      ('taller_config', 'rut', '_autonova_fmt_rut'),
      ('clientes', 'telefono', '_autonova_fmt_tel'),
      ('taller_config', 'telefono', '_autonova_fmt_tel'),
      ('personal', 'telefono', '_autonova_fmt_tel'),
      ('inspecciones', 'telefono', '_autonova_fmt_tel'),
      ('movimientos_contables', 'telefono', '_autonova_fmt_tel'),
      ('citas', 'telefono_contacto', '_autonova_fmt_tel')
    ) as t(tabla, columna, funcion)
  loop
    if to_regclass('public.' || r.tabla) is null then continue; end if;
    execute format(
      'insert into respaldo_formatos_v42 (tabla, id, campo, valor_anterior)
         select %L, (to_jsonb(t) ->> ''id''), %L, t.%I from %I t
         where t.%I is not null and %I(t.%I) is distinct from t.%I',
      r.tabla, r.columna, r.columna, r.tabla, r.columna, r.funcion, r.columna, r.columna);
    execute format(
      'update %I t set %I = %I(t.%I) where t.%I is not null and %I(t.%I) is distinct from t.%I',
      r.tabla, r.columna, r.funcion, r.columna, r.columna, r.funcion, r.columna, r.columna);
  end loop;
end $$;

drop function if exists _autonova_fmt_rut(text);
drop function if exists _autonova_fmt_tel(text);

-- Resumen: qué se unificó y qué quedó para revisar a mano
select 'v42 formatos unificados' as estado,
       (select count(*) from respaldo_formatos_v42 where tabla = 'clientes' and campo = 'rut') as ruts_de_clientes_cambiados,
       (select count(*) from respaldo_formatos_v42 where campo like '%telefono%') as telefonos_cambiados,
       (select count(*) from clientes where rut is not null and rut !~ '^[0-9]{1,2}\.[0-9]{3}\.[0-9]{3}-[0-9K]$') as ruts_por_revisar,
       (select count(*) from clientes where telefono is not null and telefono !~ '^\+56 [0-9]') as telefonos_por_revisar;
