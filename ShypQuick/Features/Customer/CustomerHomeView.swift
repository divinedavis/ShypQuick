import SwiftUI
import MapKit
import CoreLocation

struct CustomerHomeView: View {
    let profile: Profile

    @StateObject private var location = LocationService.shared
    @StateObject private var pickupSearch = AddressSearchService(recentsKey: "recent_pickup_address")
    @StateObject private var dropoffSearch = AddressSearchService(recentsKey: "recent_dropoff_address")

    @State private var pickupAddress = ""
    @State private var dropoffAddress = ""
    @State private var pickupCoord: CLLocationCoordinate2D?
    @State private var dropoffCoord: CLLocationCoordinate2D?
    @State private var didPrefillHome = false
    @State private var itemSize: ItemSize = .small
    @State private var selectedCategory: ItemCategory?
    @State private var attachedPhotoData: Data?
    @State private var sameHour = false
    @State private var routeRequest: RouteRequest?
    @State private var showingCategorySheet = false
    @State private var showingScheduleSheet = false
    @State private var showingSchedulePicker = false
    @State private var activeField: Field?

    struct RouteRequest: Hashable {
        let pickupAddress: String
        let dropoffAddress: String
        let pickupLat: Double
        let pickupLng: Double
        let dropoffLat: Double
        let dropoffLng: Double
        let size: ItemSize
        let sameHour: Bool
    }

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    enum Field: Hashable { case pickup, dropoff }

    private var currentQuote: PricingService.Quote? {
        guard let pickup = pickupCoord, let dropoff = dropoffCoord else { return nil }
        return PricingService.quote(size: itemSize, pickup: pickup, dropoff: dropoff, sameHour: sameHour)
    }

    private func resetForm() {
        pickupAddress = ""
        dropoffAddress = ""
        pickupCoord = nil
        dropoffCoord = nil
        selectedCategory = nil
        itemSize = .small
        sameHour = false
        activeField = nil
        pickupSearch.unlock()
        dropoffSearch.unlock()
        pickupSearch.updateQuery("")
        dropoffSearch.updateQuery("")
        didPrefillHome = false
        prefillHomeAddressIfNeeded()
    }

    private func prefillHomeAddressIfNeeded() {
        guard !didPrefillHome,
              pickupAddress.isEmpty,
              let home = profile.homeAddress,
              let lat = profile.homeLat,
              let lng = profile.homeLng else { return }
        didPrefillHome = true
        pickupAddress = home
        pickupCoord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        pickupSearch.lockAfterSelection()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                }
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 12) {
                    formCard

                    if let category = selectedCategory {
                        HStack {
                            Image(systemName: category.icon).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(category.title).font(.subheadline.bold())
                                Text(category.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Change") { showingCategorySheet = true }
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    Toggle(isOn: $sameHour) {
                        Label("Need it within the hour (+$30)", systemImage: "bolt.fill")
                            .font(.subheadline)
                    }
                    .tint(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                    if let quote = currentQuote {
                        HStack {
                            Text("Estimate").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Text(quote.dollars).font(.title3.bold())
                        }
                        .padding(.horizontal, 12)
                    }

                    HStack(spacing: 12) {
                        Button {
                            showingCategorySheet = true
                        } label: {
                            Text("Request now")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pickupCoord == nil || dropoffCoord == nil)

                        Button {
                            showingScheduleSheet = true
                        } label: {
                            Label("Schedule", systemImage: "calendar")
                                .bold()
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(pickupCoord == nil || dropoffCoord == nil)
                    }
                }
                .padding()
            }
            .navigationTitle("Send a package")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingCategorySheet) {
                ItemCategorySheet { category, photoData in
                    selectedCategory = category
                    itemSize = category.size
                    attachedPhotoData = photoData
                    guard let p = pickupCoord, let d = dropoffCoord else { return }
                    let quote = PricingService.quote(size: category.size, pickup: p, dropoff: d, sameHour: sameHour)
                    DispatchService.shared.postOffer(
                        pickupAddress: pickupAddress,
                        dropoffAddress: dropoffAddress,
                        pickup: p,
                        dropoff: d,
                        size: category.size,
                        sameHour: sameHour,
                        totalCents: quote.totalCents,
                        photoData: photoData,
                        categoryTitle: category.title,
                        categoryIcon: category.icon
                    )
                    routeRequest = RouteRequest(
                        pickupAddress: pickupAddress,
                        dropoffAddress: dropoffAddress,
                        pickupLat: p.latitude, pickupLng: p.longitude,
                        dropoffLat: d.latitude, dropoffLng: d.longitude,
                        size: category.size, sameHour: sameHour
                    )
                }
            }
            .sheet(isPresented: $showingScheduleSheet) {
                ItemCategorySheet { category, photoData in
                    selectedCategory = category
                    itemSize = category.size
                    attachedPhotoData = photoData
                    showingScheduleSheet = false
                    showingSchedulePicker = true
                }
            }
            .sheet(isPresented: $showingSchedulePicker) {
                SchedulePickerSheet { date in
                    guard let p = pickupCoord, let d = dropoffCoord,
                          let cat = selectedCategory else { return }
                    let quote = PricingService.quote(size: cat.size, pickup: p, dropoff: d, sameHour: false)
                    ScheduleService.shared.schedule(
                        pickupAddress: pickupAddress,
                        dropoffAddress: dropoffAddress,
                        pickup: p,
                        dropoff: d,
                        size: cat.size,
                        totalCents: quote.totalCents,
                        photoData: attachedPhotoData,
                        categoryTitle: cat.title,
                        categoryIcon: cat.icon,
                        scheduledAt: date
                    )
                    resetForm()
                }
            }
            .navigationDestination(item: $routeRequest) { req in
                let pickup = CLLocationCoordinate2D(latitude: req.pickupLat, longitude: req.pickupLng)
                let dropoff = CLLocationCoordinate2D(latitude: req.dropoffLat, longitude: req.dropoffLng)
                let quote = PricingService.quote(size: req.size, pickup: pickup, dropoff: dropoff, sameHour: req.sameHour)
                DeliveryRouteView(
                    pickupAddress: req.pickupAddress,
                    dropoffAddress: req.dropoffAddress,
                    pickup: pickup,
                    dropoff: dropoff,
                    quote: quote
                )
            }
            .task {
                location.requestPermission()
                location.startUpdating()
                prefillHomeAddressIfNeeded()
            }
            .onChange(of: routeRequest) { oldValue, newValue in
                // When the user returns from the route view (newValue == nil),
                // reset the form so they start a fresh delivery.
                if oldValue != nil && newValue == nil {
                    resetForm()
                }
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
                    pickupSearch.lockAfterSelection()
                    pickupAddress = s.displayLine
                    activeField = nil
                    pickupSearch.saveRecent(s)
                    dismissKeyboard()
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
                    dropoffSearch.lockAfterSelection()
                    dropoffAddress = s.displayLine
                    activeField = nil
                    dropoffSearch.saveRecent(s)
                    dismissKeyboard()
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
                    .onTapGesture {
                        activeField = field
                        search.unlock()
                    }
                    .onChange(of: text.wrappedValue) { _, newValue in
                        if search.isLocked { return }
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

