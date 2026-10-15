-- ============================================================
-- Actualización v46: limpiar marcado (< y >) en los textos que llegan desde la reserva pública
--
-- Cualquier persona puede reservar desde el link público y los datos que escribe (nombre, patente,
-- servicio «Otro», comentario...) se muestran luego en la Agenda y otras pantallas. Para que nunca
-- se pueda colar código en esas pantallas, se eliminan los caracteres < y > de esos campos al guardar.
--
--  * clientes: nombre, teléfono y RUT
--  * vehiculos: patente, marca y modelo
--  * citas: nombre, teléfono, patente y RUT de contacto, descripción, y comentario (si es reserva online)
--
-- Además limpia lo que ya estuviera guardado con esos caracteres. Seguro de correr más de una vez.
-- ============================================================

create or replace function limpiar_marcado(p text) returns text
language sql immutable as $$
  select case when p is null then null else regexp_replace(p, '[<>]', '', 'g') end;
$$;

create or replace function trg_limpiar_cliente() returns trigger language plpgsql as $$
begin
  new.nombre := limpiar_marcado(new.nombre);
  new.telefono := limpiar_marcado(new.telefono);
  new.rut := limpiar_marcado(new.rut);
  return new;
end $$;

create or replace function trg_limpiar_vehiculo() returns trigger language plpgsql as $$
begin
  new.patente := limpiar_marcado(new.patente);
  new.marca := limpiar_marcado(new.marca);
  new.modelo := limpiar_marcado(new.modelo);
  return new;
end $$;

create or replace function trg_limpiar_cita() returns trigger language plpgsql as $$
begin
  new.nombre_contacto := limpiar_marcado(new.nombre_contacto);
  new.telefono_contacto := limpiar_marcado(new.telefono_contacto);
  new.patente_contacto := limpiar_marcado(new.patente_contacto);
  new.descripcion := limpiar_marcado(new.descripcion);
  if new.origen = 'online' then
    new.notas := limpiar_marcado(new.notas);
  end if;
  return new;
end $$;

drop trigger if exists trg_limpiar_cliente on clientes;
create trigger trg_limpiar_cliente before insert or update on clientes
  for each row execute function trg_limpiar_cliente();

drop trigger if exists trg_limpiar_vehiculo on vehiculos;
create trigger trg_limpiar_vehiculo before insert or update on vehiculos
  for each row execute function trg_limpiar_vehiculo();

drop trigger if exists trg_limpiar_cita on citas;
create trigger trg_limpiar_cita before insert or update on citas
  for each row execute function trg_limpiar_cita();

-- rut_contacto existe desde v44; si aún no, se omite
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'citas' and column_name = 'rut_contacto') then
    execute $f$
      create or replace function trg_limpiar_cita() returns trigger language plpgsql as $g$
      begin
        new.nombre_contacto := limpiar_marcado(new.nombre_contacto);
        new.telefono_contacto := limpiar_marcado(new.telefono_contacto);
        new.patente_contacto := limpiar_marcado(new.patente_contacto);
        new.rut_contacto := limpiar_marcado(new.rut_contacto);
        new.descripcion := limpiar_marcado(new.descripcion);
        if new.origen = 'online' then
          new.notas := limpiar_marcado(new.notas);
        end if;
        return new;
      end $g$;
    $f$;
  end if;
end $$;

-- Limpieza de lo ya guardado
update clientes set nombre = limpiar_marcado(nombre), telefono = limpiar_marcado(telefono), rut = limpiar_marcado(rut)
where nombre ~ '[<>]' or telefono ~ '[<>]' or rut ~ '[<>]';

update vehiculos set patente = limpiar_marcado(patente), marca = limpiar_marcado(marca), modelo = limpiar_marcado(modelo)
where patente ~ '[<>]' or marca ~ '[<>]' or modelo ~ '[<>]';

update citas set nombre_contacto = limpiar_marcado(nombre_contacto), telefono_contacto = limpiar_marcado(telefono_contacto),
                 patente_contacto = limpiar_marcado(patente_contacto), descripcion = limpiar_marcado(descripcion),
                 notas = case when origen = 'online' then limpiar_marcado(notas) else notas end
where nombre_contacto ~ '[<>]' or telefono_contacto ~ '[<>]' or patente_contacto ~ '[<>]' or descripcion ~ '[<>]'
   or (origen = 'online' and notas ~ '[<>]');

select 'v46 textos públicos limpios' as estado;
