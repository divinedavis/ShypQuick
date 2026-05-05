import SwiftUI
import MapKit

struct DriverActiveJobView: View {
    let initialJob: JobOffer
    let onComplete: () -> Void

    @ObservedObject private var dispatch = DispatchService.shared
    @State private var cameraPosition: MapCameraPosition
    @State private var pickedUp = false
    @State private var showingUpgradeAlert = false
    @State private var upgradeError: String?
    @State private var isUpgrading = false

    init(job: JobOffer, onComplete: @escaping () -> Void) {
        self.initialJob = job
        self.onComplete = onComplete
        let midLat = (job.pickupLat + job.dropoffLat) / 2
        let midLng = (job.pickupLng + job.dropoffLng) / 2
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: midLat, longitude: midLng),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        ))
    }

    /// Prefer the live activeJob (reflects post-upgrade price) over the
    /// captured initial value.
    private var job: JobOffer { dispatch.activeJob ?? initialJob }

    private var driverEarningsCents: Int {
        Int(Double(job.totalCents) * 0.70)
    }

    private var truckUpgradeDifferenceCents: Int { 15_000 - 4_000 }

    /// Open Apple Maps with driving directions to the given coordinate.
    /// Source is omitted so Maps uses the device's current location.
    private func openInMaps(coord: CLLocationCoordinate2D, name: String) {
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    Marker("Pickup", systemImage: "circle.fill", coordinate: job.pickupCoord)
                        .tint(.green)
                    Marker("Dropoff", systemImage: "mappin.circle.fill", coordinate: job.dropoffCoord)
                        .tint(.red)
                }
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: job.categoryIcon).foregroundStyle(.tint)
                            Text(job.categoryTitle).font(.headline)
                            Spacer()
                            Text("You earn \(PricingService.Quote.format(driverEarningsCents))")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                        }

                        if pickedUp {
                            Label("Picked up — heading to dropoff", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                        }

                        Label(job.pickupAddress, systemImage: "circle.fill").font(.subheadline)
                        Label(job.dropoffAddress, systemImage: "mappin.circle.fill").font(.subheadline)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                    Button {
                        if pickedUp {
                            openInMaps(coord: job.dropoffCoord, name: "Dropoff — \(job.dropoffAddress)")
                        } else {
                            openInMaps(coord: job.pickupCoord, name: "Pickup — \(job.pickupAddress)")
                        }
                    } label: {
                        Label(
                            pickedUp ? "Navigate to dropoff" : "Navigate to pickup",
                            systemImage: "arrow.triangle.turn.up.right.diamond.fill"
                        )
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(pickedUp ? .red : .green)

                    if !pickedUp && job.vehicleType == "car" {
                        Button {
                            showingUpgradeAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "truck.box.fill")
                                Text("Need a Truck? +\(PricingService.Quote.format(truckUpgradeDifferenceCents))")
                                    .bold()
                                if isUpgrading { ProgressView().tint(.white) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(isUpgrading)
                    }

                    HStack(spacing: 12) {
                        NavigationLink {
                            ChatView(isDriver: true)
                        } label: {
                            Label("Message", systemImage: "message.fill")
                                .bold()
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)

                        if !pickedUp {
                            Button {
                                withAnimation { pickedUp = true }
                            } label: {
                                Text("Mark picked up")
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        } else {
                            Button {
                                onComplete()
                            } label: {
                                Text("Mark delivered")
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(pickedUp ? "En route to dropoff" : "Head to pickup")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Upgrade to Truck?", isPresented: $showingUpgradeAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Upgrade") {
                    Task {
                        isUpgrading = true
                        upgradeError = await DispatchService.shared.upgradeActiveJobToTruck()
                        isUpgrading = false
                    }
                }
            } message: {
                Text("This adds \(PricingService.Quote.format(truckUpgradeDifferenceCents)) to the fare and tells the customer the item needs a Truck.")
            }
            .alert(
                "Couldn't upgrade",
                isPresented: Binding(get: { upgradeError != nil }, set: { if !$0 { upgradeError = nil } })
            ) {
                Button("OK", role: .cancel) { upgradeError = nil }
            } message: {
                Text(upgradeError ?? "")
            }
        }
    }
}
