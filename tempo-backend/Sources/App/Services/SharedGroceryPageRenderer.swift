import Foundation

// MARK: - SharedGroceryPageRenderer

//
// Builds the self-contained HTML page a shopper sees at GET /g/:token. No
// external assets (no CDN scripts/fonts/images, no analytics) — everything
// inline, so it loads instantly and works behind restrictive network
// policies. The page never receives the item list inline; it fetches
// /g/:token/state on load and polls it every 5s (see `js(token:)` below),
// so item text is inserted client-side via `textContent` (the `esc` helper),
// never `innerHTML` with raw text — defense in depth alongside the
// server-side `.htmlEscaped` used for the title/store embedded directly here.

enum SharedGroceryPageRenderer {
    /// 16 random bytes, base64 — a fresh one per response. The page's inline
    /// <style>/<script> only run because they carry it (SecurityHeadersMiddleware
    /// otherwise sends `default-src 'none'`, which blocks all inline code).
    static func makeNonce() -> String {
        var rng = SystemRandomNumberGenerator()
        let bytes = (0 ..< 16).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        return Data(bytes).base64EncodedString()
    }

    /// CSP for the live list page: inline style/script by nonce only, same-origin
    /// fetches (`/g/:token/state`, `/g/:token/items/:id`), nothing else.
    static func contentSecurityPolicy(nonce: String) -> String {
        "default-src 'none'; style-src 'nonce-\(nonce)'; script-src 'nonce-\(nonce)'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    }

    /// CSP for the static "expired" page: inline style only, no script.
    static func goneContentSecurityPolicy(nonce: String) -> String {
        "default-src 'none'; style-src 'nonce-\(nonce)'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    }

    static func render(title: String, store: String?, token: String, nonce: String) -> String {
        let safeTitle = title.htmlEscaped
        let subtitle = store.map { "<p class=\"store\">\($0.htmlEscaped)</p>" } ?? ""
        let safeToken = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <title>\(safeTitle) — Tempo</title>
        <style nonce="\(nonce)">\(css)</style>
        </head>
        <body>
          <main>
            <header>
              <h1>\(safeTitle)</h1>
              \(subtitle)
              <div class="progress"><div class="bar" id="bar"></div></div>
              <p class="count" id="count">Loading…</p>
            </header>
            <ul id="list"></ul>
            <p class="footer">Shared from Tempo. Ticks sync automatically — no app or account needed.</p>
          </main>
          <script nonce="\(nonce)">\(js(token: safeToken))</script>
        </body>
        </html>
        """
    }

    static func renderGone(nonce: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Link expired — Tempo</title>
        <style nonce="\(nonce)">\(css)</style>
        </head>
        <body>
          <main class="gone">
            <h1>This list is no longer available</h1>
            <p>The link expired or was turned off by whoever shared it.</p>
          </main>
        </body>
        </html>
        """
    }

    private static let css = """
    :root{color-scheme:light dark;--bg:#fff;--fg:#111;--muted:#666;--line:#e5e5e5;--accent:#16a34a;--card:#f7f7f8;}
    @media (prefers-color-scheme:dark){:root{--bg:#0b0b0c;--fg:#f2f2f2;--muted:#9a9a9a;--line:#232326;--card:#17171a;}}
    *{box-sizing:border-box;-webkit-tap-highlight-color:transparent;}
    body{margin:0;background:var(--bg);color:var(--fg);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;}
    main{max-width:560px;margin:0 auto;padding:24px 16px 64px;}
    main.gone{text-align:center;padding-top:80px;}
    h1{font-size:22px;margin:0 0 4px;}
    h2{font-size:13px;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);margin:24px 0 8px;}
    .store{color:var(--muted);margin:0 0 16px;font-size:15px;}
    .progress{height:8px;border-radius:99px;background:var(--line);overflow:hidden;margin-top:12px;}
    .bar{height:100%;width:0%;background:var(--accent);transition:width .3s ease;}
    .count{color:var(--muted);font-size:13px;margin:8px 0 0;}
    ul{list-style:none;margin:0;padding:0;}
    li.item{display:flex;align-items:center;gap:14px;padding:14px 12px;background:var(--card);border-radius:12px;margin-bottom:8px;cursor:pointer;user-select:none;}
    li.item .box{width:26px;height:26px;flex:0 0 26px;border-radius:8px;border:2px solid var(--line);display:flex;align-items:center;justify-content:center;font-size:16px;color:#fff;}
    li.item.checked .box{background:var(--accent);border-color:var(--accent);}
    li.item.checked .name{text-decoration:line-through;color:var(--muted);}
    .name{flex:1;font-size:16px;}
    .qty{color:var(--muted);font-size:14px;}
    .footer{text-align:center;color:var(--muted);font-size:12px;margin-top:32px;}
    """

    private static func js(token: String) -> String {
        """
        const TOKEN = "\(token)";
        const listEl = document.getElementById('list');
        const barEl = document.getElementById('bar');
        const countEl = document.getElementById('count');
        let polling = false;

        function esc(s){ const d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML; }
        function fmtQty(n){ return (n && n > 0) ? (Number.isInteger(n) ? n : n.toFixed(1)) : ''; }

        function render(items){
          const order = ["produce","meat","seafood","protein","dairy","frozen","grains","oils","pantry"];
          const byCat = {};
          items.forEach(function(it){ (byCat[it.category] = byCat[it.category] || []).push(it); });
          const cats = Object.keys(byCat).sort(function(a, b){
            const ia = order.indexOf(a), ib = order.indexOf(b);
            return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib);
          });
          let html = '';
          cats.forEach(function(cat){
            html += '<h2>' + esc(cat) + '</h2>';
            byCat[cat].forEach(function(it){
              const qty = fmtQty(it.quantity);
              html += '<li class="item' + (it.checked ? ' checked' : '') + '" data-id="' + esc(it.id) + '">' +
                '<div class="box">' + (it.checked ? '\\u2713' : '') + '</div>' +
                '<div class="name">' + esc(it.name) + '</div>' +
                '<div class="qty">' + (qty ? (esc(qty) + ' ' + esc(it.unit)) : '') + '</div>' +
                '</li>';
            });
          });
          listEl.innerHTML = html;
          const total = items.length;
          const checked = items.filter(function(i){ return i.checked; }).length;
          barEl.style.width = (total ? Math.round(checked / total * 100) : 0) + '%';
          countEl.textContent = checked + ' of ' + total + ' checked';

          Array.prototype.forEach.call(listEl.querySelectorAll('li.item'), function(li){
            li.addEventListener('click', function(){ toggle(li); });
          });
        }

        function toggle(li){
          const id = li.getAttribute('data-id');
          const nowChecked = !li.classList.contains('checked');
          li.classList.toggle('checked', nowChecked);
          li.querySelector('.box').textContent = nowChecked ? '\\u2713' : '';
          fetch('/g/' + TOKEN + '/items/' + encodeURIComponent(id), {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({checked: nowChecked})
          }).catch(function(){});
        }

        function showGone(){
          document.body.innerHTML = '<main class="gone"><h1>This list is no longer available</h1><p>The link expired or was turned off.</p></main>';
        }

        function poll(){
          if (polling) return;
          polling = true;
          fetch('/g/' + TOKEN + '/state', {cache: 'no-store'})
            .then(function(res){
              if (res.status === 410 || res.status === 404) { showGone(); return null; }
              return res.json();
            })
            .then(function(json){ if (json) render(json.data.items); })
            .catch(function(){})
            .finally(function(){ polling = false; });
        }

        poll();
        setInterval(poll, 5000);
        """
    }
}
