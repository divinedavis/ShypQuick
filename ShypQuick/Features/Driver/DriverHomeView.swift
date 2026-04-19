import SwiftUI
import MapKit
import CoreLocation

struct DriverHomeView: View {
    @State private var isOnline = false
    @State private var showSimulate = false
    @StateObject private var location = LocationService.shared
    @StateObject private var dispatch = DispatchService.shared
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    private func createFakeOrder() {
        let driverCoord = location.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442)
        let pickupLat = driverCoord.latitude + Double.random(in: -0.02...0.02)
        let pickupLng = driverCoord.longitude + Double.random(in: -0.02...0.02)
        let dropoffLat = driverCoord.latitude + Double.random(in: -0.05...0.05)
        let dropoffLng = driverCoord.longitude + Double.random(in: -0.05...0.05)
        let pickup = CLLocationCoordinate2D(latitude: pickupLat, longitude: pickupLng)
        let dropoff = CLLocationCoordinate2D(latitude: dropoffLat, longitude: dropoffLng)
        let size: ItemSize = Bool.random() ? .small : .large
        let sameHour = Bool.random()
        let quote = PricingService.quote(size: size, pickup: pickup, dropoff: dropoff, sameHour: sameHour)
        dispatch.postOffer(
            pickupAddress: "123 Test Pickup St, Brooklyn, NY",
            dropoffAddress: "456 Test Dropoff Ave, Brooklyn, NY",
            pickup: pickup,
            dropoff: dropoff,
            size: size,
            sameHour: sameHour,
            totalCents: quote.totalCents,
            photoData: nil,
            categoryTitle: size == .small ? "Fits in a Car" : "Needs a Flatbed",
            categoryIcon: size == .small ? "car.fill" : "truck.box.fill"
        )
    }

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
                            dispatch.startListening()
                            showSimulate = true
                        } else {
                            dispatch.stopListening()
                            showSimulate = false
                        }
                    } label: {
                        Text(isOnline ? "Go offline" : "Go online")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isOnline ? .red : .green)

                    if showSimulate {
                        Button {
                            createFakeOrder()
                            showSimulate = false
                        } label: {
                            Label("Simulate test order", systemImage: "play.circle.fill")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
                .padding()
            }
            .navigationTitle("Deliver")
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
