import SwiftUI
import PhotosUI

/// Driver onboarding & roster form (checklist sections 1-10). Reached from
/// Profile; editable any time. Document and photo uploads land in the private
/// `driver-documents` bucket; the rest of the form is the `driver_profiles` row.
struct DriverDetailsView: View {
    let profileId: UUID

    @State private var draft: DriverProfile
    @State private var original: DriverProfile
    @State private var taxDraft: DriverTaxInfo
    @State private var taxOriginal: DriverTaxInfo

    @State private var dobDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var dobSet = false

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var didSave = false

    init(profileId: UUID) {
        self.profileId = profileId
        let empty = DriverProfile.empty(id: profileId)
        _draft = State(initialValue: empty)
        _original = State(initialValue: empty)
        let emptyTax = DriverTaxInfo.empty(id: profileId)
        _taxDraft = State(initialValue: emptyTax)
        _taxOriginal = State(initialValue: emptyTax)
    }

    private static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var isDirty: Bool { draft != original || taxDraft != taxOriginal }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                form
            }
        }
        .navigationTitle("Driver Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(!isDirty)
                }
            }
        }
        .task { await load() }
        .onChange(of: dobDate) { _, _ in syncDOB() }
        .onChange(of: dobSet) { _, _ in syncDOB() }
        .alert("Couldn't load your details", isPresented: Binding(
            get: { loadError != nil }, set: { if !$0 { loadError = nil } }
        )) {
            Button("Retry") { Task { await load() } }
            Button("OK", role: .cancel) {}
        } message: { Text(loadError ?? "") }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            statusSection
            basicInfoSection
            vehicleSection
            equipmentSection
            crewSection
            locationSection
            complianceSection
            experienceSection
            specializedSection
            paymentSection
            vehiclePhotosSection
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Image(systemName: draft.isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(draft.isComplete ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.isComplete ? "Roster profile complete" : "Onboarding incomplete")
                        .font(.subheadline.bold())
                    Text(draft.isComplete
                         ? "You're ready to be dispatched."
                         : "Fill in your basic info, vehicle, payment, license & insurance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if didSave {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }
            if let saveError {
                Label(saveError, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // 1. Basic driver information
    private var basicInfoSection: some View {
        Section("Basic Information") {
            Toggle("Date of birth set", isOn: $dobSet)
            if dobSet {
                DatePicker("Date of birth", selection: $dobDate, in: ...Date(), displayedComponents: .date)
            }
            TextField("City", text: optString(\.city))
                .textContentType(.addressCity)
            TextField("State", text: optString(\.state))
                .textContentType(.addressState)
            TextField("ZIP code", text: optString(\.zipCode))
                .textContentType(.postalCode)
                .keyboardType(.numbersAndPunctuation)
        }
    }

    // 2. Vehicle information
    private var vehicleSection: some View {
        Section("Vehicle") {
            Picker("Vehicle type", selection: $draft.vehicleType) {
                Text("Select…").tag(DriverVehicleType?.none)
                ForEach(DriverVehicleType.allCases) { type in
                    Text(type.label).tag(DriverVehicleType?.some(type))
                }
            }
            TextField("Length (ft)", text: optDouble(\.vehicleLengthFt))
                .keyboardType(.decimalPad)
            TextField("Payload capacity (lbs)", text: optInt(\.payloadCapacityLbs))
                .keyboardType(.numberPad)
            Toggle("Lift gate", isOn: $draft.hasLiftGate)
            TextField("Make", text: optString(\.vehicleMake))
            TextField("Model", text: optString(\.vehicleModel))
            TextField("Year", text: optInt(\.vehicleYear))
                .keyboardType(.numberPad)
        }
    }

    // 3. Equipment availability
    private var equipmentSection: some View {
        Section("Equipment") {
            Toggle("Furniture dolly", isOn: $draft.hasFurnitureDolly)
            Toggle("Appliance dolly", isOn: $draft.hasApplianceDolly)
            Toggle("Moving blankets", isOn: $draft.hasMovingBlankets)
            Toggle("Ratchet straps", isOn: $draft.hasRatchetStraps)
            Toggle("Pallet jack", isOn: $draft.hasPalletJack)
            Toggle("Hand truck", isOn: $draft.hasHandTruck)
            Toggle("Ramp", isOn: $draft.hasRamp)
        }
    }

    // 4. Crew information
    private var crewSection: some View {
        Section("Crew") {
            Picker("Crew", selection: $draft.crewType) {
                Text("Select…").tag(CrewType?.none)
                ForEach(CrewType.allCases) { type in
                    Text(type.label).tag(CrewType?.some(type))
                }
            }
            Toggle("Additional helpers available", isOn: $draft.additionalHelpersAvailable)
            Toggle("White glove service", isOn: $draft.whiteGloveCapable)
        }
    }

    // 5. Location & availability
    private var locationSection: some View {
        Section {
            TextField("Primary service area", text: optString(\.primaryServiceArea))
            TextField("Max travel radius (mi)", text: optInt(\.maxTravelRadiusMi))
                .keyboardType(.numberPad)
            TextField("States (comma-separated)", text: operatingStatesText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            Toggle("Weekdays", isOn: $draft.availableWeekdays)
            Toggle("Weekends", isOn: $draft.availableWeekends)
            Toggle("Nights", isOn: $draft.availableNights)
            Toggle("On-demand", isOn: $draft.availableOnDemand)
        } header: {
            Text("Location & Availability")
        } footer: {
            Text("Example states list: NY, NJ, CT")
        }
    }

    // 6. Legal & compliance
    private var complianceSection: some View {
        Section {
            DocumentUploadRow(title: "Driver's license", systemImage: "person.text.rectangle.fill",
                              kind: .driversLicense, driverId: profileId, path: $draft.driversLicensePath)
            DocumentUploadRow(title: "Insurance", systemImage: "checkmark.shield.fill",
                              kind: .insurance, driverId: profileId, path: $draft.insurancePath)
            DocumentUploadRow(title: "Vehicle registration", systemImage: "doc.text.fill",
                              kind: .vehicleRegistration, driverId: profileId, path: $draft.vehicleRegistrationPath)
            TextField("DOT number (optional)", text: optString(\.dotNumber))
                .keyboardType(.numbersAndPunctuation)
            Toggle("I consent to a background check", isOn: $draft.backgroundCheckConsent)
        } header: {
            Text("Legal & Compliance")
        } footer: {
            Text("Documents are stored in a private bucket only you can access.")
        }
    }

    // 7. Delivery experience
    private var experienceSection: some View {
        Section("Delivery Experience") {
            Toggle("Furniture delivery", isOn: $draft.expFurniture)
            Toggle("Appliance delivery", isOn: $draft.expAppliance)
            Toggle("Moving", isOn: $draft.expMoving)
            Toggle("Freight", isOn: $draft.expFreight)
            Toggle("Construction materials", isOn: $draft.expConstructionMaterial)
            TextField("Years of experience", text: optInt(\.yearsExperience))
                .keyboardType(.numberPad)
        }
    }

    // 8. Specialized services
    private var specializedSection: some View {
        Section("Specialized Services") {
            Toggle("Stair deliveries", isOn: $draft.svcStairDeliveries)
            Toggle("Assembly & disassembly", isOn: $draft.svcAssemblyDisassembly)
            Toggle("Appliance hookups", isOn: $draft.svcApplianceHookups)
            Toggle("Heavy item handling", isOn: $draft.svcHeavyItemHandling)
        }
    }

    // 9. Payment information
    private var paymentSection: some View {
        Section {
            Picker("Preferred payment", selection: $draft.preferredPaymentMethod) {
                Text("Select…").tag(DriverPaymentMethod?.none)
                ForEach(DriverPaymentMethod.allCases) { method in
                    Text(method.label).tag(DriverPaymentMethod?.some(method))
                }
            }
            Picker("Tax ID type", selection: $taxDraft.taxIdType) {
                Text("Select…").tag(TaxIdType?.none)
                ForEach(TaxIdType.allCases) { type in
                    Text(type.label).tag(TaxIdType?.some(type))
                }
            }
            SecureField("Tax ID (EIN or SSN)", text: optTaxId())
                .keyboardType(.numbersAndPunctuation)
        } header: {
            Text("Payment & Tax")
        } footer: {
            Text("Your tax ID is stored separately with owner-only access for 1099 processing.")
        }
    }

    // 10. Vehicle photo uploads
    private var vehiclePhotosSection: some View {
        Section("Vehicle Photos") {
            DocumentUploadRow(title: "Front photo", systemImage: "car.fill",
                              kind: .vehiclePhotoFront, driverId: profileId, path: $draft.vehiclePhotoFrontPath)
            DocumentUploadRow(title: "Side photo", systemImage: "car.side.fill",
                              kind: .vehiclePhotoSide, driverId: profileId, path: $draft.vehiclePhotoSidePath)
            DocumentUploadRow(title: "Cargo area photo", systemImage: "shippingbox.fill",
                              kind: .vehiclePhotoCargo, driverId: profileId, path: $draft.vehiclePhotoCargoPath)
        }
    }

    // MARK: - Bindings

    private func optString(_ kp: WritableKeyPath<DriverProfile, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: kp] ?? "" },
            set: { draft[keyPath: kp] = $0.isEmpty ? nil : $0 }
        )
    }

    private func optInt(_ kp: WritableKeyPath<DriverProfile, Int?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: kp].map(String.init) ?? "" },
            set: { draft[keyPath: kp] = Int($0.filter(\.isNumber)) }
        )
    }

    private func optDouble(_ kp: WritableKeyPath<DriverProfile, Double?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: kp].map { String($0) } ?? "" },
            set: { draft[keyPath: kp] = Double($0) }
        )
    }

    private var operatingStatesText: Binding<String> {
        Binding(
            get: { draft.operatingStates.joined(separator: ", ") },
            set: { newValue in
                draft.operatingStates = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func optTaxId() -> Binding<String> {
        Binding(
            get: { taxDraft.taxId ?? "" },
            set: { taxDraft.taxId = $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: - Actions

    private func syncDOB() {
        draft.dateOfBirth = dobSet ? Self.isoDate.string(from: dobDate) : nil
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            if let loaded = try await DriverProfileService.shared.load(driverId: profileId) {
                draft = loaded
                original = loaded
                if let dob = loaded.dateOfBirth, let date = Self.isoDate.date(from: dob) {
                    dobDate = date
                    dobSet = true
                }
            }
            if let tax = try await DriverProfileService.shared.loadTaxInfo(driverId: profileId) {
                taxDraft = tax
                taxOriginal = tax
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        didSave = false
        saveError = nil
        syncDOB()
        do {
            try await DriverProfileService.shared.save(draft)
            original = draft
            if taxDraft != taxOriginal {
                try await DriverProfileService.shared.saveTaxInfo(taxDraft)
                taxOriginal = taxDraft
            }
            didSave = true
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Document upload row

/// A tappable row that picks an image, uploads it to the private bucket, and
/// writes the resulting object path back into the bound roster field.
private struct DocumentUploadRow: View {
    let title: String
    let systemImage: String
    let kind: DriverDocumentKind
    let driverId: UUID
    @Binding var path: String?

    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var failed = false

    var body: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
                Spacer()
                trailingIcon
            }
        }
        .disabled(isUploading)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    @ViewBuilder
    private var trailingIcon: some View {
        if isUploading {
            ProgressView()
        } else if failed {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        } else if path != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "arrow.up.circle").foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if isUploading { return "Uploading…" }
        if failed { return "Upload failed — tap to retry" }
        return path != nil ? "Uploaded" : "Tap to upload a photo"
    }

    private var statusColor: Color {
        if failed { return .red }
        return path != nil ? .green : .secondary
    }

    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        failed = false
        defer { isUploading = false }
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data),
                let jpeg = image.jpegData(compressionQuality: 0.7)
            else {
                failed = true
                return
            }
            path = try await DriverProfileService.shared.uploadDocument(
                jpeg, kind: kind, driverId: driverId
            )
        } catch {
            print("DocumentUploadRow upload error:", error)
            failed = true
        }
    }
}
