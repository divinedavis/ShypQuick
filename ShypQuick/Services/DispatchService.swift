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
    let same_hour: Bool
    let total_cents: Int
    let category_title: String
    let category_icon: String
    let photo_url: String?
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
        self.size = ItemSize(rawValue: row.size) ?? .small
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
        size: ItemSize, sameHour: Bool, totalCents: Int,
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

    private init() {}

    // MARK: - Customer: post offer to Supabase

    func postOffer(
        pickupAddress: String,
        dropoffAddress: String,
        pickup: CLLocationCoordinate2D,
        dropoff: CLLocationCoordinate2D,
        size: ItemSize,
        sameHour: Bool,
        totalCents: Int,
        photoData: Data?,
        categoryTitle: String,
        categoryIcon: String
    ) {
        guard !isPosting else { return }
        isPosting = true
        lastPostError = nil
        Task {
            defer { Task { @MainActor in self.isPosting = false } }
            do {
                let userId = try await client.auth.session.user.id

                // Upload photo if provided. If upload fails, we fail the
                // whole post rather than silently saving an offer with no
                // photo — the customer wanted that photo attached.
                var uploadedUrl: String?
                if let photoData {
                    let fileName = "\(UUID().uuidString).jpg"
                    try await client.storage
                        .from("item-photos")
                        .upload(fileName, data: photoData, options: .init(contentType: "image/jpeg"))
                    uploadedUrl = try client.storage.from("item-photos").getPublicURL(path: fileName).absoluteString
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
                    same_hour: sameHour,
                    total_cents: totalCents,
                    category_title: categoryTitle,
                    category_icon: categoryIcon,
                    photo_url: uploadedUrl
                )
                try await client
                    .from("job_offers")
                    .insert(insert)
                    .execute()
            } catch {
                print("DispatchService.postOffer error:", error)
                lastPostError = error.localizedDescription
                // Surface a local fallback so the simulation / route view can
                // still run for the customer, but keep the error visible.
                pendingOffer = JobOffer(
                    id: UUID(),
                    pickupAddress: pickupAddress,
                    dropoffAddress: dropoffAddress,
                    pickupLat: pickup.latitude, pickupLng: pickup.longitude,
                    dropoffLat: dropoff.latitude, dropoffLng: dropoff.longitude,
                    size: size, sameHour: sameHour, totalCents: totalCents,
                    photoData: photoData, categoryTitle: categoryTitle,
                    categoryIcon: categoryIcon, createdAt: Date()
                )
            }
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

    func decline(_ offer: JobOffer) {
        guard pendingOffer?.id == offer.id else { return }
        pendingOffer = nil
        Task {
            do {
                try await client
                    .from("job_offers")
                    .update(JobOfferUpdate(status: "declined", driver_id: nil))
                    .eq("id", value: offer.id)
                    .eq("status", value: "pending")
                    .execute()
            } catch {
                print("DispatchService.decline error:", error)
            }
        }
    }

    func expire(_ offer: JobOffer) {
        guard pendingOffer?.id == offer.id else { return }
        pendingOffer = nil
        Task {
            try? await client
                .from("job_offers")
                .update(JobOfferUpdate(status: "expired", driver_id: nil))
                .eq("id", value: offer.id)
                .execute()
        }
    }

    func setDriverOnline(_ online: Bool) {
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
                        is_online: online,
                        lat: 0, lng: 0
                    ))
                    .execute()
            } catch { }
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
}
