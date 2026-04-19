import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var session: SessionStore
    @State private var showEmailAuth = false
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            gradient

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Send")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("SHYPQuick")
                        .font(.system(size: 42, weight: .bold))
                    Text("Deliver")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.4))
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "shippingbox.and.arrow.backward.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                    Text("Big items.\nFast delivery.")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("On-demand delivery for furniture, appliances, and everything in between.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 12) {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .cornerRadius(25)

                    Button {
                        showEmailAuth = true
                    } label: {
                        HStack {
                            Image(systemName: "envelope.fill")
                            Text("Continue with email")
                        }
                        .bold()
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 25))
                        .foregroundStyle(.white)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthSheet()
                .environmentObject(session)
        }
    }

    private var gradient: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.systemBackground),
                Color.blue.opacity(0.3),
                Color.blue.opacity(0.7),
                Color.blue
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Could not read Apple credential."
                return
            }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            Task {
                isLoading = true
                defer { isLoading = false }
                do {
                    try await session.signInWithApple(idToken: idToken, fullName: name.isEmpty ? nil : name)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Email Auth Sheet

struct EmailAuthSheet: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var fullName = ""
    @State private var role: UserRole = .customer
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isSignUp ? "Let's get started." : "Welcome back.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(isSignUp ? "Create your\nShypQuick account." : "Sign in to\nShypQuick.")
                            .font(.largeTitle.bold())
                    }
                    .padding(.top, 8)

                    Text(isSignUp
                         ? "Send big items or deliver and earn — your choice."
                         : "On-demand delivery for furniture, appliances, and more.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Fields
                    VStack(spacing: 20) {
                        if isSignUp {
                            UnderlineField(placeholder: "Full name", text: $fullName)
                        }
                        UnderlineField(placeholder: "Email", text: $email, keyboardType: .emailAddress)
                        UnderlineField(placeholder: "Password", text: $password, isSecure: true)
                        if isSignUp {
                            UnderlineField(placeholder: "Confirm password", text: $confirmPassword, isSecure: true)
                        }
                    }

                    // Role selector (sign up only)
                    if isSignUp {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("I want to")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                roleCard(
                                    choice: .customer,
                                    title: "Send",
                                    subtitle: "Ship packages",
                                    icon: "shippingbox.fill",
                                    color: .blue
                                )
                                roleCard(
                                    choice: .driver,
                                    title: "Deliver",
                                    subtitle: "Earn money",
                                    icon: "car.fill",
                                    color: .green
                                )
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }

                    // Action button
                    Button(action: submit) {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                                    .bold()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(.label), in: RoundedRectangle(cornerRadius: 26))
                        .foregroundStyle(Color(.systemBackground))
                    }
                    .buttonStyle(.plain)

                    // Toggle
                    Button(isSignUp ? "Already have an account? Sign in" : "Don't have an account? Sign up") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSignUp.toggle()
                            errorMessage = nil
                        }
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func roleCard(choice: UserRole, title: String, subtitle: String, icon: String, color: Color) -> some View {
        let isSelected = role == choice
        Button { withAnimation(.easeInOut(duration: 0.2)) { role = choice } } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .frame(width: 56, height: 56)
                    .background(isSelected ? color : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(isSelected ? .white : color)
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? color.opacity(0.08) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isSelected ? color : Color.clear, lineWidth: 2)
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
                    guard password == confirmPassword else {
                        errorMessage = "Passwords don't match."
                        return
                    }
                    try await session.signUp(email: email, password: password, fullName: fullName, role: role)
                } else {
                    try await session.signIn(email: email, password: password)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Underline text field

struct UnderlineField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(.body)
            } else {
                TextField(placeholder, text: $text)
                    .font(.body)
                    .keyboardType(keyboardType)
                    .autocapitalization(.none)
            }
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
        }
    }
}
