import SwiftUI
import MapKit

struct DeliveryRouteView: View {
    let pickupAddress: String
    let dropoffAddress: String
    let pickup: CLLocationCoordinate2D
    let dropoff: CLLocationCoordinate2D
    let quote: PricingService.Quote

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
            }
            .mapStyle(.standard(elevation: .realistic))
            .overlay(alignment: .top) {
                if isLoading {
                    ProgressView("Calculating route…")
                        .padding()
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 12)
                }
            }

            routeSummaryCard
        }
        .navigationTitle("Driver route")
        .navigationBarTitleDisplayMode(.inline)
        .task { await calculateRoute() }
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
                        title: "ETA",
                        value: formatDuration(route.expectedTravelTime)
                    )
                    statBlock(title: "Total", value: quote.dollars)
                }
            }

            Button {
                // TODO: dispatch + save delivery to Supabase
            } label: {
                Text("Find a driver")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial)
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

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remaining = minutes % 60
        return "\(hours)h \(remaining)m"
    }
}
