import Foundation
import CoreLocation
import Combine
import Supabase
import Realtime

// MARK: - Database row model

struct JobOfferRow: Codable, Identifiable, Equatable {
    let id: UUID
    let customerId: UUID
    let pickupAddress: String
    let dropoffAddress: String
    let pickupLat: Double
    let pickupLng: Double
    let dropoffLat: Double
    let dropoffLng: Double
    let size: String
    let vehicleType: String?
    let sameHour: Bool
    let totalCents: Int
    let categoryTitle: String
    let categoryIcon: String
    let status: String
    let driverId: UUID?
    let photoUrl: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case customerId = "customer_id"
        case pickupAddress = "pickup_address"
        case dropoffAddress = "dropoff_address"
        case pickupLat = "pickup_lat"
        case pickupLng = "pickup_lng"
        case dropoffLat = "dropoff_lat"
        case dropoffLng = "dropoff_lng"
        case size
        case vehicleType = "vehicle_type"
        case sameHour = "same_hour"
        case totalCents = "total_cents"
        case categoryTitle = "category_title"
        case categoryIcon = "category_icon"
        case status
        case driverId = "driver_id"
        case photoUrl = "photo_url"
        case createdAt = "created_at"
    }
}

// MARK: - Insert model

private struct JobOfferInsert: Encodable {
    let customer_id: UUID
    let pickup_address: String
    let dropoff_address: String
    let pickup_lat: Double
    let pickup_lng: Double
    let dropoff_lat: Double
    let dropoff_lng: Double
    let size: String
    let vehicle_type: String
    let same_hour: Bool
    let total_cents: Int
    let category_title: String
    let category_icon: String
    let photo_url: String?
    let payment_intent_id: String?
    let authorized_amount_cents: Int?
    let payment_status: String
}

private struct JobOfferUpdate: Encodable {
    let status: String
    let driver_id: UUID?
}

// MARK: - In-app model (extends row with local-only fields)

struct JobOffer: Identifiable, Equatable {
    let id: UUID
    let pickupAddress: String
    let dropoffAddress: String
    let pickupLat: Double
    let pickupLng: Double
    let dropoffLat: Double
    let dropoffLng: Double
    let size: ItemSize
    /// "car" or "truck" — set explicitly by the customer; falls back to
    /// size when an older row predates the column.
    let vehicleType: String
    let sameHour: Bool
    let totalCents: Int
    let photoData: Data?
    let photoUrl: String?
    let categoryTitle: String
    let categoryIcon: String
    let createdAt: Date

    var pickupCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: pickupLat, longitude: pickupLng)
    }
    var dropoffCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: dropoffLat, longitude: dropoffLng)
    }

    init(row: JobOfferRow) {
        self.id = row.id
        self.pickupAddress = row.pickupAddress
        self.dropoffAddress = row.dropoffAddress
        self.pickupLat = row.pickupLat
        self.pickupLng = row.pickupLng
        self.dropoffLat = row.dropoffLat
        self.dropoffLng = row.dropoffLng
        let resolvedSize = ItemSize(rawValue: row.size) ?? .small
        self.size = resolvedSize
        self.vehicleType = row.vehicleType ?? (resolvedSize == .small ? "car" : "truck")
        self.sameHour = row.sameHour
        self.totalCents = row.totalCents
        self.photoData = nil
        self.photoUrl = row.photoUrl
        self.categoryTitle = row.categoryTitle
        self.categoryIcon = row.categoryIcon
        self.createdAt = row.createdAt ?? Date()
    }

    init(
        id: UUID, pickupAddress: String, dropoffAddress: String,
        pickupLat: Double, pickupLng: Double,
        dropoffLat: Double, dropoffLng: Double,
        size: ItemSize, vehicleType: String, sameHour: Bool, totalCents: Int,
        photoData: Data?, photoUrl: String? = nil,
        categoryTitle: String, categoryIcon: String,
        createdAt: Date
    ) {
        self.id = id
        self.pickupAddress = pickupAddress
        self.dropoffAddress = dropoffAddress
        self.pickupLat = pickupLat
        self.pickupLng = pickupLng
        self.dropoffLat = dropoffLat
        self.dropoffLng = dropoffLng
        self.size = size
        self.vehicleType = vehicleType
        self.sameHour = sameHour
        self.totalCents = totalCents
        self.photoData = photoData
        self.photoUrl = photoUrl
        self.categoryTitle = categoryTitle
        self.categoryIcon = categoryIcon
        self.createdAt = createdAt
    }
}

// MARK: - DispatchService

@MainActor
final class DispatchService: ObservableObject {
    static let shared = DispatchService()
    static let matchRadiusMeters: Double = 16_093.4 // 10 miles

    @Published var pendingOffer: JobOffer?
    @Published var activeJob: JobOffer?
    @Published var notificationTapped = false
    @Published private(set) var isAccepting = false
    @Published private(set) var isPosting = false
    @Published var lastPostError: String?
    /// Set when the driver taps a stale push notification for an offer that
    /// is no longer pending. `DriverHomeView` shows this as an alert and
    /// clears it.
    @Published var tappedOfferUnavailable: String?

    private var client: SupabaseClient { SupabaseService.shared.client }
    private var realtimeChannel: RealtimeChannelV2?

    private init() {
        #if DEBUG && targetEnvironment(simulator)
        // `-SHYP_UI_TEST_ACTIVE_JOB 1` seeds a deterministic active job so
        // XCUITest can exercise DriverActiveJobView (pickup → delivery)
        // without a live accepted offer.
        if UserDefaults.standard.bool(forKey: "SHYP_UI_TEST_ACTIVE_JOB") {
            activeJob = JobOffer(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000aa")!,
                pickupAddress: "475 Alabama Ave, Brooklyn, NY",
                dropoffAddress: "Linden Blvd, South Ozone Park, NY",
                pickupLat: 40.6646, pickupLng: -73.8966,
                dropoffLat: 40.6712, dropoffLng: -73.9636,
                size: .large, vehicleType: "truck", sameHour: false,
                totalCents: 12_500, photoData: nil,
                categoryTitle: "Truck", categoryIcon: "truck.box.fill",
                createdAt: Date()
            )
        }
        #endif
    }

    // MARK: - Photo URL resolution
    //
    // The bucket is private. `photoUrl` on a row is the storage object path
    // (e.g. "<customer-uuid>/<random>.jpg"). The viewer mints a short-lived
    // signed URL via this helper. Storage RLS lets the customer read their
    // own uploads, the assigned driver read the offer's photo, and any
    // driver read pending unassigned offer photos.
    func signedPhotoURL(forPath path: String, expiresIn seconds: Int = 60 * 60) async -> URL? {
        do {
            return try await client.storage
                .from("item-photos")
                .createSignedURL(path: path, expiresIn: seconds)
        } catch {
            print("DispatchService.signedPhotoURL error:", error)
            return nil
        }
    }

    // MARK: - Customer: post offer to Supabase

    /// Posts the job offer and returns the created `JobOffer` (with its real
    /// DB id) so the customer's `DeliveryRouteView` can track it live.
    /// Returns nil on failure — `lastPostError` carries the reason.
    @discardableResult
    func postOffer(
        pickupAddress: String,
        dropoffAddress: String,
        pickup: CLLocationCoordinate2D,
        dropoff: CLLocationCoordinate2D,
        size: ItemSize,
        vehicleType: String,
        sameHour: Bool,
        totalCents: Int,
        photoData: Data?,
        categoryTitle: String,
        categoryIcon: String,
        paymentIntentId: String? = nil,
        authorizedAmountCents: Int? = nil
    ) async -> JobOffer? {
        guard !isPosting else { return nil }
        isPosting = true
        lastPostError = nil
        defer { isPosting = false }
        do {
            let userId = try await client.auth.session.user.id

            // Upload photo if provided. If upload fails, we fail the
            // whole post rather than silently saving an offer with no
            // photo — the customer wanted that photo attached. Bucket is
            // private; we store the object path (not a public URL) and
            // the viewer mints a signed URL on demand.
            var uploadedUrl: String?
            if let photoData {
                // Storage RLS compares folder against auth.uid()::text which
                // Postgres formats lowercase; Swift's uuidString is uppercase.
                // Force lowercase on both segments so the policy match holds.
                let path = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
                try await client.storage
                    .from("item-photos")
                    .upload(path, data: photoData, options: .init(contentType: "image/jpeg"))
                uploadedUrl = path
            }

            let insert = JobOfferInsert(
                customer_id: userId,
                pickup_address: pickupAddress,
                dropoff_address: dropoffAddress,
                pickup_lat: pickup.latitude,
                pickup_lng: pickup.longitude,
                dropoff_lat: dropoff.latitude,
                dropoff_lng: dropoff.longitude,
                size: size.rawValue,
                vehicle_type: vehicleType,
                same_hour: sameHour,
                total_cents: totalCents,
                category_title: categoryTitle,
                category_icon: categoryIcon,
                photo_url: uploadedUrl,
                payment_intent_id: paymentIntentId,
                authorized_amount_cents: paymentIntentId == nil
                    ? nil : (authorizedAmountCents ?? totalCents),
                payment_status: paymentIntentId == nil ? "unauthorized" : "authorized"
            )
            // .select() so we get the inserted row back — its id is what the
            // customer's tracking screen subscribes to.
            let rows: [JobOfferRow] = try await client
                .from("job_offers")
                .insert(insert)
                .select()
                .execute()
                .value
            guard let row = rows.first else {
                lastPostError = "Couldn't create the delivery. Please try again."
                return nil
            }
            return JobOffer(row: row)
        } catch {
            print("DispatchService.postOffer error:", error)
            lastPostError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Driver: subscribe to new offers

    private var listenTask: Task<Void, Never>?

    func startListening() {
        // Prevent duplicate listeners
        guard realtimeChannel == nil else {
            // Already listening — just re-fetch
            Task { await fetchPendingOffers() }
            return
        }

        listenTask = Task {
            // Fetch any existing pending offers
            await fetchPendingOffers()

            // Subscribe to realtime inserts
            let channel = client.realtimeV2.channel("job_offers")
            let insertions = channel.postgresChange(InsertAction.self, table: "job_offers")

            await channel.subscribe()
            self.realtimeChannel = channel

            for await insertion in insertions {
                guard !Task.isCancelled else { break }
                do {
                    let row = try insertion.decodeRecord(as: JobOfferRow.self, decoder: JSONDecoder())
                    if row.status == "pending" {
                        self.pendingOffer = JobOffer(row: row)
                    }
                } catch {
                    print("DispatchService realtime decode error:", error)
                }
            }
        }
    }

    func stopListening() {
        listenTask?.cancel()
        listenTask = nil
        Task {
            if let channel = realtimeChannel {
                await client.realtimeV2.removeChannel(channel)
                realtimeChannel = nil
            }
        }
    }

    /// Look up a specific offer by id and decide what to do with it when the
    /// driver taps an APNs notification. If the offer is still `pending`, we
    /// promote it so the accept/decline screen appears; otherwise we set
    /// `tappedOfferUnavailable` so the UI can show a "no longer available"
    /// alert instead of silently doing nothing (or, worse, showing an
    /// unrelated offer that `fetchPendingOffers` happens to return).
    func handleTappedOffer(id: UUID) async {
        do {
            let rows: [JobOfferRow] = try await client
                .from("job_offers")
                .select()
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else {
                tappedOfferUnavailable = "This job is no longer available."
                pendingOffer = nil
                return
            }
            if row.status == "pending" {
                pendingOffer = JobOffer(row: row)
            } else {
                // Anything else — accepted, declined, expired, delivered —
                // means someone else already handled it (or we did on another
                // device).
                pendingOffer = nil
                tappedOfferUnavailable = "This job is no longer available."
            }
        } catch {
            print("DispatchService.handleTappedOffer error:", error)
            tappedOfferUnavailable = "Couldn't load that job. Please try again."
        }
    }

    private func fetchPendingOffers() async {
        do {
            let rows: [JobOfferRow] = try await client
                .from("job_offers")
                .select()
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            if let row = rows.first {
                pendingOffer = JobOffer(row: row)
            }
        } catch {
            // No pending offers or not signed in
        }
    }

    // MARK: - Driver: accept / decline

    func accept(_ offer: JobOffer) {
        guard !isAccepting else { return }
        guard pendingOffer?.id == offer.id else { return }
        isAccepting = true
        Task {
            defer { Task { @MainActor in self.isAccepting = false } }
            do {
                let userId = try await client.auth.session.user.id
                // Only transition if still `pending` — the DB filter plus RLS
                // enforce that another driver couldn't have beaten us here.
                let rows: [JobOfferRow] = try await client
                    .from("job_offers")
                    .update(JobOfferUpdate(status: "accepted", driver_id: userId))
                    .eq("id", value: offer.id)
                    .eq("status", value: "pending")
                    .select()
                    .execute()
                    .value
                guard !rows.isEmpty else {
                    // Someone else already accepted — clear without promoting.
                    pendingOffer = nil
                    return
                }
                activeJob = offer
                pendingOffer = nil
            } catch {
                print("DispatchService.accept error:", error)
                pendingOffer = nil
            }
        }
    }

    /// A driver passes on an offer card — by tapping Decline or letting the
    /// countdown lapse. This is LOCAL ONLY and must NOT touch the DB: one
    /// driver passing can't kill the offer for everyone. The offer stays
    /// `pending` and `sweep_pending_offers` keeps re-broadcasting it to
    /// local drivers until one accepts.
    func decline(_ offer: JobOffer) {
        guard pendingOffer?.id == offer.id else { return }
        pendingOffer = nil
    }

    /// A driver's offer-card countdown lapsed. Same as `decline` — a local
    /// dismissal only, never a DB write.
    func expire(_ offer: JobOffer) {
        decline(offer)
    }

    /// Flips the driver's online flag in driver_locations. Deliberately does
    /// NOT write lat/lng — those are owned by `updateDriverLocation`, and
    /// writing 0,0 here would clobber a real GPS fix and make the server
    /// think the driver is in the Gulf of Guinea (which broke radius
    /// matching entirely). The lat/lng columns default to 0, so the very
    /// first flag-only upsert for a brand-new driver still inserts cleanly;
    /// `updateDriverLocation` corrects the coordinates on the first fix.
    func setDriverOnline(_ online: Bool) {
        Task {
            do {
                let userId = try await client.auth.session.user.id
                struct OnlineFlagRow: Encodable {
                    let driver_id: UUID
                    let is_online: Bool
                }
                try await client
                    .from("driver_locations")
                    .upsert(OnlineFlagRow(driver_id: userId, is_online: online))
                    .execute()
            } catch { }
        }
    }

    /// Pushes the driver's live GPS coordinate to driver_locations so the
    /// dispatcher can match offers against their travel-radius preference.
    /// Without this the server only ever saw 0,0 and a driver in SC was
    /// offered pickups in NY. Called whenever LocationService emits a fresh
    /// fix while the driver is online.
    func updateDriverLocation(_ coordinate: CLLocationCoordinate2D) {
        Task {
            do {
                let userId = try await client.auth.session.user.id
                struct DriverLocationRow: Encodable {
                    let driver_id: UUID
                    let is_online: Bool
                    let lat: Double
                    let lng: Double
                }
                try await client
                    .from("driver_locations")
                    .upsert(DriverLocationRow(
                        driver_id: userId,
                        is_online: true,
                        lat: coordinate.latitude,
                        lng: coordinate.longitude
                    ))
                    .execute()
            } catch { }
        }
    }

    /// Driver confirms the item is in hand. Flips the job to `picked_up`,
    /// which fires the on_job_offer_status_change trigger so the customer
    /// gets a "picked up" push and their tracking screen advances. Keeps
    /// driver_id intact — the driver still owns the job.
    func markPickedUp(_ job: JobOffer) async {
        struct StatusUpdate: Encodable { let status: String }
        do {
            try await client
                .from("job_offers")
                .update(StatusUpdate(status: "picked_up"))
                .eq("id", value: job.id)
                .eq("status", value: "accepted")
                .execute()
        } catch {
            print("DispatchService.markPickedUp error:", error)
        }
    }

    func completeActiveJob() {
        guard let job = activeJob else { return }
        activeJob = nil
        Task {
            try? await client
                .from("job_offers")
                .update(JobOfferUpdate(status: "delivered", driver_id: nil))
                .eq("id", value: job.id)
                .execute()
        }
    }

    /// Customer's response to a driver-proposed Car→Truck upgrade. Approving
    /// applies the new price + vehicle server-side; declining clears the
    /// proposal and the job stays a Car.
    func respondToUpgrade(
        offerId: UUID,
        approve: Bool,
        paymentIntentId: String? = nil,
        authorizedCents: Int? = nil
    ) async {
        struct UpgradeReply: Encodable {
            let p_offer_id: UUID
            let p_approve: Bool
            // Synthesized Codable omits nil optionals, so the RPC falls back
            // to its defaults when no re-authorized hold is supplied.
            let p_payment_intent_id: String?
            let p_authorized_cents: Int?
        }
        do {
            _ = try await client
                .rpc("respond_to_offer_upgrade",
                     params: UpgradeReply(
                        p_offer_id: offerId,
                        p_approve: approve,
                        p_payment_intent_id: paymentIntentId,
                        p_authorized_cents: authorizedCents))
                .execute()
        } catch {
            print("DispatchService.respondToUpgrade error:", error)
        }
    }

    // MARK: - Driver: upgrade active job to a Truck

    private struct UpgradeParams: Encodable { let p_offer_id: UUID }
    private struct UpgradeResponse: Decodable {
        let old_total_cents: Int
        let new_total_cents: Int
        let difference_cents: Int
    }

    /// Asks the server to flip the active job from Car to Truck and bump
    /// the price accordingly. Returns nil on success, or an error message
    /// suitable for the UI on failure. On success, refreshes the local
    /// `activeJob` so the driver's view reflects the new total + label.
    func upgradeActiveJobToTruck() async -> String? {
        guard let job = activeJob else { return "No active job." }
        guard job.vehicleType == "car" else { return "This job is already a Truck." }
        do {
            // The RPC now records a PROPOSAL and pings the customer — it
            // does not apply the price change. The job's vehicle/price flip
            // only when the customer approves, so `activeJob` is left as-is.
            let _: UpgradeResponse = try await client
                .rpc("upgrade_offer_to_truck", params: UpgradeParams(p_offer_id: job.id))
                .execute()
                .value
            return nil
        } catch {
            print("DispatchService.upgradeActiveJobToTruck error:", error)
            return error.localizedDescription
        }
    }
}
