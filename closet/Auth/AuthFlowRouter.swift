//
//  AuthFlowRouter.swift
//  closet
//
//  Coordinates Sign In ↔ Register navigation on AuthView's NavigationStack path.
//

import SwiftUI

enum AuthRoute: Hashable {
    case signIn
    case register
}

struct AuthFlowRouter {
    @Binding var path: [AuthRoute]

    func showSignIn() {
        path = [.signIn]
    }

    /// Sign In → Register; system back from Register returns to Sign In.
    func showRegisterFromSignIn() {
        path = [.signIn, .register]
    }
}

private struct AuthFlowRouterKey: EnvironmentKey {
    static let defaultValue: AuthFlowRouter? = nil
}

extension EnvironmentValues {
    var authFlowRouter: AuthFlowRouter? {
        get { self[AuthFlowRouterKey.self] }
        set { self[AuthFlowRouterKey.self] = newValue }
    }
}

extension View {
    func authFlowRouter(_ router: AuthFlowRouter) -> some View {
        environment(\.authFlowRouter, router)
    }
}
