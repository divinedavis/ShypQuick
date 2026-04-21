<div align="center">
  <h1>SHYP Quick</h1>

  <p><strong>Shyp all the items you want.</strong></p>

  <p>
    On-demand delivery for furniture, appliances, and everything in between —<br/>
    think Uber, but for the stuff that doesn't fit in an Uber.
  </p>

  <p>
    <img src="https://img.shields.io/badge/iOS-17%2B-000?logo=apple&logoColor=white" alt="iOS 17+" />
    <img src="https://img.shields.io/badge/SwiftUI-FA7343?logo=swift&logoColor=white" alt="SwiftUI" />
    <img src="https://img.shields.io/badge/Supabase-3ECF8E?logo=supabase&logoColor=white" alt="Supabase" />
    <img src="https://img.shields.io/badge/status-private%20TestFlight-orange" alt="Private TestFlight" />
  </p>

  <br />

  <table>
  <tr>
  <td align="center" width="33%">
    <img src="assets/screenshots/01-auth.png" width="240" alt="Welcome" />
    <br/><sub><b>Welcome</b><br/>Sign in with Apple or email.</sub>
  </td>
  <td align="center" width="33%">
    <img src="assets/screenshots/02-customer.png" width="240" alt="Customer home" />
    <br/><sub><b>Customer — Send a package</b><br/>Live map, address fields, same-hour rush toggle.</sub>
  </td>
  <td align="center" width="33%">
    <img src="assets/screenshots/03-driver.png" width="240" alt="Driver home" />
    <br/><sub><b>Driver — Go online</b><br/>One tap to start receiving jobs nearby.</sub>
  </td>
  </tr>
  </table>
</div>

---

## What is ShypQuick?

You bought a couch on Craigslist. A dresser from a yard sale. A flat-screen
from Best Buy. Now you need it home — today, not next Tuesday.

**ShypQuick is a two-sided on-demand delivery app.** Customers request a
driver, drivers accept within seconds, and everything in between —
navigation, live tracking, photo of the item, payout — happens in one place.

- **Big items.** Designed for the stuff other delivery apps won't touch.
- **Fast.** Request now, or schedule it for later. Same-hour rush available.
- **Fair.** Drivers keep **70%** of the fare. No opaque take-rate.

## How it works

<table>
<tr>
<th width="50%">🧍 For customers</th>
<th width="50%">🚗 For drivers</th>
</tr>
<tr valign="top">
<td>

1. Enter pickup and drop-off addresses
2. Pick item size — **Fits in a Car** or **Needs a Flatbed**
3. Snap a photo so the driver knows what they're picking up
4. **Request now**, or schedule for later
5. Watch the driver move toward you on the map
6. Rate the driver once delivered

</td>
<td>

1. Go online — a Dynamic Island banner shows you're live
2. Accept an incoming offer within the 5-minute window
3. **Apple Maps auto-launches** toward the pickup
4. Mark picked up → Apple Maps re-routes to drop-off
5. Mark delivered, keep 70% of the fare
6. Back online for the next job

</td>
</tr>
</table>

## Pricing

| | Small (Fits in a Car) | Large (Needs a Flatbed) |
|---|---:|---:|
| **Base fare** | $40 | $150 |
| **Long haul** | +$0.50/mi over 10 mi | +$0.50/mi over 10 mi |
| **Same-hour rush** | +$30 | +$30 |

## Tech stack

| Layer | Tools |
|---|---|
| **iOS app** | SwiftUI (iOS 17+), Swift 5.9, Swift Package Manager |
| **Maps & navigation** | MapKit, CoreLocation, Apple Maps hand-off |
| **Live Activity** | ActivityKit — the "Online" banner on the Lock Screen / Dynamic Island |
| **Backend** | Supabase — Postgres, Auth, Realtime, Storage |
| **Realtime dispatch** | Postgres `LISTEN/NOTIFY` → Supabase Realtime → in-app push offer |
| **Push notifications** | APNs via a Supabase Edge Function (Deno/TypeScript) |
| **Auth** | Email / password, Sign in with Apple |
| **Ship pipeline** | `deploy_testflight.sh` — archive → upload → auto-submit for beta review → attach to tester group, via the App Store Connect API |
| **Payments** *(planned)* | Stripe |

## Architecture at a glance

```
┌──────────────┐         ┌──────────────────────┐         ┌──────────────┐
│   Customer   │  posts  │   Supabase Postgres  │  INSERT │    Driver    │
│  (iOS app)   │ ──────▶ │  (job_offers table)  │ ──────▶ │  (iOS app)   │
└──────────────┘         └──────────┬───────────┘         └──────┬───────┘
                                    │                            │
                                    │  pg_net trigger            │ accepts
                                    ▼                            ▼
                        ┌──────────────────────┐         ┌──────────────┐
                        │  Edge Function       │ ──APNs─▶│   Apple Push │
                        │  (push-new-offer)    │         │  Notif. Svc. │
                        └──────────────────────┘         └──────────────┘
```

- Customers insert into `job_offers`.
- A database trigger fires a `pg_net` POST to the edge function.
- The edge function queries online drivers, signs an APNs JWT (ES256), and pushes to every registered device token. Dead tokens are purged on 410.
- Drivers subscribe to Supabase Realtime on the same table to get the offer inside the app even without a push.

## Status & roadmap

- [x] Two-sided app — customer + driver + both roles in one build
- [x] Instant and scheduled dispatch
- [x] Apple Maps navigation, end-to-end
- [x] Live Activity / Dynamic Island online banner
- [x] APNs push for new offers
- [x] Photo attachment on orders
- [ ] Stripe payments
- [ ] Persistent chat between customer and driver
- [ ] In-app ratings and reviews history
- [ ] Public App Store release

## Contact

Currently in **private TestFlight beta**. Reach out to request access or
send feedback.

---

<div align="center">
  <sub>Built with SwiftUI and Supabase in Brooklyn, NY.</sub>
</div>
