import SwiftUI
import MapKit

struct CustomerHomeView: View {
    @State private var pickupAddress = ""
    @State private var dropoffAddress = ""
    @State private var itemDescription = ""
    @State private var itemSize: ItemSize = .small
    @State private var showingRequest = false
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442), // Brooklyn
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                }
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "circle.fill").foregroundStyle(.green).font(.caption)
                            TextField("Pickup address", text: $pickupAddress)
                        }
                        Divider()
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                            TextField("Dropoff address", text: $dropoffAddress)
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                    Picker("Size", selection: $itemSize) {
                        ForEach(ItemSize.allCases, id: \.self) { size in
                            Text(size.rawValue.capitalized).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        showingRequest = true
                    } label: {
                        Text("Request ShypQuick")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pickupAddress.isEmpty || dropoffAddress.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Send a package")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingRequest) {
                DeliveryConfirmationView(
                    pickup: pickupAddress,
                    dropoff: dropoffAddress,
                    size: itemSize
                )
            }
        }
    }
}

struct DeliveryConfirmationView: View {
    let pickup: String
    let dropoff: String
    let size: ItemSize

    var body: some View {
        VStack(spacing: 16) {
            Text("Confirm delivery").font(.title2.bold())
            Text("From: \(pickup)").font(.subheadline)
            Text("To: \(dropoff)").font(.subheadline)
            Text("Size: \(size.rawValue.capitalized)").font(.subheadline)
            Text("Estimated: $12.50").font(.title3.bold())
            Button("Confirm & find driver") { }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationDetents([.medium])
    }
}
