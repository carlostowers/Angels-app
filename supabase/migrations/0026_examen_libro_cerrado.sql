-- =====================================================================
-- ANGELS - 0026 Examen a libro cerrado: intentos, verde o rojo por el
-- servidor, 20 minutos, abrir y cerrar desde el panel del coach, repaso
-- ---------------------------------------------------------------------
-- Decisiones de Carlos (14 nov 2026):
--  * El coach abre y cierra el examen desde su app. Cerrado, nadie empieza
--    ("El examen está cerrado. El coach te avisará cuando esté disponible.").
--    Quien ya empezó termina dentro de sus 20 minutos.
--  * Cada respuesta la revisa el servidor al tocarla: devuelve si fue
--    correcta (verde o roja), nunca cuál era la correcta. La respuesta queda
--    grabada y no se puede cambiar. La clave no sale de la base de datos.
--  * 20 minutos desde que empieza, contados por el servidor. Al pasar, el
--    intento se cierra con lo que lleve; lo no contestado cuenta como fallado.
--  * Una sola vez. Se puede repetir (práctica) solo con el repaso abierto.
--  * El repaso (correctas y explicaciones) solo con el repaso abierto.
--  * Se guardan el inicio, el fin, la hora de cada respuesta y las veces que
--    salió del examen (las cuenta el teléfono).
-- exam_results pasa a ser la tabla de intentos (estaba vacía). Se borra la
-- función vieja player_exam_submit (entregaba todo de una vez, sin reglas).
-- No se borran tablas ni datos.
-- =====================================================================

-- 1. Configuración del examen
alter table angels.exam_keys
  add column abierto       boolean    not null default false,
  add column repaso        boolean    not null default false,
  add column limite_min    smallint   not null default 20,
  add column explicaciones text[]     not null default '{}',
  add column preguntas     text[]     not null default '{}';
alter table angels.exam_keys add constraint exam_keys_limite_chk check (limite_min between 1 and 120);

create policy exam_keys_staff on angels.exam_keys for select to authenticated
  using ((select angels.is_staff()));
grant select on angels.exam_keys to authenticated;

-- 2. Intentos
alter table angels.exam_results rename column submitted_at to started_at;
alter table angels.exam_results
  add column finished_at timestamptz,
  add column answer_at   timestamptz[] not null default '{}',
  add column salidas     smallint      not null default 0,
  add column cierre      text,
  add column practica    boolean       not null default false;
alter table angels.exam_results add constraint exam_results_cierre_chk check (cierre is null or cierre in ('entrega', 'tiempo'));
alter table angels.exam_results alter column score set default 0;
alter table angels.exam_results alter column answers set default '{}';
create unique index exam_results_uno_en_curso on angels.exam_results (player_id, exam) where finished_at is null;

drop function if exists angels.player_exam_submit(text, text, smallint[]);

-- 3. Ayudas internas (no se pueden llamar desde la API)
create or replace function angels.exam_jugador(p_token text)
returns angels.players
language plpgsql
stable
set search_path to 'angels', 'pg_temp'
as $$
declare v angels.players%rowtype;
begin
  if p_token is null or length(p_token) < 32 then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  select * into v from angels.players where access_token = p_token;
  if not found then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  if v.status = 'pausado' then
    raise exception 'Tu perfil esta en pausa. Habla con el coach.' using errcode = '28000';
  end if;
  return v;
end;
$$;

create or replace function angels.exam_nombre(p angels.players)
returns text
language sql
immutable
set search_path to 'angels', 'pg_temp'
as $$
  select coalesce(nullif(btrim(p.nickname), ''), split_part(btrim(coalesce(p.name, '')), ' ', 1))
    || case when coalesce(btrim(p.number), '') <> '' then ' #' || btrim(p.number) else '' end;
$$;

-- Cierra un intento: calcula la nota con la clave del servidor.
create or replace function angels.exam_cerrar(p_id bigint, p_cierre text)
returns angels.exam_results
language plpgsql
set search_path to 'angels', 'pg_temp'
as $$
declare
  r   angels.exam_results%rowtype;
  k   angels.exam_keys%rowtype;
  n   int;
  s   int := 0;
  w   smallint[] := '{}';
  i   int;
begin
  select * into r from angels.exam_results where id = p_id for update;
  if not found or r.finished_at is not null then return r; end if;
  select * into k from angels.exam_keys where exam = r.exam;
  n := coalesce(array_length(k.answers, 1), 0);
  for i in 1..n loop
    if r.answers[i] is not null and r.answers[i] >= 0 and r.answers[i] = k.answers[i] then
      s := s + 1;
    else
      w := w || i::smallint;
    end if;
  end loop;
  update angels.exam_results
     set score = s, total = n, wrong = w, cierre = p_cierre,
         finished_at = case when p_cierre = 'tiempo'
                            then least(now(), r.started_at + make_interval(mins => k.limite_min))
                            else now() end
   where id = p_id
  returning * into r;
  return r;
end;
$$;

-- Cierra por tiempo los intentos vencidos (20 minutos y 15 segundos de gracia).
create or replace function angels.exam_vencer(p_exam text, p_player text)
returns void
language plpgsql
set search_path to 'angels', 'pg_temp'
as $$
declare r record;
begin
  for r in
    select x.id from angels.exam_results x join angels.exam_keys k on k.exam = x.exam
     where x.exam = p_exam and x.finished_at is null
       and (p_player is null or x.player_id = p_player)
       and now() > x.started_at + make_interval(mins => k.limite_min) + interval '15 seconds'
  loop
    perform angels.exam_cerrar(r.id, 'tiempo');
  end loop;
end;
$$;

revoke all on function angels.exam_jugador(text) from public, anon, authenticated;
revoke all on function angels.exam_nombre(angels.players) from public, anon, authenticated;
revoke all on function angels.exam_cerrar(bigint, text) from public, anon, authenticated;
revoke all on function angels.exam_vencer(text, text) from public, anon, authenticated;

-- 4. Jugador: estado (qué pantalla le toca)
create or replace function angels.player_exam_estado(p_token text, p_exam text)
returns jsonb
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_p     angels.players%rowtype;
  v_exam  text := lower(btrim(coalesce(p_exam, '')));
  k       angels.exam_keys%rowtype;
  r       angels.exam_results%rowtype;
  n       int;
  v_cur   jsonb := null;
  v_ok    jsonb;
  v_prim  jsonb := null;
  v_ult   jsonb := null;
  v_term  int;
begin
  v_p := angels.exam_jugador(p_token);
  select * into k from angels.exam_keys where exam = v_exam;
  if not found then raise exception 'Examen no valido'; end if;
  n := coalesce(array_length(k.answers, 1), 0);
  perform angels.exam_vencer(v_exam, v_p.id);

  select * into r from angels.exam_results where player_id = v_p.id and exam = v_exam and finished_at is null;
  if found then
    select coalesce(jsonb_agg(case when r.answers[i] is null or r.answers[i] < 0 then null
                                   else to_jsonb(r.answers[i] = k.answers[i]) end order by i), '[]'::jsonb)
      into v_ok from generate_series(1, n) as i;
    v_cur := jsonb_build_object('id', r.id, 'practica', r.practica, 'answers', to_jsonb(r.answers), 'ok', v_ok,
      'restantes', greatest(0, floor(extract(epoch from (r.started_at + make_interval(mins => k.limite_min) - now())))::int));
  end if;

  select count(*) into v_term from angels.exam_results where player_id = v_p.id and exam = v_exam and finished_at is not null;
  select jsonb_build_object('score', x.score, 'total', x.total) into v_prim
    from angels.exam_results x where x.player_id = v_p.id and x.exam = v_exam and x.finished_at is not null
    order by x.practica asc, x.started_at asc limit 1;
  select jsonb_build_object('id', x.id, 'score', x.score, 'total', x.total, 'wrong', to_jsonb(x.wrong), 'answers', to_jsonb(x.answers),
                            'practica', x.practica, 'cierre', x.cierre) into v_ult
    from angels.exam_results x where x.player_id = v_p.id and x.exam = v_exam and x.finished_at is not null
    order by x.started_at desc limit 1;

  return jsonb_build_object('ok', true, 'nombre', angels.exam_nombre(v_p), 'abierto', k.abierto, 'repaso', k.repaso,
    'limite_min', k.limite_min, 'total', n, 'en_curso', v_cur, 'terminados', v_term, 'primero', v_prim, 'ultimo', v_ult);
end;
$$;

-- 5. Jugador: empezar un intento
create or replace function angels.player_exam_empezar(p_token text, p_exam text)
returns jsonb
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_p     angels.players%rowtype;
  v_exam  text := lower(btrim(coalesce(p_exam, '')));
  k       angels.exam_keys%rowtype;
  n       int;
  v_term  int;
begin
  v_p := angels.exam_jugador(p_token);
  select * into k from angels.exam_keys where exam = v_exam;
  if not found then raise exception 'Examen no valido'; end if;
  perform angels.exam_vencer(v_exam, v_p.id);
  if exists (select 1 from angels.exam_results where player_id = v_p.id and exam = v_exam and finished_at is null) then
    return angels.player_exam_estado(p_token, v_exam);
  end if;
  if not k.abierto then
    raise exception 'El examen está cerrado. El coach te avisará cuando esté disponible.';
  end if;
  select count(*) into v_term from angels.exam_results where player_id = v_p.id and exam = v_exam and finished_at is not null;
  if v_term > 0 and not k.repaso then
    raise exception 'Ya hiciste el examen. El repaso se abre cuando el coach lo diga.';
  end if;
  if (select count(*) from angels.exam_results where player_id = v_p.id and started_at > now() - interval '1 day') >= 20 then
    raise exception 'Ya hiciste muchos intentos hoy. Intenta mañana.';
  end if;
  n := coalesce(array_length(k.answers, 1), 0);
  begin
    insert into angels.exam_results (player_id, exam, answers, answer_at, score, total, wrong, practica)
    values (v_p.id, v_exam, array_fill(-1::smallint, array[n]), array_fill(null::timestamptz, array[n]), 0, n, '{}', v_term > 0);
  exception when unique_violation then
    null; -- ya había uno en curso (doble toque): se devuelve ese
  end;
  return angels.player_exam_estado(p_token, v_exam);
end;
$$;

-- 6. Jugador: contestar una pregunta (p_q de 0 a N-1, en el orden original)
create or replace function angels.player_exam_responder(p_token text, p_id bigint, p_q int, p_choice smallint, p_salidas int)
returns jsonb
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_p   angels.players%rowtype;
  r     angels.exam_results%rowtype;
  k     angels.exam_keys%rowtype;
  n     int;
  i     int;
  v_sal int := least(greatest(coalesce(p_salidas, 0), 0), 999);
begin
  v_p := angels.exam_jugador(p_token);
  select * into r from angels.exam_results where id = p_id and player_id = v_p.id for update;
  if not found then raise exception 'Intento no valido'; end if;
  select * into k from angels.exam_keys where exam = r.exam;
  if r.finished_at is not null then
    return jsonb_build_object('ok', false, 'terminado', true, 'score', r.score, 'total', r.total, 'cierre', r.cierre);
  end if;
  if now() > r.started_at + make_interval(mins => k.limite_min) + interval '15 seconds' then
    update angels.exam_results set salidas = greatest(salidas, v_sal) where id = r.id;
    r := angels.exam_cerrar(r.id, 'tiempo');
    return jsonb_build_object('ok', false, 'terminado', true, 'score', r.score, 'total', r.total, 'cierre', r.cierre);
  end if;
  n := coalesce(array_length(k.answers, 1), 0);
  if p_q is null or p_q < 0 or p_q >= n then raise exception 'Pregunta no valida'; end if;
  if p_choice is null or p_choice < 0 or p_choice > 9 then raise exception 'Respuesta no valida'; end if;
  i := p_q + 1;
  if r.answers[i] >= 0 then
    update angels.exam_results set salidas = greatest(salidas, v_sal) where id = r.id;
    return jsonb_build_object('ok', true, 'repetida', true, 'correcta', r.answers[i] = k.answers[i]);
  end if;
  update angels.exam_results
     set answers[i] = p_choice, answer_at[i] = now(), salidas = greatest(salidas, v_sal)
   where id = r.id
  returning * into r;
  return jsonb_build_object('ok', true, 'correcta', p_choice = k.answers[i],
    'contestadas', (select count(*) from unnest(r.answers) a where a >= 0),
    'restantes', greatest(0, floor(extract(epoch from (r.started_at + make_interval(mins => k.limite_min) - now())))::int));
end;
$$;

-- 7. Jugador: terminar (entregar) el intento
create or replace function angels.player_exam_terminar(p_token text, p_id bigint, p_salidas int)
returns jsonb
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_p   angels.players%rowtype;
  r     angels.exam_results%rowtype;
  k     angels.exam_keys%rowtype;
  v_sal int := least(greatest(coalesce(p_salidas, 0), 0), 999);
begin
  v_p := angels.exam_jugador(p_token);
  select * into r from angels.exam_results where id = p_id and player_id = v_p.id for update;
  if not found then raise exception 'Intento no valido'; end if;
  if r.finished_at is null then
    select * into k from angels.exam_keys where exam = r.exam;
    update angels.exam_results set salidas = greatest(salidas, v_sal) where id = r.id;
    r := angels.exam_cerrar(r.id, case when now() > r.started_at + make_interval(mins => k.limite_min) + interval '15 seconds'
                                       then 'tiempo' else 'entrega' end);
  end if;
  return jsonb_build_object('ok', true, 'score', r.score, 'total', r.total, 'wrong', to_jsonb(r.wrong), 'cierre', r.cierre,
    'practica', r.practica, 'nombre', angels.exam_nombre(v_p));
end;
$$;

-- 8. Jugador: repaso (solo con el repaso abierto y un intento terminado)
create or replace function angels.player_exam_repaso(p_token text, p_exam text)
returns jsonb
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_p    angels.players%rowtype;
  v_exam text := lower(btrim(coalesce(p_exam, '')));
  k      angels.exam_keys%rowtype;
begin
  v_p := angels.exam_jugador(p_token);
  select * into k from angels.exam_keys where exam = v_exam;
  if not found then raise exception 'Examen no valido'; end if;
  if not k.repaso then raise exception 'El repaso todavía está cerrado. El coach lo abre cuando todos terminen.'; end if;
  if not exists (select 1 from angels.exam_results where player_id = v_p.id and exam = v_exam and finished_at is not null) then
    raise exception 'Primero haz el examen.';
  end if;
  return jsonb_build_object('ok', true, 'correctas', to_jsonb(k.answers), 'explicaciones', to_jsonb(k.explicaciones));
end;
$$;

-- 9. Staff: abrir o cerrar el examen y el repaso (null = no cambia)
create or replace function angels.staff_exam_config(p_exam text, p_abierto boolean, p_repaso boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare k angels.exam_keys%rowtype;
begin
  if not angels.is_staff() then raise exception 'Solo staff' using errcode = '42501'; end if;
  update angels.exam_keys
     set abierto = coalesce(p_abierto, abierto), repaso = coalesce(p_repaso, repaso), updated_at = now()
   where exam = lower(btrim(coalesce(p_exam, '')))
  returning * into k;
  if not found then raise exception 'Examen no valido'; end if;
  return jsonb_build_object('ok', true, 'abierto', k.abierto, 'repaso', k.repaso);
end;
$$;

-- 10. Staff: tablero (cierra primero los intentos vencidos)
create or replace function angels.staff_exam_board(p_exam text)
returns jsonb
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_exam text := lower(btrim(coalesce(p_exam, '')));
  k      angels.exam_keys%rowtype;
  v_int  jsonb;
begin
  if not angels.is_staff() then raise exception 'Solo staff' using errcode = '42501'; end if;
  select * into k from angels.exam_keys where exam = v_exam;
  if not found then raise exception 'Examen no valido'; end if;
  perform angels.exam_vencer(v_exam, null);
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id, 'player_id', x.player_id, 'started_at', x.started_at, 'finished_at', x.finished_at,
           'score', x.score, 'total', x.total, 'wrong', to_jsonb(x.wrong), 'salidas', x.salidas, 'cierre', x.cierre,
           'practica', x.practica, 'contestadas', (select count(*) from unnest(x.answers) a where a >= 0),
           'restantes', case when x.finished_at is null then greatest(0, floor(extract(epoch from (x.started_at + make_interval(mins => k.limite_min) - now())))::int) end)
         order by x.started_at), '[]'::jsonb)
    into v_int
    from angels.exam_results x where x.exam = v_exam;
  return jsonb_build_object('ok', true, 'abierto', k.abierto, 'repaso', k.repaso, 'limite_min', k.limite_min,
    'total', coalesce(array_length(k.answers, 1), 0), 'preguntas', to_jsonb(k.preguntas), 'intentos', v_int);
end;
$$;

revoke all on function angels.player_exam_estado(text, text) from public;
revoke all on function angels.player_exam_empezar(text, text) from public;
revoke all on function angels.player_exam_responder(text, bigint, int, smallint, int) from public;
revoke all on function angels.player_exam_terminar(text, bigint, int) from public;
revoke all on function angels.player_exam_repaso(text, text) from public;
revoke all on function angels.staff_exam_config(text, boolean, boolean) from public, anon;
revoke all on function angels.staff_exam_board(text) from public, anon;
grant execute on function angels.player_exam_estado(text, text) to anon, authenticated;
grant execute on function angels.player_exam_empezar(text, text) to anon, authenticated;
grant execute on function angels.player_exam_responder(text, bigint, int, smallint, int) to anon, authenticated;
grant execute on function angels.player_exam_terminar(text, bigint, int) to anon, authenticated;
grant execute on function angels.player_exam_repaso(text, text) to anon, authenticated;
grant execute on function angels.staff_exam_config(text, boolean, boolean) to authenticated;
grant execute on function angels.staff_exam_board(text) to authenticated;

-- 11. Examen del Buzzer Beater: empieza cerrado, 20 minutos, explicaciones y preguntas en el servidor
update angels.exam_keys set
  abierto = false, repaso = false, limite_min = 20, updated_at = now(),
  explicaciones = array[
    $x$Javier juega de opuesto en R1, R2 y R3. Cuando Eiden pasa a la red, Javier coloca desde atrás, y Carlos #1 entra por Eiden para jugar en la red.$x$,
    $x$Carlos #1 entra por Eiden cuando Eiden pasa a la red, y Eiden vuelve a entrar cuando Carlos pasa atrás.$x$,
    $x$R1: Z1 #24 · Z2 #10 · Z3 #7 · Z4 #9 · Z5 #30 · Z6 #15.$x$,
    $x$Ian #14 entra por Johan #15 y Adrián #28 entra por Gabriel #7: los líberos entran por los centrales cuando pasan atrás.$x$,
    $x$R1: colocador en Z1, R2 en Z6, R3 en Z5. Desde Z5 la corrida es la más larga y nadie puede salir antes del saque: ojo con la superposición.$x$,
    $x$Es el ajuste del coach: en R4 y R5 Carlos juega el centro y Johan el opuesto.$x$,
    $x$En R6 Gabriel juega el centro y Carlos pasa al opuesto.$x$,
    $x$Con pase # buscamos cuatro amenazas. En R3 la cuarta es el Pipe: el punta zaguero ataca por el centro de la cancha.$x$,
    $x$El pase − deja una sola opción de verdad, sin 1T ni jugadas rápidas. Todos cubren y quedan listos para defender.$x$,
    $x$Con !, primero mantenemos vivo el rally: un mal pase no puede convertirse en dos errores. Balón alto y todos cubren.$x$,
    $x$El target está cerca de la red, al medio de la cancha, más hacia Z3. Desde ahí el colocador tiene todas las opciones.$x$,
    $x$Free ball = cuatro amenazas. Cuando oímos FREE, dejamos de defender y nos preparamos para atacar.$x$,
    $x$Así defendemos contra la punta: dos bloquean, nadie se queda solo esperando el tip y cuatro defienden.$x$,
    $x$El OFF baja de la red a la diagonal corta. El tip no tiene dueño fijo: es de quien lo tenga en su carril.$x$,
    $x$El líbero juega en Z5, la punta de atrás en Z6 y Z1 es del tercer jugador de atrás.$x$,
    $x$Cubrimos antes del golpe, no después. Los otros dos cubren lejos, por si el balón rebota largo del bloqueo.$x$,
    $x$Primero miramos al colocador y después le ganamos la carrera a su central. Ojos en el colocador, primero los pies y después las manos.$x$,
    $x$Si el bloqueo cierra la diagonal, quedan la línea y la mano de afuera: el balón pega en la mano del bloqueador de la punta y se va afuera.$x$,
    $x$Si la defensa juega atrás, el espacio libre está corto. El roll es un golpe suave con efecto que cae detrás del bloqueo.$x$,
    $x$Si la defensa se adelanta, el espacio libre está atrás, en las esquinas del fondo.$x$,
    $x$Con un set difícil, el atacante usa las manos del bloqueo o la juega segura para volver a construir el ataque. Por eso todos cubren.$x$,
    $x$Prunes ataca más que nadie (9 kills en 16 ataques) y le colocaron 7 de los 12 primeros balones del set 2. Ataca por el lado de nuestro opuesto.$x$,
    $x$Nieves recibe y después tiene que atacar, y ataca mal (.125). A Prunes casi no lo ponen a recibir.$x$,
    $x$Con Nieves sacando ganaron 5 de 8 puntos. Cortar la racha vale más que el pase perfecto.$x$,
    $x$Atacó 2 veces de segunda y anotó las 2. Nuestros Z4 y Z5 cuidan el tip corto.$x$,
    $x$Le colocaron casi la mitad de los primeros balones. Doble a él, pero el central lee: reparten el ataque entre 6 jugadores. Aponte #5 es su sacador peligroso.$x$,
    $x$Rosario #9 y Figueroa #10 reciben y después atacan. En 2 sets fallaron 7 saques y 9 ataques.$x$,
    $x$Contra este saque, un pase + es suficiente: balón alto y a atacar.$x$,
    $x$Torres y López son los que más reciben. Contra un equipo que defiende tanto, un error de saque es un punto regalado.$x$,
    $x$Sus sacadores hacen rachas: en un tramo ganaron 10 de 12 puntos con su saque. El primer side-out corta la racha, y un error de saque nuestro es un punto regalado.$x$
  ],
  preguntas = array[
    $x$Cuando Eiden #24 pasa a la red, ¿quién ya está en la cancha y va a colocar?$x$,
    $x$¿Quién entra por Eiden cuando él pasa a la red?$x$,
    $x$En nuestra R1, ¿quién está en Z4?$x$,
    $x$¿Por quién entra Adrián #28, nuestro líbero?$x$,
    $x$En R3, Eiden #24 sale a colocar desde Z5. ¿Qué tenemos que cuidar?$x$,
    $x$Cuando Carlos #1 entra por Eiden en R4 y R5, ¿quién juega de opuesto?$x$,
    $x$En R6, Carlos #1 está en Z2 y Gabriel #7 llega a la red. ¿Quién juega el centro?$x$,
    $x$Derek #2 coloca en R3 y el pase es #. ¿Qué amenazas tiene?$x$,
    $x$Javier #9 está colocando y el pase llega − (negativo). ¿Qué coloca?$x$,
    $x$Derek #2 coloca un pase ! (exclamativo). ¿Qué hace?$x$,
    $x$Ian #14 recibe el saque. ¿A dónde tiene que ir el pase (el target)?$x$,
    $x$Manuel #11 está de central en la red y se oye FREE. ¿Qué hace?$x$,
    $x$Javier #9 y Johan #15 bloquean juntos a la punta rival. ¿Qué quiere decir que defendemos 2-0-4?$x$,
    $x$Jomar #30 está en la red, pero el ataque rival va por el otro lado y él no bloquea (es el OFF). ¿Qué hace?$x$,
    $x$En nuestra defensa Middle/Middle, ¿desde dónde defiende el líbero (Ian #14 o Adrián #28)?$x$,
    $x$Yandier #10 ataca por Z4. ¿Cómo lo cubrimos?$x$,
    $x$Manuel #11 bloquea en el centro contra el 1T rival. ¿Qué mira primero?$x$,
    $x$Contra San Ignacio, Yandier #10 ataca por Z4. Su bloqueo de dos le cierra la diagonal y deja la línea. ¿Qué tiene más sentido?$x$,
    $x$San José le defendió a Jomar #30 dos diagonales fuertes. Su defensa está atrás, al fondo. ¿Qué cambia Jomar?$x$,
    $x$Javier #9 ataca por Z2 y la defensa rival se viene adelante esperando el tip. ¿Qué hace?$x$,
    $x$Carlos #1 recibe un set pegado a la red y el bloqueo de dos lo espera arriba. ¿Qué hace?$x$,
    $x$Pentecostal: ¿quién es su mejor jugador y cómo lo paramos?$x$,
    $x$Contra Pentecostal, ¿a quién le sacamos?$x$,
    $x$Pentecostal hizo su única racha cuando sacó el #4 Nieves. Si te toca recibir su saque, ¿qué buscas?$x$,
    $x$Cuando el colocador #16 de Pentecostal está en la red, ¿qué cuidamos?$x$,
    $x$Perpetuo Socorro: ¿quién es su jugador más peligroso?$x$,
    $x$Manuel #11 saca contra Perpetuo Socorro. ¿A quién le saca y con qué idea?$x$,
    $x$San José: ¿cuál es su arma y cómo recibimos?$x$,
    $x$Derek #2 saca contra San José. ¿A dónde saca?$x$,
    $x$San Ignacio saca fuerte y casi no falla: 10 aces y solo 4 errores en 49 saques. ¿Qué tiene más sentido para nosotros?$x$
  ]
where exam = 'buzzer-2026';
