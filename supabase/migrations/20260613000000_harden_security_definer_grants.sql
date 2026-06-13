-- Address Supabase security advisor warnings (08 Jun 2026 batch).
--
-- 1. anon_security_definer_function_executable / authenticated_…:
--    SECURITY DEFINER functions execute with the definer's (postgres) rights,
--    so any role that can EXECUTE them runs privileged code. Revoke EXECUTE
--    from anon/authenticated/PUBLIC on every SECURITY DEFINER function that is
--    NEVER called directly by the client with an anon/user JWT:
--      - trigger functions (PostgREST cannot invoke functions returning trigger)
--      - pg_cron jobs (run as postgres): sweep_pending_offers
--      - the disabled seed cron: seed_test_offer_if_drivers_online
--      - edge-function-only RPCs (invoked with the service_role key):
--        online_drivers_for_offer, find_closest_online_driver
--    The three client-facing RPCs (offer_driver_info, respond_to_offer_upgrade,
--    upgrade_offer_to_truck) and the RLS-helper predicates (is_driver,
--    is_delivery_counterparty, has_active_job_with_driver) are intentionally
--    callable by authenticated users and are left untouched.
--
-- 2. function_search_path_mutable on touch_updated_at: pin search_path so the
--    function can't be hijacked via a mutable search_path. The body only uses
--    now() (pg_catalog, always searched), so an empty search_path is safe.

do $$
declare
  f text;
  internal_fns text[] := array[
    'public.capture_on_delivered()',
    'public.handle_new_user()',
    'public.notify_new_offer()',
    'public.notify_offer_status_change()',
    'public.sweep_pending_offers()',
    'public.seed_test_offer_if_drivers_online()',
    'public.online_drivers_for_offer(double precision, double precision, text)',
    'public.find_closest_online_driver(double precision, double precision, text)'
  ];
begin
  foreach f in array internal_fns loop
    execute format('revoke all on function %s from public, anon, authenticated;', f);
    execute format('grant execute on function %s to service_role;', f);
  end loop;
end $$;

alter function public.touch_updated_at() set search_path = '';
