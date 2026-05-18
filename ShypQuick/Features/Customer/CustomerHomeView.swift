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
    @State private var itemSize: ItemSize = .small
    @State private var selectedCategory: ItemCategory?
    @State private var attachedPhotoData: Data?
    @State private var sameHour = false
    @State private var stairsFloors = 0
    @State private var twoManCrew = false
    @State private var showingAddOns = false
    @State private var routeRequest: RouteRequest?
    @State private var showingCategorySheet = false
    @State private var showingScheduleSheet = false
    @State private var showingSchedulePicker = false
    @State private var activeField: Field?
    @FocusState private var focusedField: Field?
    /// Set synchronously inside the suggestion-tap handler so the
    /// text-onChange that fires immediately after can recognize the
    /// programmatic write and skip re-querying. @FocusState is not
    /// reliable for this — its writes are committed asynchronously
    /// by UIKit, so `focusedField` may still report the old field
    /// when the onChange runs.
    @State private var suppressNextEdit: Field?

    struct RouteRequest: Hashable {
        let pickupAddress: String
        let dropoffAddress: String
        let pickupLat: Double
        let pickupLng: Double
        let dropoffLat: Double
        let dropoffLng: Double
        let size: ItemSize
        let sameHour: Bool
        let stairsFloors: Int
        let twoManCrew: Bool
        /// Real job_offers row id, so DeliveryRouteView can track it live.
        /// nil when the post failed.
        let offerId: UUID?
    }

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )
    @State private var paymentError: String?
    @State private var isProcessingPayment = false
    /// Captured at the moment the customer picks a category. The payment +
    /// dispatch flow reads this from the sheet's `onDismiss` (i.e. AFTER the
    /// SwiftUI sheet is fully gone) so Stripe PaymentSheet can present
    /// cleanly without racing the dismissal animation.
    @State private var pendingRequest: PendingRequest?

    struct PendingRequest {
        let category: ItemCategory
        let photoData: Data?
        let pickup: CLLocationCoordinate2D
        let dropoff: CLLocationCoordinate2D
        let pickupAddress: String
        let dropoffAddress: String
        let quote: PricingService.Quote
        let sameHour: Bool
        let stairsFloors: Int
        let twoManCrew: Bool
    }

    enum Field: Hashable { case pickup, dropoff }

    private var currentSurcharges: PricingService.Surcharges {
        PricingService.Surcharges(
            sameHour: sameHour,
            stairsFloors: stairsFloors,
            twoManCrew: twoManCrew
        )
    }

    private var currentQuote: PricingService.Quote? {
        guard let pickup = pickupCoord, let dropoff = dropoffCoord else { return nil }
        return PricingService.quote(
            size: itemSize,
            pickup: pickup,
            dropoff: dropoff,
            surcharges: currentSurcharges
        )
    }

    private var canSubmit: Bool {
        guard let p = pickupCoord, let d = dropoffCoord else { return false }
        let pickupOk = !pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && CLLocationCoordinate2DIsValid(p)
            && !(p.latitude == 0 && p.longitude == 0)
        let dropoffOk = !dropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && CLLocationCoordinate2DIsValid(d)
            && !(d.latitude == 0 && d.longitude == 0)
        // Also block self-delivery (same pickup and dropoff).
        let distinct = p.latitude != d.latitude || p.longitude != d.longitude
        return pickupOk && dropoffOk && distinct
    }

    private func resetForm() {
        pickupAddress = ""
        dropoffAddress = ""
        pickupCoord = nil
        dropoffCoord = nil
        selectedCategory = nil
        itemSize = .small
        sameHour = false
        stairsFloors = 0
        twoManCrew = false
        showingAddOns = false
        activeField = nil
        pickupSearch.unlock()
        dropoffSearch.unlock()
        pickupSearch.updateQuery("")
        dropoffSearch.updateQuery("")
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    private func rootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return nil }
        let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }

    /// Authorize the customer's card via Apple Pay (when configured), then
    /// post the job offer with the resulting payment_intent_id. If Stripe
    /// isn't configured, falls back to posting the offer with no hold so
    /// the legacy free flow keeps working.
    ///
    /// Called from the category sheet's `onDismiss` — by that point the
    /// SwiftUI sheet is fully gone, so Stripe PaymentSheet has a clean
    /// presenter (the root view controller of the key window).
    private func processRequest(_ req: PendingRequest) async {
        isProcessingPayment = true
        defer { isProcessingPayment = false }

        let result: PaymentService.AuthorizeResult
        if let presenter = rootViewController() {
            result = await PaymentService.shared.authorize(
                amountCents: req.quote.totalCents,
                presenter: presenter
            )
        } else {
            // No window we can present from — fall through to legacy free
            // flow rather than dropping the request silently.
            result = .notConfigured
        }

        let intentId: String?
        switch result {
        case .authorized(let id):
            intentId = id
        case .notConfigured:
            intentId = nil
        case .cancelled:
            return
        case .failed(let msg):
            paymentError = msg
            return
        }

        let posted = await DispatchService.shared.postOffer(
            pickupAddress: req.pickupAddress,
            dropoffAddress: req.dropoffAddress,
            pickup: req.pickup,
            dropoff: req.dropoff,
            size: req.category.size,
            vehicleType: req.category.vehicleType,
            sameHour: req.sameHour,
            totalCents: req.quote.totalCents,
            photoData: req.photoData,
            categoryTitle: req.category.title,
            categoryIcon: req.category.icon,
            paymentIntentId: intentId
        )
        routeRequest = RouteRequest(
            pickupAddress: req.pickupAddress,
            dropoffAddress: req.dropoffAddress,
            pickupLat: req.pickup.latitude, pickupLng: req.pickup.longitude,
            dropoffLat: req.dropoff.latitude, dropoffLng: req.dropoff.longitude,
            size: req.category.size,
            sameHour: req.sameHour,
            stairsFloors: req.stairsFloors,
            twoManCrew: req.twoManCrew,
            offerId: posted?.id
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
                        Label(
                            "Need it within the hour (+\(PricingService.Quote.format(PricingService.sameHourSurchargeCents)))",
                            systemImage: "bolt.fill"
                        )
                        .font(.subheadline)
                    }
                    .tint(.orange)
                    .accessibilityIdentifier("rushToggle")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                    addOnsCard

                    if let quote = currentQuote {
                        quoteBreakdown(quote)
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
                        .disabled(!canSubmit)

                        Button {
                            showingScheduleSheet = true
                        } label: {
                            Label("Schedule", systemImage: "calendar")
                                .bold()
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(!canSubmit)
                    }
                }
                .padding()
            }
            .navigationTitle("Send a package")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(
                isPresented: $showingCategorySheet,
                onDismiss: {
                    // Run AFTER the sheet animation completes so the
                    // Stripe PaymentSheet has a clean presenter. Without
                    // this, presenting UIKit-style from inside the SwiftUI
                    // sheet's onSelect closure raced the dismissal and
                    // silently hung the flow (no payment sheet, no route).
                    guard let req = pendingRequest else { return }
                    pendingRequest = nil
                    Task { @MainActor in
                        await processRequest(req)
                    }
                }
            ) {
                ItemCategorySheet { category, photoData in
                    selectedCategory = category
                    itemSize = category.size
                    attachedPhotoData = photoData
                    guard let p = pickupCoord, let d = dropoffCoord else { return }
                    let quote = PricingService.quote(
                        size: category.size,
                        pickup: p, dropoff: d,
                        surcharges: currentSurcharges
                    )
                    pendingRequest = PendingRequest(
                        category: category,
                        photoData: photoData,
                        pickup: p,
                        dropoff: d,
                        pickupAddress: pickupAddress,
                        dropoffAddress: dropoffAddress,
                        quote: quote,
                        sameHour: sameHour,
                        stairsFloors: stairsFloors,
                        twoManCrew: twoManCrew
                    )
                }
            }
            .alert(
                "Payment failed",
                isPresented: Binding(
                    get: { paymentError != nil },
                    set: { if !$0 { paymentError = nil } }
                ),
                presenting: paymentError
            ) { _ in
                Button("OK", role: .cancel) { paymentError = nil }
            } message: { msg in
                Text(msg)
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
                    let quote = PricingService.quote(
                        size: cat.size,
                        pickup: p, dropoff: d,
                        surcharges: PricingService.Surcharges(
                            sameHour: false,
                            stairsFloors: stairsFloors,
                            twoManCrew: twoManCrew
                        )
                    )
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
                let quote = PricingService.quote(
                    size: req.size,
                    pickup: pickup, dropoff: dropoff,
                    surcharges: PricingService.Surcharges(
                        sameHour: req.sameHour,
                        stairsFloors: req.stairsFloors,
                        twoManCrew: req.twoManCrew
                    )
                )
                DeliveryRouteView(
                    pickupAddress: req.pickupAddress,
                    dropoffAddress: req.dropoffAddress,
                    pickup: pickup,
                    dropoff: dropoff,
                    quote: quote,
                    offerId: req.offerId
                )
            }
            .task {
                location.requestPermission()
                location.startUpdating()
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

    @ViewBuilder
    private var addOnsCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showingAddOns.toggle() }
            } label: {
                HStack {
                    Label("Add-ons", systemImage: "plus.circle.fill")
                        .font(.subheadline.bold())
                    if currentSurcharges.hasAny {
                        Text("\(addOnsCount) selected")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                    }
                    Spacer()
                    Image(systemName: showingAddOns ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addOnsToggle")

            if showingAddOns {
                VStack(spacing: 10) {
                    HStack {
                        Label("Stairs", systemImage: "stairs")
                            .font(.subheadline)
                        Spacer()
                        Stepper(
                            "\(stairsFloors) floor\(stairsFloors == 1 ? "" : "s")",
                            value: $stairsFloors, in: 0...20
                        )
                        .labelsHidden()
                        Text("\(stairsFloors) fl")
                            .font(.caption.monospacedDigit())
                            .frame(width: 40, alignment: .trailing)
                        Text("+\(PricingService.Quote.format(PricingService.stairsPerFloorCents))/fl")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Toggle(isOn: $twoManCrew) {
                        Label(
                            "Two-man crew (+\(PricingService.Quote.format(PricingService.twoManCrewCents)))",
                            systemImage: "person.2.fill"
                        )
                        .font(.subheadline)
                    }
                    .accessibilityIdentifier("twoManCrewToggle")
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var addOnsCount: Int {
        var count = 0
        if stairsFloors > 0 { count += 1 }
        if twoManCrew { count += 1 }
        return count
    }

    @ViewBuilder
    private func quoteBreakdown(_ quote: PricingService.Quote) -> some View {
        VStack(spacing: 4) {
            breakdownRow("Base", PricingService.Quote.format(quote.baseCents))
            if quote.mileageSurchargeCents > 0 {
                breakdownRow(
                    String(format: "Mileage (%.1f mi)", max(0, quote.distanceMiles - PricingService.freeMilesRadius)),
                    "+\(PricingService.Quote.format(quote.mileageSurchargeCents))"
                )
            }
            if quote.sameHourSurchargeCents > 0 {
                breakdownRow("Rush (within hour)", "+\(PricingService.Quote.format(quote.sameHourSurchargeCents))")
            }
            if quote.stairsCents > 0 {
                breakdownRow("Stairs (\(stairsFloors) fl)", "+\(PricingService.Quote.format(quote.stairsCents))")
            }
            if quote.twoManCrewCents > 0 {
                breakdownRow("Two-man crew", "+\(PricingService.Quote.format(quote.twoManCrewCents))")
            }
            Divider().padding(.vertical, 2)
            HStack {
                Text("Estimate").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(quote.dollars).font(.title3.bold())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func breakdownRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
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
                invalidateCoord: { pickupCoord = nil },
                selected: { s in
                    pickupSearch.lockAfterSelection()
                    pickupAddress = s.displayLine
                    activeField = nil
                    focusedField = nil
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
                invalidateCoord: { dropoffCoord = nil },
                selected: { s in
                    dropoffSearch.lockAfterSelection()
                    dropoffAddress = s.displayLine
                    activeField = nil
                    focusedField = nil
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
        invalidateCoord: @escaping () -> Void,
        selected: @escaping (AddressSuggestion) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: icon).foregroundStyle(iconColor)
                TextField(placeholder, text: text)
                    .focused($focusedField, equals: field)
                    .onChange(of: focusedField) { _, newValue in
                        // Focus is the canonical signal that the user wants
                        // to edit this field — `onTapGesture` on TextField
                        // is unreliable on iOS 17+. Reactivate suggestions
                        // for whichever field has focus so typing populates
                        // the dropdown.
                        if newValue == field {
                            search.unlock()
                            activeField = field
                            search.updateQuery(text.wrappedValue)
                        }
                    }
                    .onChange(of: text.wrappedValue) { _, newValue in
                        // Programmatic writes (prefill, suggestion tap) flag
                        // themselves before mutating the text so we can skip
                        // the re-query path here and leave the dropdown closed.
                        if suppressNextEdit == field {
                            suppressNextEdit = nil
                            return
                        }
                        // Otherwise this is a user edit; trust focus only as
                        // a secondary check — the @FocusState write from a
                        // programmatic dismiss may not have landed yet.
                        guard focusedField == field else { return }
                        search.unlock()
                        activeField = field
                        search.updateQuery(newValue)
                        // The coord saved alongside the previous selection
                        // is stale the moment the user edits the text.
                        invalidateCoord()
                    }
            }
            .padding()

            if activeField == field && !search.isLocked && !search.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(search.suggestions) { suggestion in
                        Button {
                            // Lock first (clears suggestions + sets isLocked).
                            search.lockAfterSelection()
                            activeField = nil
                            // Synchronous suppress flag: the upcoming
                            // text-onChange will see this and bail.
                            suppressNextEdit = field
                            text.wrappedValue = suggestion.displayLine
                            focusedField = nil
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

