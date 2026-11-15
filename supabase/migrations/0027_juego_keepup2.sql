-- =====================================================================
-- 0027 · Juegos: Keep It Up 2.0 (top nuevo: keepup2)
-- ---------------------------------------------------------------------
-- Keep It Up 2.0 tiene fisica nueva (jugador con aceleracion, plancha y
-- paso fijo), asi que su marca no se compara con la de 0.5.1. Se agrega
-- el juego 'keepup2' a los records del jugador y del coach, a los tops y
-- al borrado del staff del esquema angels. El top de 'keepup' (el 2D, que
-- sigue disponible como clasico) no se toca: no se borra ni cambia nada.
-- Validacion en el servidor: la misma de 'keepup'
--   toques <= 4 x segundos + 5, nivel <= 1 + segundos / 6,
--   marca <= 150 x segundos + 600
-- Medido con el robot (pruebas/juegos/robot_keepup2.js): el mejor ritmo
-- fue 76 puntos por segundo, 0.71 toques por segundo y 0.04 niveles por
-- segundo, muy por debajo de esos limites.
-- Las funciones se reescriben a partir de su definicion vigente
-- (pg_get_functiondef), solo con los cambios de abajo; si un reemplazo no
-- encuentra el texto esperado, la migracion se detiene.
-- =====================================================================

alter table angels.game_records drop constraint if exists game_records_game_chk;
alter table angels.game_records add constraint game_records_game_chk
  check (game = any (array['keepup','longspike','bareboru','bareboru6','keepup2']));
alter table angels.staff_game_records drop constraint if exists staff_game_records_game_chk;
alter table angels.staff_game_records add constraint staff_game_records_game_chk
  check (game = any (array['keepup','longspike','bareboru','bareboru6','keepup2']));

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
    if position('keepup2' in d) > 0 then
      raise notice 'ya tiene keepup2: %', f;
      continue;
    end if;
    n := replace(d, 'array[''keepup'',''longspike'',''bareboru'',''bareboru6'']', 'array[''keepup'',''longspike'',''bareboru'',''bareboru6'',''keepup2'']');
    if n = d then raise exception 'no encontre la lista de juegos en %', f; end if;
    if f like '%game_submit%' then
      d := n;
      n := replace(d, E'  if p_game = ''keepup'' then\n', E'  if p_game in (''keepup'', ''keepup2'') then\n');
      if n = d then raise exception 'no encontre la validacion de keepup en %', f; end if;
    end if;
    execute n;
  end loop;
end
$mig$;
