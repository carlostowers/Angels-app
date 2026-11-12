-- =====================================================================
-- 0019 · Se borra el bloque viejo del Buzzer Beater
-- ---------------------------------------------------------------------
-- La fila 'adc-buzzerbeater' ("Buzzer Beater La Copa", 4 al 22 de
-- noviembre de 2026, sin confirmar) era la ventana tentativa del torneo.
-- Ya la reemplazan los cinco juegos confirmados (filas 'bb26-'), todos
-- con peso "objetivo", así que el taper sigue funcionando.
-- Solo se borra si sigue sin confirmar. Las filas 'bb26-' no se tocan.
-- =====================================================================

delete from angels.tournaments
 where id = 'adc-buzzerbeater'
   and confirmed = false;

-- Para restaurarla (copia de la fila tal como estaba antes de borrarla):
-- insert into angels.tournaments
--   (id, sub, kind, name, sede, color, notes, phase, rival, teams, result,
--    weight, jornada, end_date, confirmed, game_time, created_at, start_date, updated_at)
-- values
--   ('adc-buzzerbeater', 'Gurabo', 'torneo', 'Buzzer Beater La Copa', null, '#51B7E4',
--    'Campeonato nacional. Ventana de 18 dias. Fechas exactas de junior masculino pendientes: ajustar start_date y end_date cuando se anuncien, aprox. un mes antes.',
--    'regular', null, array['ADCJVBoys'], null, 'objetivo', null, '2026-11-22', false, null,
--    '2026-07-28T21:22:53.739919+00:00', '2026-11-04', '2026-11-10T13:37:17.54538+00:00');
