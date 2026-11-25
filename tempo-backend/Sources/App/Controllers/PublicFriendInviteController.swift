import Fluent
import Vapor

// MARK: - PublicFriendInviteController

//
// Public, UNAUTHENTICATED page behind a friend invite link, mounted at the app
// root (`/i/<token>`, not under /v1) so the link is short enough to text. The
// person who opens it may not have Tempo yet, so this is a plain page with one
// button that opens the app (`tempo://invite/<token>`, a scheme the app already
// registers). IP rate-limited like the grocery pages.
//
// What it reveals: the inviter's display name and nothing else. Unknown and
// revoked links get the same generic page, so tokens can't be probed.

struct PublicFriendInviteController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get(":token", use: page)
    }

    @Sendable
    func page(_ req: Request) async throws -> Response {
        let nonce = FriendInvitePageRenderer.makeNonce()
        var name: String?
        var token = ""
        if let candidate = req.parameters.get("token"), candidate.count <= 64,
           let invite = try await FriendInvite.query(on: req.db).filter(\.$token == candidate).first(),
           invite.isLive,
           let owner = try await User.find(invite.userID, on: req.db), owner.deletedAt == nil
        {
            name = ArenaService.publicName(owner)
            token = candidate
        }
        let html = name.map { FriendInvitePageRenderer.render(inviter: $0, token: token, nonce: nonce) }
            ?? FriendInvitePageRenderer.renderGone(nonce: nonce)
        let response = Response(status: name == nil ? .gone : .ok, body: .init(string: html))
        response.headers.contentType = .html
        response.headers.replaceOrAdd(name: "Content-Security-Policy", value: FriendInvitePageRenderer.contentSecurityPolicy(nonce: nonce))
        return response
    }
}

// MARK: - FriendInvitePageRenderer

enum FriendInvitePageRenderer {
    static func makeNonce() -> String {
        var rng = SystemRandomNumberGenerator()
        let bytes = (0 ..< 16).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        return Data(bytes).base64EncodedString()
    }

    /// Inline style by nonce only; no script, no fetches, no forms.
    static func contentSecurityPolicy(nonce: String) -> String {
        "default-src 'none'; style-src 'nonce-\(nonce)'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    }

    static func render(inviter: String, token: String, nonce: String) -> String {
        let safeName = inviter.htmlEscaped
        // Tokens are lowercase letters and digits; encode anyway.
        let safeToken = token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return page(
            title: "\(safeName) invited you to Tempo",
            body: """
            <h1>\(safeName) invited you to Tempo</h1>
            <p>Join them on the weekly leaderboard and take on challenges together.</p>
            <a class="button" href="tempo://invite/\(safeToken)">Open in Tempo</a>
            <p class="hint">If the button does nothing, you need the Tempo app on this phone first.</p>
            """,
            nonce: nonce
        )
    }

    static func renderGone(nonce: String) -> String {
        page(
            title: "Invite link expired",
            body: """
            <h1>This invite link is no longer active</h1>
            <p>Ask your friend to send a new one from Tempo.</p>
            """,
            nonce: nonce
        )
    }

    private static func page(title: String, body: String, nonce: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <title>\(title) — Tempo</title>
        <style nonce="\(nonce)">\(css)</style>
        </head>
        <body>
          <main>
            \(body)
          </main>
        </body>
        </html>
        """
    }

    private static let css = """
    :root{color-scheme:light dark;--bg:#fff;--fg:#111;--muted:#666;--accent:#16a34a;}
    @media (prefers-color-scheme:dark){:root{--bg:#0b0b0c;--fg:#f2f2f2;--muted:#9a9a9a;}}
    *{box-sizing:border-box;}
    body{margin:0;background:var(--bg);color:var(--fg);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;}
    main{max-width:480px;margin:0 auto;padding:96px 24px;text-align:center;}
    h1{font-size:26px;line-height:1.2;margin:0 0 12px;}
    p{color:var(--muted);font-size:16px;line-height:1.4;margin:0 0 28px;}
    .button{display:block;background:var(--accent);color:#fff;text-decoration:none;font-weight:600;font-size:17px;padding:16px 24px;border-radius:14px;}
    .hint{font-size:13px;margin:20px 0 0;}
    """
}
