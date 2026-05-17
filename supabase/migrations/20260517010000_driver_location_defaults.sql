-- ============================================================
-- driver_locations.lat/lng defaults
--
-- The radius-filtered dispatch (20260517000000) compares each
-- driver's stored location against the pickup. But the app was
-- writing lat/lng = 0,0 and never syncing real GPS, so the
-- server thought every driver sat in the Gulf of Guinea.
--
-- The app fix splits the write in two: setDriverOnline() now
-- updates only is_online, and updateDriverLocation() owns the
-- coordinates. For that to insert cleanly the first time a
-- driver toggles online, lat/lng need a default — otherwise the
-- NOT NULL constraint rejects the flag-only upsert.
-- ============================================================

alter table public.driver_locations alter column lat set default 0;
alter table public.driver_locations alter column lng set default 0;
