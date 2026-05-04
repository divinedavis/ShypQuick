import Foundation
import Combine
import CoreLocation
import MapKit
import Supabase

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
    /// Real-world expected travel time (in seconds) for the driver to reach pickup,
    /// computed via MKDirections once a driver is assigned.
    @Published var driverToPickupSeconds: TimeInterval?
    /// The moment `start()` was called — used as the anchor for absolute ETA times.
    @Published var dispatchedAt: Date?

    /// Flat handling buffer added between pickup-complete and dropoff-complete
    /// to account for the driver loading/handling the item.
    static let pickupHandlingSeconds: TimeInterval = 90

    private let client: SupabaseClient
    private let stepDurationSeconds: Double = 0.1 // tick interval
    private var animationTask: Task<Void, Never>?

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    func start(pickup: CLLocationCoordinate2D, dropoff: CLLocationCoordinate2D) {
        cancel()
        dispatchedAt = Date()
        phase = .searching
        animationTask = Task {
            do {
                guard let driver = try await findClosestDriver(to: pickup) else {
                    if !Task.isCancelled {
                        // Friendly copy: the offer was still posted and
                        // drivers will be pushed when they come online.
                        phase = .failed("No drivers online right now. We'll keep looking.")
                    }
                    return
                }
                if Task.isCancelled { return }
                driverName = driver.name
                driverPosition = driver.location
                phase = .assigned(driverName: driver.name)

                driverToPickupSeconds = try? await routeTravelTime(
                    from: driver.location, to: pickup
                )

                try? await Task.sleep(nanoseconds: 900_000_000)
                if Task.isCancelled { return }
                phase = .enRouteToPickup

                try await animate(
                    from: driver.location,
                    to: pickup,
                    routeMode: true,
                    durationSeconds: 12
                )
                if Task.isCancelled { return }
                phase = .atPickup
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { return }

                phase = .enRouteToDropoff
                try await animate(
                    from: pickup,
                    to: dropoff,
                    routeMode: true,
                    durationSeconds: 20
                )
                if !Task.isCancelled { phase = .delivered }
            } catch {
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }

    func cancel() {
        animationTask?.cancel()
        animationTask = nil
    }

    deinit {
        animationTask?.cancel()
    }

    // MARK: - Driver lookup

    private struct DriverRow: Decodable {
        let driver_id: String
        let lat: Double
        let lng: Double
    }

    private struct ProfileRow: Decodable {
        let id: String
        let full_name: String?
    }

    private struct AssignedDriver {
        let id: UUID
        let name: String
        var location: CLLocationCoordinate2D
    }

    /// Customers can't SELECT from driver_locations directly under the
    /// tightened RLS — they only see the driver's row once a job is
    /// accepted. This RPC is SECURITY DEFINER on the server side and
    /// returns just the closest match (name + coords) for the animation.
    private struct ClosestDriverRow: Decodable {
        let driver_id: String
        let full_name: String?
        let driver_lat: Double
        let driver_lng: Double
    }

    private struct ClosestDriverParams: Encodable {
        let pickup_lat: Double
        let pickup_lng: Double
    }

    private func findClosestDriver(to pickup: CLLocationCoordinate2D) async throws -> AssignedDriver? {
        let rows: [ClosestDriverRow] = try await client
            .rpc(
                "find_closest_online_driver",
                params: ClosestDriverParams(
                    pickup_lat: pickup.latitude,
                    pickup_lng: pickup.longitude
                )
            )
            .execute()
            .value

        guard let row = rows.first,
              let uuid = UUID(uuidString: row.driver_id) else {
            return nil
        }
        return AssignedDriver(
            id: uuid,
            name: row.full_name ?? "Your driver",
            location: CLLocationCoordinate2D(latitude: row.driver_lat, longitude: row.driver_lng)
        )
    }

    // MARK: - Animation

    private func animate(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        routeMode: Bool,
        durationSeconds: Double
    ) async throws {
        let points = try await routePoints(from: from, to: to) ?? [from, to]
        let steps = max(30, Int(durationSeconds / stepDurationSeconds))
        let interpolated = resample(points, count: steps)

        for (i, coord) in interpolated.enumerated() {
            if Task.isCancelled { return }
            driverPosition = coord
            let remainingSteps = interpolated.count - i
            etaSeconds = Int(Double(remainingSteps) * stepDurationSeconds)
            try? await Task.sleep(nanoseconds: UInt64(stepDurationSeconds * 1_000_000_000))
        }
        etaSeconds = 0
    }

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

    private func routePoints(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async throws -> [CLLocationCoordinate2D]? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .automobile
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return nil }
            let pointCount = route.polyline.pointCount
            var coords = [CLLocationCoordinate2D](
                repeating: CLLocationCoordinate2D(),
                count: pointCount
            )
            route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
            return coords
        } catch {
            return nil
        }
    }

    private func resample(_ points: [CLLocationCoordinate2D], count: Int) -> [CLLocationCoordinate2D] {
        guard points.count > 1, count > 1 else { return points }
        var distances: [Double] = [0]
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let b = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            distances.append(distances.last! + a.distance(from: b))
        }
        let total = distances.last!
        guard total > 0 else { return Array(repeating: points.first!, count: count) }

        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let target = total * Double(i) / Double(count - 1)
            var j = 0
            while j < distances.count - 1 && distances[j+1] < target { j += 1 }
            let d0 = distances[j]
            let d1 = distances[min(j+1, distances.count - 1)]
            let t = d1 == d0 ? 0 : (target - d0) / (d1 - d0)
            let p0 = points[j]
            let p1 = points[min(j+1, points.count - 1)]
            let lat = p0.latitude + (p1.latitude - p0.latitude) * t
            let lng = p0.longitude + (p1.longitude - p0.longitude) * t
            result.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        return result
    }
}
