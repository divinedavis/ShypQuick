import SwiftUI

struct AuthView: View {
    @EnvironmentObject var session: SessionStore
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var role: UserRole = .customer
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 40)

                    Image(systemName: "shippingbox.and.arrow.backward.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)

                    Text("ShypQuick")
                        .font(.largeTitle.bold())
                    Text("On-demand delivery, on your terms.")
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        if isSignUp {
                            TextField("Full name", text: $fullName)
                                .textFieldStyle(.roundedBorder)
                        }
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)

                        if isSignUp {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("I want to sign up as")
                                    .font(.footnote.bold())
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 10) {
                                    roleCard(
                                        choice: .customer,
                                        title: "Customer",
                                        subtitle: "Send packages",
                                        icon: "shippingbox.fill"
                                    )
                                    roleCard(
                                        choice: .driver,
                                        title: "Driver",
                                        subtitle: "Deliver & earn",
                                        icon: "car.fill"
                                    )
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal)

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }

                    Button(action: submit) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text(isSignUp ? "Create account" : "Sign in")
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)

                    Button(isSignUp ? "Have an account? Sign in" : "New here? Create account") {
                        isSignUp.toggle()
                    }
                    .font(.footnote)

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private func roleCard(
        choice: UserRole,
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        let isSelected = role == choice
        Button {
            role = choice
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                if isSignUp {
                    try await session.signUp(
                        email: email,
                        password: password,
                        fullName: fullName,
                        role: role
                    )
                } else {
                    try await session.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
