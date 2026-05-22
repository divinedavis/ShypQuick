-- Disable the seed-test-offer cron permanently.
--
-- Supabase Disk IO budget alert (2026-05-19) pinned it on the pg_net
-- response-table cleanup chasing 397 MB of bloat. The bloat was driven
-- by two */5 * * * * crons posting via net.http_post: this seed cron
-- (synthetic offers → push-new-offer edge fn) and sweep_pending_offers.
-- Killing the seed half + truncating net._http_response cuts the
-- write-amp roughly in half. The seeder function is kept around for
-- manual one-offs but no longer fires on a schedule.
do $$
begin
  perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'seed-test-offer-every-5-min';
end $$;
