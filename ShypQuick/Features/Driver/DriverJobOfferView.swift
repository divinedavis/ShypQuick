import SwiftUI
import Combine
import CoreLocation

struct DriverJobOfferView: View {
    let offer: JobOffer
    let driverLocation: CLLocation?
    let onAccept: () -> Void
    let onDecline: () -> Void

    @State private var secondsRemaining: Int = 15
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var driverEarningsCents: Int {
        Int(Double(offer.totalCents) * 0.70)
    }

    private var distanceToPickupMiles: Double? {
        guard let driverLocation else { return nil }
        let pickup = CLLocation(latitude: offer.pickupLat, longitude: offer.pickupLng)
        return driverLocation.distance(from: pickup) / 1609.344
    }

    var body: some View {
        ZStack {
            Color.green.ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 40)
                    Spacer()
                    Text("\(secondsRemaining)s")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.2), in: Capsule())
                }

                itemCard

                addressBlock

                earningsCard

                Spacer()

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        onDecline()
                    } label: {
                        Text("Decline")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.2))
                    .foregroundStyle(.white)

                    Button {
                        onAccept()
                    } label: {
                        Text("Accept")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.green)
                }
            }
            .padding()
        }
        .onReceive(timer) { _ in
            if secondsRemaining > 0 {
                secondsRemaining -= 1
            } else {
                onDecline()
            }
        }
    }

    private var itemCard: some View {
        VStack(spacing: 12) {
            if let data = offer.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Image(systemName: offer.categoryIcon)
                    .font(.system(size: 70))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
            }
            Text(offer.categoryTitle)
                .font(.title2.bold())
                .foregroundStyle(.white)
        }
    }

    private var addressBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            addressRow(icon: "circle.fill", label: "Pickup", text: offer.pickupAddress)
            addressRow(icon: "mappin.circle.fill", label: "Dropoff", text: offer.dropoffAddress)
            if let miles = distanceToPickupMiles {
                Label(String(format: "%.1f mi to pickup", miles), systemImage: "location.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
    }

    private func addressRow(icon: String, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.75))
                Text(text)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
        }
    }

    private var earningsCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("YOU EARN")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.75))
                Text(PricingService.Quote.format(driverEarningsCents))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("TOTAL")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.75))
                Text(PricingService.Quote.format(offer.totalCents))
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding()
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
    }
}
