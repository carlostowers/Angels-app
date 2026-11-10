-- =====================================================================
-- ANGELS - 0016 PERMISO DE BORRAR PARA EL STAFF (PENDIENTE DE CARLOS)
-- No se aplica sin su permiso. Sin esto, desde el panel del staff no se
-- puede borrar un registro, un dia de practica ni un torneo (los botones
-- de borrar fallan). Solo afecta al esquema angels y solo a cuentas staff.
-- =====================================================================
grant delete on angels.entries, angels.practice_days, angels.tournaments to authenticated;
