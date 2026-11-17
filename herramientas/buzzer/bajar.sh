#!/bin/sh
# Baja las paginas de todos los partidos de Junior Masculino del Buzzer Beater
# 2026 (buzzerbeaterpr.com) a la carpeta que se le pase. Uso: sh bajar.sh <carpeta>
set -e
DIR="${1:-./crudo}"
mkdir -p "$DIR"
BASE="https://www.buzzerbeaterpr.com/model/volleyball-live-stats"
Q="search=&school=&sport=4&tournament=&match_date=&court=&status=&category=Junior&sex=Masculino&order=x_studio_date+desc"
curl -sS -m 40 -o "$DIR/lista1.html" "$BASE?$Q"
curl -sS -m 40 -o "$DIR/lista2.html" "$BASE/page/2?$Q"
SLUGS=$( (grep -oh 'volleyball-live-stats/junior-masculino-[a-z0-9-]*' "$DIR"/lista*.html | sed 's/.*stats\///'; \
  printf '%s\n' junior-masculino-quarterfinal-1-g26-313 junior-masculino-quarterfinal-2-g27-314 junior-masculino-quarterfinal-3-g28-315 \
  junior-masculino-quarterfinal-4-g29-316 junior-masculino-semifinal-1-g30-317 junior-masculino-semifinal-2-g31-318 junior-masculino-final-g32-319) | sort -u)
for s in $SLUGS; do
  curl -sS -m 40 -o "$DIR/m_$s.html" "$BASE/$s?sex=Masculino"
  sleep 0.4
done
echo "$(ls "$DIR"/m_*.html | wc -l) partidos bajados en $DIR"
