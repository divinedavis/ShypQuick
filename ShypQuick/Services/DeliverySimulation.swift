import Foundation
import Combine
import CoreLocation
import MapKit
import Supabase

/// Tracks a customer's delivery against the REAL job_offers row.
///
/// This used to be a hardcoded local animation (12s to "picked up", 20s to
/// "delivered") decoupled from the driver. It now polls `offer_driver_info`
/// — a SECURITY DEFINER RPC scoped to the caller's own offer — so every
/// phase reflects what the driver actually did, and the map shows the
/// driver's real location. Instant "driver accepted" alerts arrive via APNs
/// (push-offer-status); this poll keeps the on-screen UI in sync.
@MainActor
final class DeliverySimulation: ObservableObject {
    enum Phase: Equatable {
        case idle
        case searching
        case assigned(driverName: String)
        case enRouteToPickup
        case atPickup
        case enRouteToDropoff
        case delivered
        case failed(String)

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }

        var headline: String {
            switch self {
            case .idle:                return "Ready"
            case .searching:           return "Finding a driver…"
            case .assigned(let name):  return "\(name) is on the way"
            case .enRouteToPickup:     return "Driver heading to pickup"
            case .atPickup:            return "Package picked up"
            case .enRouteToDropoff:    return "On the way to drop-off"
            case .delivered:           return "Delivered 🎉"
            case .failed(let msg):     return "Something went wrong: \(msg)"
            }
        }
    }

    @Published var phase: Phase = .idle
    @Published var driverPosition: CLLocationCoordinate2D?
    @Published var driverName: String?
    @Published var etaSeconds: Int?
    /// Real-world expected travel time (in seconds) for the driver to reach
    /// pickup, computed via MKDirections once a driver is assigned.
    @Published var driverToPickupSeconds: TimeInterval?
    /// The moment tracking began — anchor for absolute ETA times.
    @Published var dispatchedAt: Date?

    /// Flat handling buffer added between pickup-complete and dropoff-complete
    /// to account for the driver loading/handling the item.
    static let pickupHandlingSeconds: TimeInterval = 90

    private let client: SupabaseClient
    private let pollIntervalSeconds: UInt64 = 6
    private var pollTask: Task<Void, Never>?

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    /// Begin tracking a posted offer. `offerId` is the real job_offers row id
    /// returned by `DispatchService.postOffer`.
    func track(offerId: UUID, pickup: CLLocationCoordinate2D, dropoff: CLLocationCoordinate2D) {
        cancel()
        dispatchedAt = Date()
        phase = .searching
        pollTask = Task {
            while !Task.isCancelled {
                await poll(offerId: offerId, pickup: pickup, dropoff: dropoff)
                if case .delivered = phase { break }
                if phase.isFailed { break }
                try? await Task.sleep(nanoseconds: pollIntervalSeconds * 1_000_000_000)
            }
        }
    }

    func cancel() {
        pollTask?.cancel()
        pollTask = nil
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - Polling

    private struct DriverInfoRow: Decodable {
        let driver_id: String?
        let full_name: String?
        let driver_lat: Double?
        let driver_lng: Double?
        let status: String
    }

    private struct OfferIdParam: Encodable { let offer_id: UUID }

    private func poll(
        offerId: UUID,
        pickup: CLLocationCoordinate2D,
        dropoff: CLLocationCoordinate2D
    ) async {
        do {
            let rows: [DriverInfoRow] = try await client
                .rpc("offer_driver_info", params: OfferIdParam(offer_id: offerId))
                .execute()
                .value
            guard let row = rows.first else {
                // No row visible — offer not found or not ours. Keep waiting.
                return
            }
            await apply(row, pickup: pickup, dropoff: dropoff)
        } catch {
            // Transient network error — leave the current phase and retry on
            // the next tick.
            print("DeliverySimulation.poll error:", error)
        }
    }

    /// Map a real job_offers status onto a customer-facing phase.
    private func apply(
        _ row: DriverInfoRow,
        pickup: CLLocationCoordinate2D,
        dropoff: CLLocationCoordinate2D
    ) async {
        if let name = row.full_name, !name.isEmpty {
            driverName = name
        }
        // Only trust a real GPS fix — 0,0 means the driver's location hasn't
        // synced yet, so we leave the marker hidden rather than dropping it
        // in the Gulf of Guinea.
        if let lat = row.driver_lat, let lng = row.driver_lng,
           !(lat == 0 && lng == 0) {
            driverPosition = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        switch row.status {
        case "pending":
            phase = .searching

        case "accepted":
            phase = .enRouteToPickup
            if driverToPickupSeconds == nil, let from = driverPosition {
                driverToPickupSeconds = try? await routeTravelTime(from: from, to: pickup)
            }

        case "picked_up":
            phase = .enRouteToDropoff

        case "delivered":
            phase = .delivered

        case "declined", "expired", "cancelled":
            phase = .failed("This delivery didn't go through. Please try again.")

        default:
            break
        }
    }

    // MARK: - ETA helper

    private func routeTravelTime(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .automobile
        let response = try await MKDirections(request: request).calculate()
        return response.routes.first?.expectedTravelTime ?? 0
    }
}
