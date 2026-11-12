-- =====================================================================
-- 0021 · Juegos: BAREBORU 6x6 (cuarto juego)
-- ---------------------------------------------------------------------
-- Agrega 'bareboru6' a los récords del jugador y del coach, a los tops,
-- al borrado del staff y al registro anónimo de partidas del esquema
-- angels. No borra ni cambia ningún récord existente.
-- Validación en el servidor: la misma del 3 contra 3, porque el 6x6
-- también se juega a un set de 15 con ventaja de 2 y usa la misma marca:
--   level x (us x 10 + max(us - them, 0) x 5 + 100 si ganó)
-- con marcador final posible y al menos 4 s por punto jugado.
-- Las funciones se reescriben a partir de su definición vigente en la
-- base de datos (pg_get_functiondef), solo con los cambios de abajo; si un
-- reemplazo no encuentra el texto esperado, la migración se detiene.
-- =====================================================================

alter table angels.game_records drop constraint if exists game_records_game_chk;
alter table angels.game_records add constraint game_records_game_chk
  check (game = any (array['keepup','longspike','bareboru','bareboru6']));
alter table angels.staff_game_records drop constraint if exists staff_game_records_game_chk;
alter table angels.staff_game_records add constraint staff_game_records_game_chk
  check (game = any (array['keepup','longspike','bareboru','bareboru6']));
alter table angels.game_plays drop constraint if exists game_plays_game_chk;
alter table angels.game_plays add constraint game_plays_game_chk
  check (game = any (array['bareboru','bareboru6']));

do $mig$
declare
  f text;
  d text;
  n text;
begin
  foreach f in array array[
    'angels.player_game_submit(text,text,integer,jsonb)',
    'angels.staff_game_submit(text,integer,jsonb)',
    'angels.player_game_board(text,text,text)',
    'angels.staff_game_board(text)',
    'angels.staff_game_reset(text,text,text,text)']
  loop
    d := pg_get_functiondef(f::regprocedure);
    if position('bareboru6' in d) > 0 then
      raise notice 'ya tiene bareboru6: %', f;
      continue;
    end if;
    n := replace(d, 'array[''keepup'',''longspike'',''bareboru'']', 'array[''keepup'',''longspike'',''bareboru'',''bareboru6'']');
    if n = d then raise exception 'no encontre la lista de juegos en %', f; end if;
    if f like '%game_submit%' then
      d := n;
      n := replace(d, E'  elsif p_game = ''bareboru'' then\n', E'  elsif p_game in (''bareboru'', ''bareboru6'') then\n');
      if n = d then raise exception 'no encontre la validacion de bareboru en %', f; end if;
    end if;
    execute n;
  end loop;
  foreach f in array array[
    'angels.player_game_log(text,text,jsonb)',
    'angels.staff_game_log(text,jsonb)']
  loop
    d := pg_get_functiondef(f::regprocedure);
    if position('bareboru6' in d) > 0 then
      raise notice 'ya tiene bareboru6: %', f;
      continue;
    end if;
    n := replace(d, 'array[''bareboru'']', 'array[''bareboru'',''bareboru6'']');
    if n = d then raise exception 'no encontre la lista de juegos en %', f; end if;
    execute n;
  end loop;
end
$mig$;
