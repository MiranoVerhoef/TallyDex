@preconcurrency import Network
import Darwin
import Foundation
import Observation
import UIKit

struct LocalHTTPRequest: Equatable, Sendable {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    var cookies: [String: String] {
        guard let value = headers["cookie"] else { return [:] }
        return value.split(separator: ";").reduce(into: [:]) { result, item in
            let parts = item.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { return }
            result[parts[0]] = parts[1]
        }
    }

    var formValues: [String: String] {
        guard let text = String(data: body, encoding: .utf8) else { return [:] }
        return Self.decodeQuery(text)
    }

    static func parse(_ data: Data) -> LocalHTTPRequest? {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<boundary.lowerBound], encoding: .utf8)
        else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count == 3 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }

        let target = requestParts[1]
        let components = URLComponents(string: "http://tallydex.local\(target)")
        let query = (components?.queryItems ?? []).reduce(into: [:]) {
            $0[$1.name] = $1.value ?? ""
        }
        let bodyStart = boundary.upperBound
        return LocalHTTPRequest(
            method: requestParts[0].uppercased(),
            path: components?.percentEncodedPath.removingPercentEncoding ?? "/",
            query: query,
            headers: headers,
            body: Data(data[bodyStart...])
        )
    }

    static func expectedByteCount(in data: Data) -> Int? {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<boundary.lowerBound], encoding: .utf8)
        else { return nil }
        let contentLength = headerText.components(separatedBy: "\r\n").dropFirst()
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") }
            ?? 0
        return boundary.upperBound + contentLength
    }

    private static func decodeQuery(_ value: String) -> [String: String] {
        value.split(separator: "&").reduce(into: [:]) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = parts.first else { return }
            let decodedKey = key.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? key
            let rawValue = parts.count > 1 ? parts[1] : ""
            let decodedValue = rawValue.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawValue
            result[decodedKey] = decodedValue
        }
    }
}

struct LocalHTTPResponse: Sendable {
    let statusCode: Int
    let reason: String
    let headers: [String: String]
    let body: Data

    static func html(_ html: String, statusCode: Int = 200, headers: [String: String] = [:]) -> Self {
        LocalHTTPResponse(
            statusCode: statusCode,
            reason: reason(for: statusCode),
            headers: headers.merging(["Content-Type": "text/html; charset=utf-8"]) { current, _ in current },
            body: Data(html.utf8)
        )
    }

    static func json<T: Encodable>(_ value: T, statusCode: Int = 200) -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let body = (try? encoder.encode(value)) ?? Data("{\"error\":\"Encoding failed\"}".utf8)
        return LocalHTTPResponse(
            statusCode: statusCode,
            reason: reason(for: statusCode),
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body
        )
    }

    static func redirect(to location: String, cookie: String? = nil) -> Self {
        var headers = ["Location": location]
        if let cookie { headers["Set-Cookie"] = cookie }
        return LocalHTTPResponse(statusCode: 303, reason: "See Other", headers: headers, body: Data())
    }

    static func error(_ message: String, statusCode: Int) -> Self {
        json(["error": message], statusCode: statusCode)
    }

    var encoded: Data {
        var resolvedHeaders = headers
        resolvedHeaders["Content-Length"] = String(body.count)
        resolvedHeaders["Connection"] = "close"
        resolvedHeaders["Cache-Control"] = "no-store"
        resolvedHeaders["X-Content-Type-Options"] = "nosniff"
        resolvedHeaders["X-Frame-Options"] = "DENY"
        resolvedHeaders["Referrer-Policy"] = "no-referrer"
        let header = (["HTTP/1.1 \(statusCode) \(reason)"]
            + resolvedHeaders.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" })
            .joined(separator: "\r\n") + "\r\n\r\n"
        return Data(header.utf8) + body
    }

    private static func reason(for statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 413: "Payload Too Large"
        case 429: "Too Many Requests"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        default: "Response"
        }
    }
}

final class LocalHTTPServer: @unchecked Sendable {
    enum Event: Sendable {
        case ready(port: UInt16)
        case failed(String)
        case stopped
    }

    private let queue = DispatchQueue(label: "com.miranoverhoef.TallyDex.local-http")
    private var listener: NWListener?
    private var handler: (@Sendable (LocalHTTPRequest) async -> LocalHTTPResponse)?
    private let maximumRequestBytes = 1_048_576

    func start(
        handler: @escaping @Sendable (LocalHTTPRequest) async -> LocalHTTPResponse,
        eventHandler: @escaping @Sendable (Event) -> Void
    ) throws {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        self.handler = handler

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let port = listener.port?.rawValue { eventHandler(.ready(port: port)) }
            case .failed(let error):
                eventHandler(.failed(error.localizedDescription))
            case .cancelled:
                eventHandler(.stopped)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.receive(on: connection, accumulated: Data())
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            self?.handler = nil
        }
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.start(queue: queue)
        receiveNext(on: connection, accumulated: accumulated)
    }

    private func receiveNext(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var requestData = accumulated
            if let data { requestData.append(data) }

            if requestData.count > maximumRequestBytes {
                send(.error("Request is too large.", statusCode: 413), on: connection)
                return
            }
            if let expected = LocalHTTPRequest.expectedByteCount(in: requestData), requestData.count >= expected {
                guard let request = LocalHTTPRequest.parse(Data(requestData.prefix(expected))) else {
                    send(.error("Malformed request.", statusCode: 400), on: connection)
                    return
                }
                guard let handler else {
                    send(.error("Sharing has stopped.", statusCode: 503), on: connection)
                    return
                }
                Task {
                    let response = await handler(request)
                    self.send(response, on: connection)
                }
                return
            }
            if isComplete || error != nil {
                send(.error("Incomplete request.", statusCode: 400), on: connection)
                return
            }
            receiveNext(on: connection, accumulated: requestData)
        }
    }

    private func send(_ response: LocalHTTPResponse, on connection: NWConnection) {
        connection.send(content: response.encoded, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

struct LocalSharingSetDTO: Encodable, Sendable {
    let id: String
    let name: String
    let seriesName: String
    let releaseDate: String?
}

struct LocalSharingVariantDTO: Encodable, Sendable {
    let id: String
    let name: String
    let quantity: Int
}

struct LocalSharingCardDTO: Encodable, Sendable {
    let id: String
    let name: String
    let number: String
    let setName: String
    let imageURL: String?
    let variants: [LocalSharingVariantDTO]
    let wishlisted: Bool
    let notes: String
    let owned: Bool
}

struct LocalSharingBootstrapDTO: Encodable, Sendable {
    let sets: [LocalSharingSetDTO]
    let allowsMultipleCopies: Bool
}

struct LocalSharingCardsDTO: Encodable, Sendable {
    let cards: [LocalSharingCardDTO]
    let resultCount: Int
    let mayBeTruncated: Bool
}

private struct LocalSharingQuantityUpdate: Decodable {
    let variant: String
    let quantity: Int
}

private struct LocalSharingMetadataUpdate: Decodable {
    let wishlisted: Bool
    let notes: String
}

@MainActor
@Observable
final class LocalCollectionSharingController {
    private(set) var isRunning = false
    private(set) var isStarting = false
    private(set) var accessURL: URL?
    private(set) var pairingCode = ""
    private(set) var editCount = 0
    private(set) var statusMessage: String?

    @ObservationIgnored private var server: LocalHTTPServer?
    @ObservationIgnored private var sessionToken = ""
    @ObservationIgnored private var csrfToken = ""
    @ObservationIgnored private var failedPairAttempts = 0

    func start(catalogStore: CatalogStore, collectionStore: CollectionStore) async {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        statusMessage = nil
        editCount = 0
        pairingCode = String(format: "%06d", Int.random(in: 0...999_999))
        sessionToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        csrfToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        failedPairAttempts = 0

        do {
            _ = try await collectionStore.createBackup(reason: "Before browser editing")
            let server = LocalHTTPServer()
            self.server = server
            try server.start(
                handler: { [weak self, catalogStore, collectionStore] request in
                    guard let self else {
                        return .error("Sharing has stopped.", statusCode: 503)
                    }
                    return await self.route(
                        request,
                        catalogStore: catalogStore,
                        collectionStore: collectionStore
                    )
                },
                eventHandler: { [weak self] event in
                    Task { @MainActor in self?.handle(event) }
                }
            )
        } catch {
            server?.stop()
            server = nil
            isStarting = false
            statusMessage = "TallyDex couldn’t start browser editing: \(error.localizedDescription)"
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
        isStarting = false
        accessURL = nil
        pairingCode = ""
        sessionToken = ""
        csrfToken = ""
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func handle(_ event: LocalHTTPServer.Event) {
        switch event {
        case .ready(let port):
            isStarting = false
            isRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            if let address = Self.localIPv4Address() {
                accessURL = URL(string: "http://\(address):\(port)")
                statusMessage = nil
            } else {
                accessURL = URL(string: "http://127.0.0.1:\(port)")
                statusMessage = "No Wi-Fi address was found. Connect this iPhone and computer to the same network, then restart sharing."
            }
        case .failed(let message):
            stop()
            statusMessage = "Browser editing stopped: \(message)"
        case .stopped:
            if isRunning { stop() }
        }
    }

    private func route(
        _ request: LocalHTTPRequest,
        catalogStore: CatalogStore,
        collectionStore: CollectionStore
    ) async -> LocalHTTPResponse {
        if request.method == "GET", request.path == "/" {
            return isAuthorized(request)
                ? .html(Self.editorHTML(csrfToken: csrfToken))
                : .html(Self.pairingHTML(showError: request.query["error"] == "1"))
        }
        if request.method == "POST", request.path == "/pair" {
            guard request.formValues["code"] == pairingCode else {
                failedPairAttempts += 1
                if failedPairAttempts >= 5 {
                    pairingCode = String(format: "%06d", Int.random(in: 0...999_999))
                    failedPairAttempts = 0
                    return .html(Self.tooManyAttemptsHTML, statusCode: 429)
                }
                return .redirect(to: "/?error=1")
            }
            failedPairAttempts = 0
            return .redirect(
                to: "/",
                cookie: "tallydex_session=\(sessionToken); Path=/; HttpOnly; SameSite=Strict"
            )
        }

        guard request.path.hasPrefix("/api/") else {
            return .error("Not found.", statusCode: 404)
        }
        guard isAuthorized(request) else {
            return .error("Pair with TallyDex first.", statusCode: 401)
        }

        if request.method == "GET", request.path == "/api/bootstrap" {
            let sets = catalogStore.groups.flatMap { group in
                group.sets.map {
                    LocalSharingSetDTO(
                        id: $0.id,
                        name: $0.name,
                        seriesName: group.series.name,
                        releaseDate: $0.releaseDate
                    )
                }
            }
            return .json(LocalSharingBootstrapDTO(
                sets: sets,
                allowsMultipleCopies: UserDefaults.standard.bool(
                    forKey: CollectionSettings.allowsMultipleCopiesKey
                )
            ))
        }

        if request.method == "GET", request.path == "/api/cards" {
            do {
                let results: [CatalogCardSearchResult]
                let mayBeTruncated: Bool
                if let setID = request.query["setID"],
                   let set = catalogStore.groups.flatMap(\.sets).first(where: { $0.id == setID }) {
                    let cards = try await catalogStore.cards(for: set)
                    results = cards.map { CatalogCardSearchResult(card: $0, setName: set.name) }
                    mayBeTruncated = false
                } else if let query = request.query["q"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                          query.count >= 2 {
                    results = try await catalogStore.searchCards(query: query)
                    mayBeTruncated = results.count == 100
                } else {
                    return .error("Choose a set or enter at least two search characters.", statusCode: 400)
                }
                let isSetRequest = request.query["setID"] != nil
                let cards = isSetRequest ? results : Array(results.prefix(250))
                let variants = await catalogStore.prepareVariants(
                    for: cards.map(\.card),
                    refreshCachedDetails: false
                )
                let document = try await collectionStore.exportDocument()
                return .json(Self.cardsDTO(
                    results: cards,
                    variantsByCardID: variants,
                    document: document,
                    mayBeTruncated: mayBeTruncated || (!isSetRequest && results.count > 250)
                ))
            } catch {
                return .error("Cards couldn’t be loaded. Try again.", statusCode: 500)
            }
        }

        guard request.headers["x-tallydex-csrf"] == csrfToken else {
            return .error("The editing session is no longer valid. Reload the page.", statusCode: 403)
        }
        let quantityPrefix = "/api/cards/"
        if request.method == "POST", request.path.hasPrefix(quantityPrefix), request.path.hasSuffix("/quantity") {
            let cardID = String(request.path.dropFirst(quantityPrefix.count).dropLast("/quantity".count))
            guard let update = try? JSONDecoder().decode(LocalSharingQuantityUpdate.self, from: request.body),
                  let variant = CatalogVariantKind(rawValue: update.variant),
                  update.quantity >= 0,
                  update.quantity <= 999
            else { return .error("Invalid quantity update.", statusCode: 400) }
            do {
                try await collectionStore.setQuantity(update.quantity, cardID: cardID, variant: variant)
                editCount += 1
                return .json(["saved": true])
            } catch {
                return .error("The quantity couldn’t be saved.", statusCode: 500)
            }
        }
        if request.method == "POST", request.path.hasPrefix(quantityPrefix), request.path.hasSuffix("/metadata") {
            let cardID = String(request.path.dropFirst(quantityPrefix.count).dropLast("/metadata".count))
            guard let update = try? JSONDecoder().decode(LocalSharingMetadataUpdate.self, from: request.body),
                  update.notes.count <= 10_000
            else { return .error("Invalid wishlist or notes update.", statusCode: 400) }
            do {
                try await collectionStore.saveCardMetadata(
                    cardID: cardID,
                    isWishlisted: update.wishlisted,
                    notes: update.notes
                )
                editCount += 1
                return .json(["saved": true])
            } catch {
                return .error("The wishlist or notes couldn’t be saved.", statusCode: 500)
            }
        }
        return .error("Not found.", statusCode: 404)
    }

    private func isAuthorized(_ request: LocalHTTPRequest) -> Bool {
        request.cookies["tallydex_session"] == sessionToken && !sessionToken.isEmpty
    }

    private static func cardsDTO(
        results: [CatalogCardSearchResult],
        variantsByCardID: [String: Set<CatalogVariantKind>],
        document: PortableCollectionDocument,
        mayBeTruncated: Bool
    ) -> LocalSharingCardsDTO {
        let ownership = Dictionary(grouping: document.ownership, by: \.cardID)
        let metadata = Dictionary(uniqueKeysWithValues: document.cardMetadata.map { ($0.cardID, $0) })
        let cards = results.map { result in
            let owned = ownership[result.card.id] ?? []
            let quantities = Dictionary(uniqueKeysWithValues: owned.map { ($0.variant, $0.quantity) })
            var knownVariants = variantsByCardID[result.card.id] ?? []
            knownVariants.formUnion(quantities.keys)
            if knownVariants.isEmpty { knownVariants = [.normal] }
            let cardMetadata = metadata[result.card.id]
            return LocalSharingCardDTO(
                id: result.card.id,
                name: result.card.name,
                number: result.card.localID,
                setName: result.setName,
                imageURL: result.card.imageURL.map {
                    CatalogArtworkCache.resolvedAssetURL($0, category: .cardThumbnails).absoluteString
                },
                variants: CatalogVariantKind.allCases.filter(knownVariants.contains).map {
                    LocalSharingVariantDTO(
                        id: $0.rawValue,
                        name: $0.displayName,
                        quantity: quantities[$0, default: 0]
                    )
                },
                wishlisted: cardMetadata?.isWishlisted ?? false,
                notes: cardMetadata?.notes ?? "",
                owned: quantities.values.contains { $0 > 0 }
            )
        }
        return LocalSharingCardsDTO(
            cards: cards,
            resultCount: cards.count,
            mayBeTruncated: mayBeTruncated
        )
    }

    nonisolated private static func localIPv4Address() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        var candidates: [(name: String, address: String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                candidates.append((
                    String(cString: interface.pointee.ifa_name),
                    host.withUnsafeBufferPointer {
                        String(decoding: $0.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
                    }
                ))
            }
        }
        return candidates.first(where: { $0.name == "en0" })?.address ?? candidates.first?.address
    }

    private static func pairingHTML(showError: Bool) -> String {
        let message = showError ? "<p class=\"error\">That code didn’t match. Check the iPhone and try again.</p>" : ""
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Pair with TallyDex</title><style>\(sharedCSS)</style></head><body><main class="pairing">
        <div class="brand">TallyDex</div><h1>Pair with your iPhone</h1>
        <p>Enter the six-digit code shown in TallyDex. Collection data stays between this browser and your iPhone.</p>\(message)
        <form method="post" action="/pair"><label for="code">Pairing code</label><input id="code" name="code" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" autocomplete="one-time-code" autofocus required><button>Connect</button></form>
        </main></body></html>
        """
    }

    private static let tooManyAttemptsHTML = """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>New code required</title><style>\(sharedCSS)</style></head>
    <body><main class="pairing"><div class="brand">TallyDex</div><h1>New code created</h1><p>For security, TallyDex replaced the pairing code after five incorrect attempts. Use the new code shown on your iPhone.</p><a class="button" href="/">Try again</a></main></body></html>
    """

    private static func editorHTML(csrfToken: String) -> String {
        let csrfJSON = String(data: try! JSONEncoder().encode(csrfToken), encoding: .utf8)!
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>TallyDex Browser Editor</title><style>\(sharedCSS)\(editorCSS)</style></head><body>
        <header><div><div class="brand">TallyDex</div><small>Browser collection editor</small></div><div class="secure">Connected locally</div></header>
        <main class="editor"><section class="toolbar"><div class="field grow"><label for="search">Search cards</label><input id="search" type="search" placeholder="Lucario, SM95, Chaos Rising…"></div>
        <div class="field grow"><label for="set">Or choose a set</label><select id="set"><option value="">Choose a set</option></select></div><button id="load">Load cards</button></section>
        <section class="statusbar"><div id="status">Choose a set or search for cards.</div><div class="filters"><button data-filter="all" class="active">All</button><button data-filter="owned">Owned</button><button data-filter="missing">Missing</button></div></section>
        <div id="cards" class="cards"></div></main><div id="toast" role="status"></div>
        <script>
        const csrf=\(csrfJSON);const state={cards:[],filter:'all',multiple:false};
        const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
        async function api(path,options={}){const headers={'Accept':'application/json',...(options.body?{'Content-Type':'application/json','X-TallyDex-CSRF':csrf}:{}),...(options.headers||{})};const response=await fetch(path,{...options,headers});if(response.status===401){location.reload();throw new Error('Session ended');}const data=await response.json();if(!response.ok)throw new Error(data.error||'Request failed');return data;}
        function toast(message,bad=false){const el=document.querySelector('#toast');el.textContent=message;el.className=bad?'show bad':'show';setTimeout(()=>el.className='',2200);}
        async function start(){try{const data=await api('/api/bootstrap');state.multiple=data.allowsMultipleCopies;const select=document.querySelector('#set');let series='';data.sets.forEach(set=>{if(set.seriesName!==series){series=set.seriesName;const group=document.createElement('optgroup');group.label=series;select.append(group);}const option=document.createElement('option');option.value=set.id;option.textContent=set.name+(set.releaseDate?' · '+set.releaseDate:'');select.lastElementChild.append(option);});}catch(e){document.querySelector('#status').textContent=e.message;}}
        async function load(){const q=document.querySelector('#search').value.trim(),setID=document.querySelector('#set').value;if(!q&&!setID){toast('Choose a set or enter a search.',true);return;}const params=q?'q='+encodeURIComponent(q):'setID='+encodeURIComponent(setID);document.querySelector('#status').textContent='Loading cards and printing variants from your iPhone…';document.querySelector('#cards').innerHTML='<div class="loader"></div>';try{const data=await api('/api/cards?'+params);state.cards=data.cards;render();document.querySelector('#status').textContent=data.resultCount+' cards'+(data.mayBeTruncated?' · narrow your search to see every match':'');}catch(e){document.querySelector('#cards').innerHTML='';document.querySelector('#status').textContent=e.message;}}
        function visible(){return state.cards.filter(card=>state.filter==='all'||(state.filter==='owned'&&card.owned)||(state.filter==='missing'&&!card.owned));}
        function render(){const root=document.querySelector('#cards');root.innerHTML=visible().map(card=>`<article class="card" data-id="${esc(card.id)}"><div class="cardtop">${card.imageURL?`<img loading="lazy" src="${esc(card.imageURL)}" alt="">`:'<div class="placeholder">TD</div>'}<div><h2>${esc(card.name)}</h2><p>${esc(card.setName)} · #${esc(card.number)}</p></div></div><div class="variants">${card.variants.map(v=>variantHTML(card,v)).join('')}</div><details><summary>Wishlist & notes</summary><label class="wish"><input type="checkbox" data-wishlist ${card.wishlisted?'checked':''}> Wishlist</label><label>Personal notes<textarea data-notes maxlength="10000">${esc(card.notes)}</textarea></label><button data-save-meta>Save wishlist & notes</button></details></article>`).join('')||'<div class="empty">No cards match this filter.</div>';}
        function variantHTML(card,v){if(state.multiple)return `<div class="variant"><span>${esc(v.name)}</span><div class="stepper"><button data-step="-1" data-variant="${esc(v.id)}" aria-label="Remove one">−</button><strong data-quantity="${esc(v.id)}">${v.quantity}</strong><button data-step="1" data-variant="${esc(v.id)}" aria-label="Add one">+</button></div></div>`;return `<label class="variant check"><span>${esc(v.name)}</span><input type="checkbox" data-check data-variant="${esc(v.id)}" ${v.quantity>0?'checked':''}></label>`;}
        async function setQuantity(card,variant,quantity){quantity=Math.max(0,Math.min(999,quantity));await api('/api/cards/'+encodeURIComponent(card.id)+'/quantity',{method:'POST',body:JSON.stringify({variant,quantity})});const item=card.variants.find(v=>v.id===variant);item.quantity=quantity;card.owned=card.variants.some(v=>v.quantity>0);toast('Saved '+card.name);if(state.filter!=='all')render();}
        document.querySelector('#load').onclick=load;document.querySelector('#search').addEventListener('keydown',e=>{if(e.key==='Enter')load();});document.querySelector('#set').onchange=()=>{document.querySelector('#search').value='';load();};
        document.querySelector('.filters').onclick=e=>{const button=e.target.closest('[data-filter]');if(!button)return;state.filter=button.dataset.filter;document.querySelectorAll('[data-filter]').forEach(b=>b.classList.toggle('active',b===button));render();};
        document.querySelector('#cards').addEventListener('click',async e=>{const article=e.target.closest('.card');if(!article)return;const card=state.cards.find(c=>c.id===article.dataset.id);try{const step=e.target.closest('[data-step]');if(step){const item=card.variants.find(v=>v.id===step.dataset.variant);await setQuantity(card,item.id,item.quantity+Number(step.dataset.step));article.querySelector(`[data-quantity="${CSS.escape(item.id)}"]`).textContent=item.quantity;return;}if(e.target.closest('[data-save-meta]')){const wishlisted=article.querySelector('[data-wishlist]').checked,notes=article.querySelector('[data-notes]').value;await api('/api/cards/'+encodeURIComponent(card.id)+'/metadata',{method:'POST',body:JSON.stringify({wishlisted,notes})});card.wishlisted=wishlisted;card.notes=notes;toast('Wishlist and notes saved');}}catch(err){toast(err.message,true);render();}});
        document.querySelector('#cards').addEventListener('change',async e=>{if(!e.target.matches('[data-check]'))return;const article=e.target.closest('.card'),card=state.cards.find(c=>c.id===article.dataset.id);try{await setQuantity(card,e.target.dataset.variant,e.target.checked?1:0);}catch(err){toast(err.message,true);render();}});
        start();
        </script></body></html>
        """
    }

    private static let sharedCSS = """
    :root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#14213d;background:#f3f5f9;color-scheme:light}*{box-sizing:border-box}body{margin:0}.brand{font-weight:900;font-size:2rem;color:#ffcb05;-webkit-text-stroke:1px #086bd8;text-shadow:2px 2px #086bd8}.pairing{width:min(92%,460px);margin:10vh auto;background:white;padding:2rem;border-radius:28px;box-shadow:0 18px 70px #0b2d5b25}.pairing h1{margin-bottom:.5rem}.pairing p{color:#59677c;line-height:1.5}.pairing label,.field label,details label{display:block;font-weight:700;margin:.8rem 0 .35rem}.pairing input,input,select,textarea{width:100%;font:inherit;border:1px solid #cad2df;border-radius:12px;padding:.8rem;background:white}.pairing input{font-size:2rem;letter-spacing:.35em;text-align:center}.pairing button,.button,button{border:0;border-radius:12px;background:#087fe8;color:white;font:inherit;font-weight:700;padding:.85rem 1.1rem;cursor:pointer;text-decoration:none;display:inline-block}.pairing button{width:100%;margin-top:1rem}.error{color:#b42318!important;background:#fee4e2;padding:.7rem;border-radius:10px}
    """

    private static let editorCSS = """
    header{display:flex;justify-content:space-between;align-items:center;padding:1rem 4vw;background:white;position:sticky;top:0;z-index:5;box-shadow:0 2px 20px #102a4320}header small{color:#66758a}.secure{font-weight:700;color:#18794e;background:#def7e7;padding:.55rem .8rem;border-radius:999px}.editor{width:min(94%,1400px);margin:1.5rem auto}.toolbar{display:flex;gap:1rem;align-items:end;background:white;padding:1rem;border-radius:18px}.grow{flex:1}.field label{margin-top:0}.statusbar{display:flex;justify-content:space-between;align-items:center;gap:1rem;padding:1rem 0;color:#536277}.filters{display:flex;background:#e2e7ef;border-radius:12px;padding:3px}.filters button{background:transparent;color:#344054;padding:.55rem .9rem}.filters button.active{background:white;color:#087fe8;box-shadow:0 2px 7px #1112}.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(310px,1fr));gap:1rem}.card{background:white;border-radius:20px;padding:1rem;box-shadow:0 7px 26px #102a4312}.cardtop{display:flex;gap:1rem;align-items:center}.cardtop img,.placeholder{width:74px;height:103px;object-fit:contain;border-radius:8px;background:#edf1f7}.placeholder{display:grid;place-items:center;font-weight:900;color:#087fe8}.card h2{font-size:1.1rem;margin:0 0 .35rem}.card p{margin:0;color:#6b778c}.variants{margin-top:1rem;border-top:1px solid #e8ebf0}.variant{min-height:48px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #e8ebf0}.check input{width:24px;height:24px}.stepper{display:flex;align-items:center;gap:.6rem}.stepper button{width:36px;height:36px;padding:0;font-size:1.3rem}.stepper strong{min-width:2ch;text-align:center}details{margin-top:1rem}summary{font-weight:700;cursor:pointer}.wish{display:flex;align-items:center;gap:.5rem}.wish input{width:22px;height:22px}textarea{min-height:90px;resize:vertical}details button{margin-top:.7rem}#toast{position:fixed;right:1rem;bottom:1rem;background:#14213d;color:white;padding:.8rem 1rem;border-radius:12px;opacity:0;transform:translateY(20px);transition:.2s;pointer-events:none}#toast.show{opacity:1;transform:none}#toast.bad{background:#b42318}.loader{width:42px;height:42px;border:5px solid #d8e9fb;border-top-color:#087fe8;border-radius:50%;animation:spin .8s linear infinite;margin:4rem auto}.empty{text-align:center;color:#66758a;padding:4rem}@keyframes spin{to{transform:rotate(360deg)}}@media(max-width:700px){.toolbar{flex-direction:column;align-items:stretch}.statusbar{align-items:flex-start;flex-direction:column}.cards{grid-template-columns:1fr}.secure{font-size:.8rem}}
    """
}
