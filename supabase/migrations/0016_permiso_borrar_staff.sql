-- =====================================================================
-- ANGELS - 0016 PERMISO DE BORRAR PARA EL STAFF (APROBADA POR CARLOS, 10 nov. 2026)
-- Aplicada el 10 nov. 2026. Sin esto, desde el panel del staff no se
-- puede borrar un registro, un dia de practica ni un torneo (los botones
-- de borrar fallan). Solo afecta al esquema angels y solo a cuentas staff.
-- =====================================================================
grant delete on angels.entries, angels.practice_days, angels.tournaments to authenticated;
