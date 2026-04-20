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
        self.categoryTitle = row.categoryTitle
        self.categoryIcon = row.categoryIcon
        self.createdAt = row.createdAt ?? Date()
    }

    init(
        id: UUID, pickupAddress: String, dropoffAddress: String,
        pickupLat: Double, pickupLng: Double,
        dropoffLat: Double, dropoffLng: Double,
        size: ItemSize, sameHour: Bool, totalCents: Int,
        photoData: Data?, categoryTitle: String, categoryIcon: String,
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
        Task {
            do {
                let userId = try await client.auth.session.user.id
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
                    category_icon: categoryIcon
                )
                try await client
                    .from("job_offers")
                    .insert(insert)
                    .execute()
            } catch {
                // Fallback to local-only if DB write fails
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

    func startListening() {
        Task {
            // Fetch any existing pending offers
            await fetchPendingOffers()

            // Subscribe to realtime inserts
            let channel = client.realtimeV2.channel("job_offers")
            let insertions = channel.postgresChange(InsertAction.self, table: "job_offers")

            await channel.subscribe()
            self.realtimeChannel = channel

            for await insertion in insertions {
                do {
                    let row = try insertion.decodeRecord(as: JobOfferRow.self, decoder: JSONDecoder())
                    if row.status == "pending" {
                        self.pendingOffer = JobOffer(row: row)
                    }
                } catch {
                    // Decode error — skip
                }
            }
        }
    }

    func stopListening() {
        Task {
            if let channel = realtimeChannel {
                await client.realtimeV2.removeChannel(channel)
                realtimeChannel = nil
            }
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
        guard pendingOffer?.id == offer.id else { return }
        activeJob = offer
        pendingOffer = nil
        Task {
            do {
                let userId = try await client.auth.session.user.id
                try await client
                    .from("job_offers")
                    .update(JobOfferUpdate(status: "accepted", driver_id: userId))
                    .eq("id", value: offer.id)
                    .execute()
            } catch { }
        }
    }

    func decline(_ offer: JobOffer) {
        guard pendingOffer?.id == offer.id else { return }
        pendingOffer = nil
        Task {
            try? await client
                .from("job_offers")
                .update(JobOfferUpdate(status: "declined", driver_id: nil))
                .eq("id", value: offer.id)
                .execute()
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
