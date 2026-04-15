import SwiftUI
import MapKit
import CoreLocation

struct CustomerHomeView: View {
    @StateObject private var location = LocationService.shared
    @StateObject private var pickupSearch = AddressSearchService(recentsKey: "recent_pickup_address")
    @StateObject private var dropoffSearch = AddressSearchService(recentsKey: "recent_dropoff_address")

    @State private var pickupAddress = ""
    @State private var dropoffAddress = ""
    @State private var pickupCoord: CLLocationCoordinate2D?
    @State private var dropoffCoord: CLLocationCoordinate2D?
    @State private var itemSize: ItemSize = .small
    @State private var showingRequest = false
    @State private var activeField: Field?

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    enum Field: Hashable { case pickup, dropoff }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                }
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 12) {
                    formCard

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
                    .disabled(pickupCoord == nil || dropoffCoord == nil)
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
            .task {
                location.requestPermission()
                location.startUpdating()
            }
            .onChange(of: location.currentLocation) { _, loc in
                guard let coord = loc?.coordinate else { return }
                pickupSearch.updateRegion(center: coord)
                dropoffSearch.updateRegion(center: coord)
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                    )
                )
            }
        }
    }

    private var formCard: some View {
        VStack(spacing: 0) {
            addressRow(
                icon: "circle.fill",
                iconColor: .green,
                placeholder: "Pickup address",
                text: $pickupAddress,
                field: .pickup,
                search: pickupSearch,
                selected: { s in
                    pickupAddress = s.displayLine
                    activeField = nil
                    pickupSearch.saveRecent(s)
                    Task {
                        pickupCoord = try? await pickupSearch.resolveCoordinate(for: s)
                    }
                }
            )

            Divider().padding(.leading, 32)

            addressRow(
                icon: "mappin.circle.fill",
                iconColor: .red,
                placeholder: "Dropoff address",
                text: $dropoffAddress,
                field: .dropoff,
                search: dropoffSearch,
                selected: { s in
                    dropoffAddress = s.displayLine
                    activeField = nil
                    dropoffSearch.saveRecent(s)
                    Task {
                        dropoffCoord = try? await dropoffSearch.resolveCoordinate(for: s)
                    }
                }
            )
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func addressRow(
        icon: String,
        iconColor: Color,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        search: AddressSearchService,
        selected: @escaping (AddressSuggestion) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: icon).foregroundStyle(iconColor)
                TextField(placeholder, text: text)
                    .onTapGesture { activeField = field }
                    .onChange(of: text.wrappedValue) { _, newValue in
                        activeField = field
                        search.updateQuery(newValue)
                    }
            }
            .padding()

            if activeField == field && !search.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(search.suggestions) { suggestion in
                        Button {
                            text.wrappedValue = suggestion.displayLine
                            selected(suggestion)
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: suggestion.isRecent ? "clock.arrow.circlepath" : "mappin")
                                    .foregroundStyle(suggestion.isRecent ? .blue : .secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title).font(.subheadline).foregroundStyle(.primary)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if suggestion.id != search.suggestions.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(.bottom, 8)
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
