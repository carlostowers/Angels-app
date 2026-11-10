# Angels - base de datos (esquema `angels`)

Derivada de Station v2.5.1, en el mismo proyecto Supabase, aislada en su propio esquema.
El esquema `public` (app actual) no se toca: queda como respaldo.

Aplicadas el 2026-11-10, en este orden: 0001, 0003, 0004, 0005, 0006, 0007, 0009, 0010, 0011, 0012, 0013, 0014, 0015, 0017.
Ninguna migracion borra nada (sin DROP, DELETE ni TRUNCATE).
v4.0.0 publicada en angelsapp.thegriit.com el 2026-11-10; 0017 copio lo ultimo de `public` al publicar.
El esquema `angels` ya esta expuesto en Supabase.

Pendiente:
- 0016 (permiso de borrar para el staff): solo con el permiso de Carlos.
- No hay 0002 (no aplica) ni 0008 (retencion: borraba datos viejos; Angels no la usa).
