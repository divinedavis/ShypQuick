-- Belt-and-suspenders retention for net._http_response.
--
-- pg_net's own cleanup uses pg_net.ttl which defaults to 6 hours on Supabase
-- and is not tunable (postmaster-context GUC). When request volume spikes
-- (a runaway trigger or unbounded cron loop) the 6-hour window lets the table
-- grow into the hundreds-of-MB / GB range and triggers Disk IO alerts.
--
-- This adds a project-owned retention cron that keeps the response table at
-- ≤1 hour of history, deleting in 10-minute increments. ShypQuick uses
-- net.http_post fire-and-forget — no code reads net._http_response back — so
-- 1h is generous for ad-hoc debugging while keeping the table bounded.

select cron.schedule(
  'pg-net-response-retention',
  '*/10 * * * *',
  $$ delete from net._http_response where created < now() - interval '1 hour'; $$
);
