//
// SettingsSignInCard.swift
// Tempo
//
// Sign in with Apple from Settings → Account, for a user who finished
// onboarding without a backend session (Debug "Skip Sign In", an expired
// session, or a lost Keychain). Same card as the Dashboard nudge.
//

import SwiftUI

struct SettingsSignInCard: View {
    var body: some View {
        SignInPromptCard()
    }
}
