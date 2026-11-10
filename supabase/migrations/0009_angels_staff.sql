-- =====================================================================
-- ANGELS - 0009 CUENTAS DE STAFF
-- Solo estas cuentas ven y cambian datos de Angels (angels.is_staff()).
-- Son las mismas dos cuentas que ya entraban al panel de Angels.
-- =====================================================================
insert into angels.staff_users (email)
values ('carlos@voleii.com'), ('catd04@gmail.com')
on conflict (email) do nothing;
