import Foundation
import Combine
import MapKit

struct AddressSuggestion: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let isRecent: Bool

    var displayLine: String {
        subtitle.isEmpty ? title : "\(title), \(subtitle)"
    }
}

@MainActor
final class AddressSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var suggestions: [AddressSuggestion] = []
    private(set) var isLocked = false

    private let completer = MKLocalSearchCompleter()
    private let recentsKey: String
    private let maxResults = 3

    init(recentsKey: String) {
        self.recentsKey = recentsKey
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Scope suggestions to a ~20km radius around the user's current location (same city).
    func updateRegion(center: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 20_000,
            longitudinalMeters: 20_000
        )
    }

    func updateQuery(_ query: String) {
        if isLocked { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestions = []
            completer.cancel()
            return
        }
        completer.queryFragment = trimmed
    }

    /// Called after the user picks a suggestion — clears the list and blocks
    /// further query updates until `unlock()` is called (when user edits again).
    func lockAfterSelection() {
        isLocked = true
        suggestions = []
        completer.cancel()
    }

    func unlock() {
        isLocked = false
    }

    func saveRecent(_ suggestion: AddressSuggestion) {
        let line = suggestion.displayLine
        UserDefaults.standard.set(line, forKey: recentsKey)
    }

    func resolveCoordinate(for suggestion: AddressSuggestion) async throws -> CLLocationCoordinate2D {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = suggestion.displayLine
        if let region = completer.region as MKCoordinateRegion? {
            request.region = region
        }
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw NSError(domain: "AddressSearch", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "No match for \(suggestion.displayLine)"])
        }
        return item.location.coordinate
    }

    private func recentSuggestionIfAny() -> AddressSuggestion? {
        guard let line = UserDefaults.standard.string(forKey: recentsKey), !line.isEmpty else {
            return nil
        }
        let parts = line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
        let title = String(parts.first ?? "").trimmingCharacters(in: .whitespaces)
        let subtitle = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        return AddressSuggestion(title: title, subtitle: subtitle, isRecent: true)
    }

    // MARK: - MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            if self.isLocked { return }
            var merged: [AddressSuggestion] = []
            if let recent = self.recentSuggestionIfAny() {
                merged.append(recent)
            }
            for result in results {
                if merged.count >= self.maxResults { break }
                let isDuplicate = merged.contains { $0.title == result.title && $0.subtitle == result.subtitle }
                if !isDuplicate {
                    merged.append(AddressSuggestion(
                        title: result.title,
                        subtitle: result.subtitle,
                        isRecent: false
                    ))
                }
            }
            self.suggestions = Array(merged.prefix(self.maxResults))
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = self.recentSuggestionIfAny().map { [$0] } ?? []
        }
    }
}
