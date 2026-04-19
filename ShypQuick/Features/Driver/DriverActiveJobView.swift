import SwiftUI
import MapKit

struct DriverActiveJobView: View {
    let job: JobOffer
    let onComplete: () -> Void

    @State private var cameraPosition: MapCameraPosition
    @State private var pickedUp = false

    init(job: JobOffer, onComplete: @escaping () -> Void) {
        self.job = job
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

    private var driverEarningsCents: Int {
        Int(Double(job.totalCents) * 0.70)
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
        }
    }
}
