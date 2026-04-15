import SwiftUI
import MapKit

struct DeliveryRouteView: View {
    let pickupAddress: String
    let dropoffAddress: String
    let pickup: CLLocationCoordinate2D
    let dropoff: CLLocationCoordinate2D
    let quote: PricingService.Quote

    @StateObject private var simulation = DeliverySimulation()
    @State private var route: MKRoute?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition) {
                Marker("Pickup", systemImage: "shippingbox.fill", coordinate: pickup)
                    .tint(.green)
                Marker("Dropoff", systemImage: "mappin.circle.fill", coordinate: dropoff)
                    .tint(.red)
                if let route {
                    MapPolyline(route.polyline)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if let driverPos = simulation.driverPosition {
                    Annotation(simulation.driverName ?? "Driver", coordinate: driverPos) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 44, height: 44)
                                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                            Circle()
                                .strokeBorder(Color.blue, lineWidth: 3)
                                .frame(width: 44, height: 44)
                            Image(systemName: "car.fill")
                                .foregroundStyle(.blue)
                                .font(.title3)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .onChange(of: simulation.driverPosition?.latitude) { _, _ in
                updateCameraForSimulation()
            }
            .onChange(of: simulation.phase) { _, _ in
                updateCameraForSimulation()
            }
            .overlay(alignment: .top) {
                if isLoading {
                    ProgressView("Calculating route…")
                        .padding()
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 12)
                } else if simulation.phase != .idle {
                    phaseBanner
                        .padding(.top, 12)
                }
            }

            routeSummaryCard
        }
        .navigationTitle("Driver route")
        .navigationBarTitleDisplayMode(.inline)
        .task { await calculateRoute() }
        .onDisappear { simulation.cancel() }
    }

    private var phaseBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: phaseIcon)
            Text(simulation.phase.headline).font(.subheadline.bold())
            if let eta = simulation.etaSeconds, eta > 0 {
                Text("· \(eta)s").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }

    private var phaseIcon: String {
        switch simulation.phase {
        case .idle: return "clock"
        case .searching: return "magnifyingglass"
        case .assigned: return "person.fill.checkmark"
        case .enRouteToPickup: return "car.fill"
        case .atPickup: return "shippingbox.fill"
        case .enRouteToDropoff: return "arrow.right.circle.fill"
        case .delivered: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var routeSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(pickupAddress, systemImage: "circle.fill")
                    .font(.subheadline)
                Label(dropoffAddress, systemImage: "mappin.circle.fill")
                    .font(.subheadline)
            }

            if let route {
                HStack(spacing: 16) {
                    statBlock(
                        title: "Distance",
                        value: String(format: "%.1f mi", route.distance / 1609.344)
                    )
                    statBlock(
                        title: etaStat(for: route).label,
                        value: etaStat(for: route).value
                    )
                    statBlock(title: "Total", value: quote.dollars)
                }
            }

            Button {
                simulation.start(pickup: pickup, dropoff: dropoff)
            } label: {
                Text(findDriverButtonLabel)
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isFindDriverDisabled)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var findDriverButtonLabel: String {
        switch simulation.phase {
        case .idle, .failed: return "Find a driver"
        case .searching: return "Searching…"
        case .assigned, .enRouteToPickup: return "Driver en route"
        case .atPickup: return "At pickup"
        case .enRouteToDropoff: return "Delivering"
        case .delivered: return "Delivered ✓"
        }
    }

    private var isFindDriverDisabled: Bool {
        switch simulation.phase {
        case .idle, .failed: return false
        default: return true
        }
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calculateRoute() async {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: pickup.latitude, longitude: pickup.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: dropoff.latitude, longitude: dropoff.longitude), address: nil)
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let best = response.routes.first else {
                throw NSError(domain: "Route", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: "No route available."])
            }
            route = best
            cameraPosition = .rect(best.polyline.boundingMapRect.insetBy(dx: -2000, dy: -2000))
        } catch {
            errorMessage = "Couldn't calculate route: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func etaStat(for route: MKRoute) -> (label: String, value: String) {
        let now = Date()
        let deliveryDuration = route.expectedTravelTime
        let pickupLeg = simulation.driverToPickupSeconds ?? 0
        let handling = DeliverySimulation.pickupHandlingSeconds
        let anchor = simulation.dispatchedAt ?? now

        switch simulation.phase {
        case .idle, .failed:
            // No driver yet — times of day are unknown until we dispatch.
            return ("ETA", "TBD")

        case .searching, .assigned, .enRouteToPickup:
            // Driver is on their way to pickup — show expected pickup time.
            let pickupAt = anchor.addingTimeInterval(pickupLeg)
            return ("Pickup by", formatClock(pickupAt))

        case .atPickup, .enRouteToDropoff:
            // Package in hand — show expected delivery time.
            let deliveryAt = anchor.addingTimeInterval(pickupLeg + handling + deliveryDuration)
            return ("Delivery by", formatClock(deliveryAt))

        case .delivered:
            return ("Delivered at", formatClock(now))
        }
    }

    private func formatClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func updateCameraForSimulation() {
        guard let driver = simulation.driverPosition else { return }
        let target: CLLocationCoordinate2D
        switch simulation.phase {
        case .enRouteToPickup, .assigned, .searching, .atPickup:
            target = pickup
        case .enRouteToDropoff, .delivered:
            target = dropoff
        default:
            return
        }
        let rect = boundingRect(for: [driver, target], paddingMeters: 600)
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraPosition = .rect(rect)
        }
    }

    private func boundingRect(
        for coords: [CLLocationCoordinate2D],
        paddingMeters: Double
    ) -> MKMapRect {
        let points = coords.map { MKMapPoint($0) }
        var rect = MKMapRect.null
        for p in points {
            rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        let padding = paddingMeters * MKMapPointsPerMeterAtLatitude(coords.first?.latitude ?? 0)
        return rect.insetBy(dx: -padding, dy: -padding)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remaining = minutes % 60
        return "\(hours)h \(remaining)m"
    }
}
