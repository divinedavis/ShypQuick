import SwiftUI
import MapKit
import CoreLocation

struct DriverHomeView: View {
    @State private var isOnline = false
    @StateObject private var location = LocationService.shared
    @StateObject private var dispatch = DispatchService.shared
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    private var visibleOffer: JobOffer? {
        guard isOnline, let offer = dispatch.pendingOffer else { return nil }
        guard let driverLoc = location.currentLocation else {
            return offer
        }
        let pickup = CLLocation(latitude: offer.pickupLat, longitude: offer.pickupLng)
        return driverLoc.distance(from: pickup) <= DispatchService.matchRadiusMeters ? offer : nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                }
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 12) {
                    if isOnline {
                        Text("You're online — waiting for jobs")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.green.opacity(0.2), in: Capsule())
                    }

                    Button {
                        isOnline.toggle()
                        if isOnline {
                            location.requestPermission()
                            location.startUpdating()
                        }
                    } label: {
                        Text(isOnline ? "Go offline" : "Go online")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isOnline ? .red : .green)
                }
                .padding()
            }
            .navigationTitle("Drive")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: location.currentLocation) { _, loc in
                guard let coord = loc?.coordinate else { return }
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                    )
                )
            }
            .fullScreenCover(item: Binding(
                get: { visibleOffer },
                set: { _ in }
            )) { offer in
                DriverJobOfferView(
                    offer: offer,
                    driverLocation: location.currentLocation,
                    onAccept: { dispatch.accept(offer) },
                    onDecline: { dispatch.decline(offer) }
                )
            }
            .fullScreenCover(item: $dispatch.activeJob) { job in
                DriverActiveJobView(job: job) {
                    dispatch.clearActiveJob()
                }
            }
        }
    }
}
