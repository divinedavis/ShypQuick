-- ============================================================
-- Dispatch gate tests
--
-- Repeatable assertions for the region + radius matching logic —
-- the gates behind the recurring "SC driver gets NY orders" bug.
-- Run with: ./scripts/test_db.sh
-- A failed assert raises an exception, which the runner reports.
-- ============================================================
do $$
begin
  -- ── pickup_state: parse the state from a pickup address ──────
  assert public.pickup_state('475 Alabama Ave, Brooklyn, NY, United States') = 'NY',
    'comma-delimited state with United States suffix';
  assert public.pickup_state('Brooklyn Museum, NY') = 'NY',
    'state as the final token';
  assert public.pickup_state('Sandhills, Columbia, SC') = 'SC',
    'SC pickup, comma-delimited';
  assert public.pickup_state('The Preserve at Spears Creek, Elgin SC') = 'SC',
    'space-delimited "City ST" form the geocoder also emits';
  assert public.pickup_state('123 Main St, Brooklyn, NY 11207, United States') = 'NY',
    'state followed by a ZIP';
  assert public.pickup_state('A place with no state') is null,
    'unparseable address yields NULL';

  -- ── driver_serves_pickup_state: region gate ─────────────────
  -- The exact bug: an SC driver must NOT match an NY pickup.
  assert public.driver_serves_pickup_state(array['Sc'], 'SC',
    '475 Alabama Ave, Brooklyn, NY, United States') = false,
    'SC driver is excluded from an NY pickup';
  assert public.driver_serves_pickup_state(array['Sc'], 'SC',
    'Sandhills, Columbia, SC') = true,
    'SC driver matches an SC pickup (case-insensitive)';
  assert public.driver_serves_pickup_state(array['NY','SC'], 'NY',
    'Brooklyn Museum, NY') = true,
    'multi-state driver matches a listed state';
  -- Missing data must fail OPEN, never silently block dispatch.
  assert public.driver_serves_pickup_state(array[]::text[], null,
    'Brooklyn Museum, NY') = true,
    'driver with no declared region is not blocked';
  assert public.driver_serves_pickup_state(array['SC'], 'SC',
    'an address with no parseable state') = true,
    'unparseable pickup state is not blocked';

  -- ── miles_between: equirectangular distance ─────────────────
  assert public.miles_between(34.0, -81.0, 40.66, -73.88) between 400 and 800,
    'Columbia SC -> Brooklyn NY is a few hundred miles';
  assert public.miles_between(40.0, -73.0, 40.0, -73.0) = 0,
    'identical points are zero miles apart';

  raise notice 'dispatch_gates_test: ALL ASSERTIONS PASSED';
end $$;
