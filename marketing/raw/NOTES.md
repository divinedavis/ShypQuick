# SHYP Quick — raw marketing screenshots

Captured on simulator `PM-shots-K` (iPhone 17 Pro Max, iOS 26.5), simulated
location 40.7128,-74.0060, light appearance, status bar 9:41 / full battery
(charging) / full signal. All 5 PNGs verified at 1320x2868 via `sips`.

01-customer-home.png — Customer home screen: live NYC map, empty pickup/
dropoff fields, "Need it within the hour" rush toggle, collapsed Add-ons.
Entry point to the whole booking flow. — **Send big items**

02-pricing.png — Same screen with addresses filled, Truck selected,
Add-ons expanded (2 floors of stairs, two-man crew) and the full quote
breakdown showing Base $125 + Stairs $50 + Two-man crew $75 = $250.00
estimate. — **See your price upfront**

03-pickup-delivery.png — Driver-route screen right after requesting:
pickup/dropoff pins and route line on the map, addresses, 4.3 mi distance,
"Pickup by" time, $125.00 total, "Finding a driver…" status. — **Your
route, mapped**

04-live-tracking.png — Same screen once a driver is assigned: live driver
pin ("Marcus") moving along the route, "On the way to drop-off" banner
with ETA countdown, Delivery-by time, Message button. — **Watch it arrive
live**

05-driver-view.png — Driver's active-job screen: pickup/dropoff pins,
"Head to pickup" title, job card showing item type + "You earn $87.50",
Navigate/Message/Mark picked up controls. — **Drive, deliver, earn**

## How these were captured

No real account, no real order, no App Store Connect upload. Old captures
in `assets/screenshots/` (01-auth, 02-customer, 03-driver at 1206x2622)
were used only as a framing guide — none of that flow was populated enough
for a marketing shot, so populated-state screens came from launch
arguments instead.

The app already ships a DEBUG+simulator-only stub-login mechanism
(`-SHYP_UI_TEST 1`, optionally `-SHYP_UI_TEST_DRIVER 1` and
`-SHYP_UI_TEST_ACTIVE_JOB 1`) used by `ShypQuickUITests/PricingFlowUITests.swift`
and `DriverFlowUITests.swift` — no test account was found in the README,
scripts/, or the macOS keychain, so no real sign-in was attempted.

That mechanism didn't reach a populated pricing screen, a delivery-route
screen, or a live-tracking state, so three new DEBUG+simulator-only launch
args were added, following the exact same pattern as the existing ones:

- `-SHYP_UI_TEST_PRICING 1` (in `CustomerHomeView.swift`) — prefills
  pickup/dropoff + selects Truck + expands Add-ons so the quote breakdown
  renders, for screenshot 02.
- `-SHYP_UI_TEST_ROUTE 1` (in `CustomerHomeView.swift`) — pushes
  `DeliveryRouteView` with stub pickup/dropoff coords and a random offer
  id, for screenshot 03.
- `-SHYP_UI_TEST_ROUTE_ENROUTE 1` (in `DeliveryRouteView.swift`, only
  takes effect combined with `-SHYP_UI_TEST_ROUTE 1`) — overrides the
  polled delivery-simulation phase/driver position directly (no backend
  row needed) so the "on the way to drop-off" tracking state renders, for
  screenshot 04.

All three are wrapped in `#if DEBUG && targetEnvironment(simulator)`,
compiled out of every Release/device build, and were left **uncommitted**
per the task instructions — `git diff` shows the two touched files. No
network write, no Supabase auth call, and no payment flow were triggered;
`DeliveryRouteView`'s MKDirections route calc does hit Apple's map service
over the network (same as any real use of the screen).

Screenshot 05 used only the existing `-SHYP_UI_TEST_ACTIVE_JOB` arg — no
code change needed.
