# ShypQuick

**Shyp all the items you want.**

An on-demand delivery iOS app — think Uber, but for packages. Customers request a pickup, nearby drivers accept, pick up the item, and drop it off.

## Stack

- **iOS**: SwiftUI (iOS 17+), Swift Package Manager
- **Backend**: Supabase (Postgres + Auth + Realtime + Storage)
- **Maps**: MapKit + CoreLocation
- **Payments**: Stripe (planned)

## Architecture

Single app with a **role toggle** — users can switch between Customer and Driver modes, like early Uber. Auth state and role stored in Supabase `profiles` table.

```
ShypQuick/
├── App/              # App entry, root view, env setup
├── Features/
│   ├── Auth/         # Sign in / sign up / role selection
│   ├── Customer/     # Request delivery, track driver, history
│   ├── Driver/       # Go online, accept jobs, navigate, earnings
│   └── Shared/       # Map view, components shared by both roles
├── Models/           # Delivery, Profile, Location, etc.
├── Services/         # SupabaseClient, LocationService, etc.
└── Resources/        # Assets, Info.plist
```

## Core flows (MVP)

1. **Customer**: enter pickup + dropoff → see price estimate → request → track driver on map → rate driver
2. **Driver**: toggle online → receive nearby job requests → accept → navigate to pickup → confirm pickup → navigate to dropoff → confirm delivery → get paid
3. **Realtime**: Supabase Realtime channels push driver location updates to the customer during an active delivery

## Supabase schema (initial)

See `supabase/schema.sql` for the full schema. Tables:

- `profiles` — extends `auth.users`, stores role (`customer` | `driver` | `both`), name, phone, rating
- `deliveries` — pickup/dropoff coords + addresses, status, customer_id, driver_id, price, timestamps
- `driver_locations` — live lat/lng for online drivers (updated via Realtime)
- `ratings` — post-delivery ratings both directions

## Setup

1. Clone the repo
2. Open `ShypQuick.xcodeproj` in Xcode
3. Copy `ShypQuick/Resources/Secrets.example.plist` → `Secrets.plist` and fill in your Supabase URL + anon key
4. Run the Supabase schema: `supabase db push` (or paste `supabase/schema.sql` into the SQL editor)
5. Build & run on an iOS 17+ simulator or device

## Status

🚧 Scaffolding in progress.
