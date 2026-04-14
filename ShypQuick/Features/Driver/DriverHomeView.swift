import SwiftUI
import MapKit

struct DriverHomeView: View {
    @State private var isOnline = false
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition)
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
        }
    }
}
