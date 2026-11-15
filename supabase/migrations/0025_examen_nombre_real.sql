-- =====================================================================
-- ANGELS - 0025 El examen devuelve el nombre real del jugador
-- ---------------------------------------------------------------------
-- player_exam_submit devuelve también 'nombre': el del dueño del enlace
-- (apodo, o primer nombre, y número), como lo nombra la app. El examen lo
-- usa en la pantalla final y en el mensaje de WhatsApp, en lugar del nombre
-- que se escoja en el teléfono. Misma firma, mismos permisos; no toca tablas.
-- =====================================================================

create or replace function angels.player_exam_submit(p_token text, p_exam text, p_answers smallint[])
returns jsonb
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_player  angels.players%rowtype;
  v_exam    text := lower(btrim(coalesce(p_exam, '')));
  v_key     smallint[];
  v_n       int;
  v_score   int := 0;
  v_wrong   smallint[] := '{}';
  v_tries   int;
  v_nombre  text;
  i         int;
begin
  if p_token is null or length(p_token) < 32 then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  select * into v_player from angels.players where access_token = p_token;
  if not found then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  if v_player.status = 'pausado' then
    raise exception 'Tu perfil esta en pausa. Habla con el coach.' using errcode = '28000';
  end if;
  if v_exam !~ '^[a-z0-9-]{2,40}$' then
    raise exception 'Examen no valido';
  end if;
  select k.answers into v_key from angels.exam_keys k where k.exam = v_exam;
  if v_key is null then
    raise exception 'Examen no valido';
  end if;
  v_nombre := coalesce(nullif(btrim(v_player.nickname), ''), split_part(btrim(coalesce(v_player.name, '')), ' ', 1))
    || case when coalesce(btrim(v_player.number), '') <> '' then ' #' || btrim(v_player.number) else '' end;
  v_n := coalesce(array_length(v_key, 1), 0);
  if p_answers is null or coalesce(array_length(p_answers, 1), 0) <> v_n then
    raise exception 'Faltan respuestas';
  end if;
  for i in 1..v_n loop
    if p_answers[i] is null or p_answers[i] < 0 or p_answers[i] > 9 then
      raise exception 'Respuesta no valida';
    end if;
    if p_answers[i] = v_key[i] then
      v_score := v_score + 1;
    else
      v_wrong := v_wrong || i::smallint;
    end if;
  end loop;

  if exists (select 1 from angels.exam_results r
             where r.player_id = v_player.id and r.exam = v_exam and r.answers = p_answers
               and r.submitted_at > now() - interval '1 minute') then
    return jsonb_build_object('ok', true, 'repetido', true, 'score', v_score, 'total', v_n, 'wrong', to_jsonb(v_wrong), 'nombre', v_nombre);
  end if;
  if (select count(*) from angels.exam_results r
      where r.player_id = v_player.id and r.submitted_at > now() - interval '1 day') >= 20 then
    raise exception 'Ya entregaste muchas veces hoy. Intenta mañana.';
  end if;

  insert into angels.exam_results (player_id, exam, answers, score, total, wrong)
  values (v_player.id, v_exam, p_answers, v_score, v_n, v_wrong);

  select count(*) into v_tries from angels.exam_results r where r.player_id = v_player.id and r.exam = v_exam;
  return jsonb_build_object('ok', true, 'score', v_score, 'total', v_n, 'wrong', to_jsonb(v_wrong), 'intento', v_tries, 'nombre', v_nombre);
end;
$$;
revoke all on function angels.player_exam_submit(text, text, smallint[]) from public;
grant execute on function angels.player_exam_submit(text, text, smallint[]) to anon, authenticated;
