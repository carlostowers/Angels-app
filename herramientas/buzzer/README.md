# Buzzer Beater 2026 · estadísticas del torneo

Página **Buzzer** de Angels app (v4.22.0). Pedido de Carlos, 17 nov. 2026.

- Fuente: páginas oficiales de cada partido de Junior Masculino en buzzerbeaterpr.com (box score de los dos equipos, sets, orden de saque, lista de puntos con su segundo en el video de YouTube y el jugada a jugada).
- Base de datos: migración `supabase/migrations/0031_buzzer_estadisticas.sql` (`angels.buzzer_config`, `buzzer_partidos`, `buzzer_box`; RPC `player_buzzer`, `staff_buzzer`, `staff_buzzer_config`).
- La ven todos los jugadores solo cuando Carlos la abre desde la página Buzzer del staff (como el examen). Cerrada por defecto.

## Cargar después de cada juego

1. `sh bajar.sh /tmp/bb` (baja las 32 páginas de partido).
2. `python3 -I bb_parse.py /tmp/bb datos/buzzer-2026.json` y después `python3 -I bb_fases.py /tmp/bb datos/buzzer-2026.json` (K1, first ball side-out y K2).
3. Commit y push del JSON.
4. En Supabase, `cargar.sql` (paso 1 con el SHA del commit, paso 2 con el id que devuelve). Es upsert: no borra nada.

## Cómo se calcula lo que no viene en el box score

- **Quién sacó cada rally:** el que ganó el punto anterior saca. Si el jugada a jugada dice el sacador, manda el jugada a jugada.
- **Rotación:** se ancla en cada saque conocido (jugada a jugada y aces) y avanza con cada side-out. En los 32 partidos, 614 de 630 saques conocidos coinciden con la rotación calculada; las diferencias vienen de cambios de jugadores.
- **R1** = rotación en que saca el colocador (en ADC, Eiden #24): orden de saque como numera Carlos (R1 colocador en Z1, R2 en Z6, R3 en Z5, R4 en Z4, R5 en Z3, R6 en Z2). En los rivales, el colocador es el de más asistencias.
- Los puntos de antes de que empezara el video no tienen detalle: no cuentan para side-out, break-point ni rotaciones.
