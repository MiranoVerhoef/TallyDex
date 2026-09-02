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
        queue.sync {
            listener?.cancel()
            listener = nil
            handler = nil
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
    let category: String
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
    let browserGridColumns: String
    let browserGridSpacing: String
}

struct LocalSharingCardsDTO: Encodable, Sendable {
    let cards: [LocalSharingCardDTO]
    let resultCount: Int
    let mayBeTruncated: Bool
}

struct LocalSharingMarketQuoteDTO: Encodable, Sendable {
    let variant: String
    let variantName: String
    let currencyCode: String
    let amount: Double
    let updatedAt: String
    let average1Day: Double?
    let average7Days: Double?
    let average30Days: Double?
    let marketplaceURL: String?
}

struct LocalSharingMarketHistoryPointDTO: Encodable, Sendable {
    let variant: String
    let variantName: String
    let day: String
    let currencyCode: String
    let amount: Double
}

struct LocalSharingMarketDTO: Encodable, Sendable {
    let cardID: String
    let cardName: String
    let cardNumber: String
    let setName: String
    let quotes: [LocalSharingMarketQuoteDTO]
    let history: [LocalSharingMarketHistoryPointDTO]
}

private struct LocalSharingQuantityUpdate: Decodable {
    let variant: String
    let quantity: Int
}

private struct LocalSharingMetadataUpdate: Decodable {
    let wishlisted: Bool
    let notes: String
}

private struct LocalSharingLayoutUpdate: Decodable {
    let columns: String
    let spacing: String
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
#if DEBUG
        pairingCode = ProcessInfo.processInfo.arguments.contains("-BrowserEditorTesting")
            ? "000000"
            : String(format: "%06d", Int.random(in: 0...999_999))
#else
        pairingCode = String(format: "%06d", Int.random(in: 0...999_999))
#endif
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
                        releaseDate: $0.releaseDate,
                        category: Self.browserCategory(for: $0, seriesName: group.series.name)
                    )
                }
            }
            return .json(LocalSharingBootstrapDTO(
                sets: sets,
                allowsMultipleCopies: UserDefaults.standard.bool(
                    forKey: CollectionSettings.allowsMultipleCopiesKey
                ),
                browserGridColumns: UserDefaults.standard.string(forKey: Self.browserGridColumnsKey) ?? "4",
                browserGridSpacing: UserDefaults.standard.string(forKey: Self.browserGridSpacingKey) ?? "comfortable"
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

        let marketPrefix = "/api/cards/"
        if request.method == "GET",
           request.path.hasPrefix(marketPrefix),
           request.path.hasSuffix("/market") {
            let cardID = String(request.path.dropFirst(marketPrefix.count).dropLast("/market".count))
            do {
                guard let result = try await catalogStore.searchResults(cardIDs: [cardID]).first else {
                    return .error("This card is no longer available in the local catalog.", statusCode: 404)
                }
                let snapshot = try await catalogStore.details(for: result.card)
                let history = try await catalogStore.priceHistory(cardID: cardID, source: .cardmarket)
                return .json(Self.marketDTO(snapshot: snapshot, setName: result.setName, history: history))
            } catch {
                return .error("Cardmarket prices couldn’t be loaded. Try again.", statusCode: 500)
            }
        }

        guard request.headers["x-tallydex-csrf"] == csrfToken else {
            return .error("The editing session is no longer valid. Reload the page.", statusCode: 403)
        }
        if request.method == "POST", request.path == "/api/browser-layout" {
            guard let update = try? JSONDecoder().decode(LocalSharingLayoutUpdate.self, from: request.body),
                  ["auto", "2", "3", "4", "5", "6"].contains(update.columns),
                  ["compact", "comfortable", "spacious"].contains(update.spacing)
            else { return .error("Invalid browser layout.", statusCode: 400) }
            UserDefaults.standard.set(update.columns, forKey: Self.browserGridColumnsKey)
            UserDefaults.standard.set(update.spacing, forKey: Self.browserGridSpacingKey)
            return .json(["saved": true])
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

    private static func marketDTO(
        snapshot: CatalogCardSnapshot,
        setName: String,
        history: [CatalogPriceHistoryPoint]
    ) -> LocalSharingMarketDTO {
        let isoFormatter = ISO8601DateFormatter()
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let quotes = snapshot.prices
            .filter { $0.source == .cardmarket }
            .sorted { $0.variant.rawValue < $1.variant.rawValue }
            .map { quote in
                LocalSharingMarketQuoteDTO(
                    variant: quote.variant.rawValue,
                    variantName: quote.variant.displayName,
                    currencyCode: quote.currencyCode,
                    amount: quote.amount,
                    updatedAt: isoFormatter.string(from: quote.updatedAt),
                    average1Day: quote.average1Day,
                    average7Days: quote.average7Days,
                    average30Days: quote.average30Days,
                    marketplaceURL: quote.marketplaceURL?.absoluteString
                )
            }
        let historyPoints = history
            .sorted { $0.day < $1.day }
            .map { point in
                LocalSharingMarketHistoryPointDTO(
                    variant: point.variant.rawValue,
                    variantName: point.variant.displayName,
                    day: dayFormatter.string(from: point.day),
                    currencyCode: point.currencyCode,
                    amount: point.amount
                )
            }
        return LocalSharingMarketDTO(
            cardID: snapshot.card.id,
            cardName: snapshot.card.name,
            cardNumber: snapshot.card.localID,
            setName: setName,
            quotes: quotes,
            history: historyPoints
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
        let csrfJSON = (try? JSONEncoder().encode(csrfToken))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "\"\""
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>TallyDex Browser Editor</title><style>\(sharedCSS)\(editorCSS)</style></head><body>
        <header><div><div class="brand">TallyDex</div><small>Browser collection editor</small></div><div class="secure">Connected locally</div></header>
        <main class="editor"><section class="toolbar"><div class="field grow"><label for="search">Search cards</label><input id="search" type="search" placeholder="Lucario, SM95, Chaos Rising…"></div>
        <div class="field grow"><label for="choose-set">Or choose a set</label><button id="choose-set" class="select-button" type="button"><span id="selected-set">Choose a set</span><span aria-hidden="true">⌄</span></button></div><button id="load">Load cards</button></section>
        <section class="statusbar"><div id="status">Choose a set or search for cards.</div><div class="view-tools"><label>Cards per row <select id="grid-columns"><option value="auto">Auto</option><option value="2">2</option><option value="3">3</option><option value="4" selected>4</option><option value="5">5</option><option value="6">6</option></select></label><label>Spacing <select id="grid-spacing"><option value="compact">Compact</option><option value="comfortable" selected>Comfortable</option><option value="spacious">Spacious</option></select></label></div><div class="filters"><button data-filter="all" class="active">All</button><button data-filter="owned">Owned</button><button data-filter="missing">Missing</button></div></section>
        <div id="cards" class="cards"></div></main>
        <dialog id="set-dialog" class="sheet"><form method="dialog" class="dialog-shell"><div class="dialog-heading"><div><h2>Choose a set</h2><p>Search by set or series, then choose where to browse.</p></div><button class="icon-button" value="cancel" aria-label="Close">×</button></div><input id="set-search" type="search" placeholder="Search sets or series…" autocomplete="off"><div class="set-scopes" aria-label="Set type"><button type="button" data-set-scope="all" class="active">All</button><button type="button" data-set-scope="main">Main sets</button><button type="button" data-set-scope="special">Promos & subsets</button><button type="button" data-set-scope="other">Other</button></div><div id="set-list" class="set-list"></div></form></dialog>
        <dialog id="metadata-dialog" class="sheet metadata-sheet"><form method="dialog" class="dialog-shell"><div class="dialog-heading"><div><h2 id="metadata-title">Wishlist & notes</h2><p id="metadata-subtitle"></p></div><button class="icon-button" value="cancel" aria-label="Close">×</button></div><label class="wish"><input id="metadata-wishlist" type="checkbox"> Add to wishlist</label><label for="metadata-notes">Personal notes</label><textarea id="metadata-notes" maxlength="10000" placeholder="Binder location, condition, trade notes…"></textarea><div class="dialog-actions"><button class="secondary" value="cancel">Cancel</button><button id="save-metadata" type="button">Save</button></div></form></dialog>
        <dialog id="market-dialog" class="sheet market-sheet"><div class="dialog-shell"><div class="dialog-heading"><div><h2 id="market-title">Cardmarket</h2><p id="market-subtitle"></p></div><button class="icon-button" type="button" data-close-market aria-label="Close">×</button></div><div id="market-content"><div class="loader"></div></div></div></dialog>
        <div id="toast" role="status"></div>
        <script>
        const csrf=\(csrfJSON);const state={cards:[],sets:[],filter:'all',multiple:false,selectedSetID:'',setScope:'all',metadataCardID:'',marketCardID:'',marketData:null,marketVariant:'',marketRange:'30'};
        const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
        async function api(path,options={}){const headers={'Accept':'application/json',...(options.body?{'Content-Type':'application/json','X-TallyDex-CSRF':csrf}:{}),...(options.headers||{})};const response=await fetch(path,{...options,headers});if(response.status===401){location.reload();throw new Error('Session ended');}const data=await response.json();if(!response.ok)throw new Error(data.error||'Request failed');return data;}
        function toast(message,bad=false){const el=document.querySelector('#toast');el.textContent=message;el.className=bad?'show bad':'show';setTimeout(()=>el.className='',2200);}
        async function start(){try{const data=await api('/api/bootstrap');state.multiple=data.allowsMultipleCopies;state.sets=data.sets;document.querySelector('#grid-columns').value=data.browserGridColumns;document.querySelector('#grid-spacing').value=data.browserGridSpacing;applyLayout();renderSetList();}catch(e){document.querySelector('#status').textContent=e.message;}}
        async function load(){const q=document.querySelector('#search').value.trim(),setID=state.selectedSetID;if(!q&&!setID){toast('Choose a set or enter a search.',true);return;}const params=q?'q='+encodeURIComponent(q):'setID='+encodeURIComponent(setID);document.querySelector('#status').textContent='Loading cards and printing variants from your iPhone…';document.querySelector('#cards').innerHTML='<div class="loader"></div>';try{const data=await api('/api/cards?'+params);state.cards=data.cards;render();document.querySelector('#status').textContent=data.resultCount+' cards'+(data.mayBeTruncated?' · narrow your search to see every match':'');}catch(e){document.querySelector('#cards').innerHTML='';document.querySelector('#status').textContent=e.message;}}
        function renderSetList(){const query=document.querySelector('#set-search').value.trim().toLowerCase();const filtered=state.sets.filter(set=>(state.setScope==='all'||set.category===state.setScope)&&(!query||(set.name+' '+set.seriesName).toLowerCase().includes(query)));const groups=new Map();filtered.forEach(set=>{if(!groups.has(set.seriesName))groups.set(set.seriesName,[]);groups.get(set.seriesName).push(set);});document.querySelector('#set-list').innerHTML=[...groups].map(([series,sets])=>`<section class="set-group"><h3>${esc(series)}</h3>${sets.map(set=>`<button type="button" class="set-option" data-set-id="${esc(set.id)}"><span><strong>${esc(set.name)}</strong><small>${esc(series)}</small></span><span class="set-date">${esc(set.releaseDate||'Date unknown')}</span></button>`).join('')}</section>`).join('')||'<div class="empty compact">No sets match this search.</div>';}
        function visible(){return state.cards.filter(card=>state.filter==='all'||(state.filter==='owned'&&card.owned)||(state.filter==='missing'&&!card.owned));}
        function render(){const root=document.querySelector('#cards');root.innerHTML=visible().map(card=>`<article class="card" data-id="${esc(card.id)}"><div class="cardtop">${card.imageURL?`<img loading="lazy" src="${esc(card.imageURL)}" alt="">`:'<div class="placeholder">TD</div>'}<div><h2>${esc(card.name)}</h2><p>${esc(card.setName)} · #${esc(card.number)}</p></div></div><div class="variants">${card.variants.map(v=>variantHTML(card,v)).join('')}</div><div class="card-actions"><button type="button" class="metadata-button" data-edit-meta><span>${card.wishlisted?'♥':'♡'} Wishlist & notes</span><small>${card.notes?'Notes added':card.wishlisted?'Wishlisted':'Add details'}</small></button><button type="button" class="market-button" data-open-market><span>€ Cardmarket</span><small>Prices & history</small></button></div></article>`).join('')||'<div class="empty">No cards match this filter.</div>';}
        function variantHTML(card,v){if(state.multiple)return `<div class="variant"><span>${esc(v.name)}</span><div class="stepper"><button data-step="-1" data-variant="${esc(v.id)}" aria-label="Remove one">−</button><strong data-quantity="${esc(v.id)}">${v.quantity}</strong><button data-step="1" data-variant="${esc(v.id)}" aria-label="Add one">+</button></div></div>`;return `<label class="variant check"><span>${esc(v.name)}</span><input type="checkbox" data-check data-variant="${esc(v.id)}" ${v.quantity>0?'checked':''}></label>`;}
        async function setQuantity(card,variant,quantity){quantity=Math.max(0,Math.min(999,quantity));await api('/api/cards/'+encodeURIComponent(card.id)+'/quantity',{method:'POST',body:JSON.stringify({variant,quantity})});const item=card.variants.find(v=>v.id===variant);item.quantity=quantity;card.owned=card.variants.some(v=>v.quantity>0);toast('Saved '+card.name);if(state.filter!=='all')render();}
        function openMetadata(card){state.metadataCardID=card.id;document.querySelector('#metadata-title').textContent=card.name;document.querySelector('#metadata-subtitle').textContent=card.setName+' · #'+card.number;document.querySelector('#metadata-wishlist').checked=card.wishlisted;document.querySelector('#metadata-notes').value=card.notes;document.querySelector('#metadata-dialog').showModal();}
        function applyLayout(){const columns=document.querySelector('#grid-columns').value,spacing=document.querySelector('#grid-spacing').value,root=document.querySelector('#cards');root.style.setProperty('--grid-columns',columns==='auto'?'repeat(auto-fill,minmax(280px,1fr))':`repeat(${columns},minmax(0,1fr))`);root.dataset.spacing=spacing;}
        async function saveLayout(){applyLayout();try{await api('/api/browser-layout',{method:'POST',body:JSON.stringify({columns:document.querySelector('#grid-columns').value,spacing:document.querySelector('#grid-spacing').value})});}catch(err){toast(err.message,true);}}
        const money=(value,currency='EUR')=>value==null?'—':new Intl.NumberFormat(undefined,{style:'currency',currency:currency||'EUR'}).format(value);
        const dateLabel=value=>value?new Intl.DateTimeFormat(undefined,{dateStyle:'medium'}).format(new Date(value.length===10?value+'T00:00:00Z':value)):'—';
        function marketVariantOptions(data){const found=new Map();[...data.quotes,...data.history].forEach(item=>found.set(item.variant,item.variantName));return [...found].map(([id,name])=>({id,name}));}
        function rangePoints(points){if(state.marketRange==='all')return points;const days=Number(state.marketRange),cutoff=new Date();cutoff.setHours(0,0,0,0);cutoff.setDate(cutoff.getDate()-(days-1));return points.filter(point=>new Date(point.day+'T00:00:00Z')>=cutoff);}
        function marketChart(points,currency){if(!points.length)return '<div class="market-empty"><strong>No saved history in this range</strong><span>TallyDex saves one exact daily point when this printing refreshes. The graph will grow over time.</span></div>';const values=points.map(point=>point.amount),low=Math.min(...values),high=Math.max(...values),spread=high-low||Math.max(high*.08,.01),min=Math.max(0,low-spread*.18),max=high+spread*.18,w=760,h=260,px=46,py=26,times=points.map(point=>new Date(point.day+'T00:00:00Z').getTime()),first=Math.min(...times),last=Math.max(...times),x=(time)=>first===last?w/2:px+(time-first)/(last-first)*(w-px*2),y=(value)=>h-py-(value-min)/(max-min)*(h-py*2),line=points.map((point,index)=>`${index?'L':'M'} ${x(times[index]).toFixed(1)} ${y(point.amount).toFixed(1)}`).join(' '),area=`${line} L ${x(times[times.length-1]).toFixed(1)} ${h-py} L ${x(times[0]).toFixed(1)} ${h-py} Z`;return `<div class="chart"><svg viewBox="0 0 ${w} ${h}" role="img" aria-label="Price history from ${esc(dateLabel(points[0].day))} to ${esc(dateLabel(points.at(-1).day))}"><line x1="${px}" y1="${py}" x2="${px}" y2="${h-py}"/><line x1="${px}" y1="${h-py}" x2="${w-px}" y2="${h-py}"/><path class="chart-area" d="${area}"/><path class="chart-line" d="${line}"/>${points.map((point,index)=>`<circle cx="${x(times[index]).toFixed(1)}" cy="${y(point.amount).toFixed(1)}" r="4"><title>${esc(dateLabel(point.day))}: ${esc(money(point.amount,point.currencyCode||currency))}</title></circle>`).join('')}<text x="${px}" y="18">${esc(money(high,currency))}</text><text x="${px}" y="${h-5}">${esc(dateLabel(points[0].day))}</text><text x="${w-px}" y="${h-5}" text-anchor="end">${esc(dateLabel(points.at(-1).day))}</text></svg></div>`;}
        function renderMarket(){const data=state.marketData,root=document.querySelector('#market-content');if(!data)return;const variants=marketVariantOptions(data);if(!state.marketVariant||!variants.some(item=>item.id===state.marketVariant))state.marketVariant=variants[0]?.id||'';const quote=data.quotes.find(item=>item.variant===state.marketVariant),allPoints=data.history.filter(item=>item.variant===state.marketVariant).sort((a,b)=>a.day.localeCompare(b.day)),points=rangePoints(allPoints),currency=quote?.currencyCode||points.at(-1)?.currencyCode||'EUR',latest=points.at(-1),first=points[0],change=points.length>1?latest.amount-first.amount:null,percent=change!=null&&first.amount?change/first.amount*100:null,low=points.length?Math.min(...points.map(item=>item.amount)):null,high=points.length?Math.max(...points.map(item=>item.amount)):null;root.innerHTML=`<div class="market-controls"><label>Printing<select id="market-variant">${variants.map(item=>`<option value="${esc(item.id)}" ${item.id===state.marketVariant?'selected':''}>${esc(item.name)}</option>`).join('')}</select></label><div class="range-picker">${[['7','7D'],['30','30D'],['90','90D'],['all','All']].map(([id,label])=>`<button type="button" data-market-range="${id}" class="${state.marketRange===id?'active':''}">${label}</button>`).join('')}</div></div>${quote?`<section class="quote-panel"><div><span>Current Cardmarket price</span><strong>${esc(money(quote.amount,currency))}</strong><small>Updated ${esc(dateLabel(quote.updatedAt))}</small></div><div class="averages"><div><span>1-day average</span><strong>${esc(money(quote.average1Day,currency))}</strong></div><div><span>7-day average</span><strong>${esc(money(quote.average7Days,currency))}</strong></div><div><span>30-day average</span><strong>${esc(money(quote.average30Days,currency))}</strong></div></div>${quote.marketplaceURL?`<a class="market-link" href="${esc(quote.marketplaceURL)}" target="_blank" rel="noopener noreferrer">Open exact printing on Cardmarket ↗</a>`:''}</section>`:'<div class="market-empty compact"><strong>No current Cardmarket price</strong><span>TCGdex does not currently provide an exact price for this printing.</span></div>'}<div class="history-heading"><div><h3>Price history</h3><p>${allPoints.length} locally saved ${allPoints.length===1?'day':'days'} · exact printing only</p></div></div>${marketChart(points,currency)}${points.length?`<div class="summary-grid"><div><span>Current</span><strong>${esc(money(latest.amount,currency))}</strong></div><div><span>Change</span><strong class="${change>0?'up':change<0?'down':''}">${change==null?'—':(change>0?'+':'')+money(change,currency)}</strong><small>${percent==null?'':(percent>0?'+':'')+percent.toFixed(1)+'%'}</small></div><div><span>Low</span><strong>${esc(money(low,currency))}</strong></div><div><span>High</span><strong>${esc(money(high,currency))}</strong></div></div>`:''}<p class="market-note">Rolling averages come from TCGdex. Price history is stored locally on this iPhone when the exact printing refreshes; TallyDex never substitutes another variant or converts currencies.</p>`;document.querySelector('#market-variant').onchange=e=>{state.marketVariant=e.target.value;renderMarket();};root.querySelector('.range-picker').onclick=e=>{const button=e.target.closest('[data-market-range]');if(!button)return;state.marketRange=button.dataset.marketRange;renderMarket();};}
        async function openMarket(card){state.marketCardID=card.id;state.marketData=null;state.marketVariant='';state.marketRange='30';document.querySelector('#market-title').textContent=card.name;document.querySelector('#market-subtitle').textContent=card.setName+' · #'+card.number+' · Cardmarket via TCGdex';document.querySelector('#market-content').innerHTML='<div class="loader"></div>';document.querySelector('#market-dialog').showModal();try{state.marketData=await api('/api/cards/'+encodeURIComponent(card.id)+'/market');if(state.marketCardID===card.id)renderMarket();}catch(err){document.querySelector('#market-content').innerHTML=`<div class="market-empty"><strong>Prices unavailable</strong><span>${esc(err.message)}</span></div>`;}}
        document.querySelector('#load').onclick=load;document.querySelector('#search').addEventListener('keydown',e=>{if(e.key==='Enter'){state.selectedSetID='';document.querySelector('#selected-set').textContent='Choose a set';load();}});
        document.querySelector('#choose-set').onclick=()=>{document.querySelector('#set-dialog').showModal();requestAnimationFrame(()=>document.querySelector('#set-search').focus());};
        document.querySelector('#set-search').oninput=renderSetList;document.querySelector('.set-scopes').onclick=e=>{const button=e.target.closest('[data-set-scope]');if(!button)return;state.setScope=button.dataset.setScope;document.querySelectorAll('[data-set-scope]').forEach(b=>b.classList.toggle('active',b===button));renderSetList();};
        document.querySelector('#set-list').onclick=e=>{const option=e.target.closest('[data-set-id]');if(!option)return;const set=state.sets.find(item=>item.id===option.dataset.setId);state.selectedSetID=set.id;document.querySelector('#selected-set').textContent=set.seriesName+' · '+set.name;document.querySelector('#search').value='';document.querySelector('#set-dialog').close();load();};
        document.querySelector('.filters').onclick=e=>{const button=e.target.closest('[data-filter]');if(!button)return;state.filter=button.dataset.filter;document.querySelectorAll('[data-filter]').forEach(b=>b.classList.toggle('active',b===button));render();};
        document.querySelector('#cards').addEventListener('click',async e=>{const article=e.target.closest('.card');if(!article)return;const card=state.cards.find(c=>c.id===article.dataset.id);try{const step=e.target.closest('[data-step]');if(step){const item=card.variants.find(v=>v.id===step.dataset.variant);await setQuantity(card,item.id,item.quantity+Number(step.dataset.step));article.querySelector(`[data-quantity="${CSS.escape(item.id)}"]`).textContent=item.quantity;return;}if(e.target.closest('[data-edit-meta]')){openMetadata(card);return;}if(e.target.closest('[data-open-market]'))openMarket(card);}catch(err){toast(err.message,true);render();}});
        document.querySelector('#cards').addEventListener('change',async e=>{if(!e.target.matches('[data-check]'))return;const article=e.target.closest('.card'),card=state.cards.find(c=>c.id===article.dataset.id);try{await setQuantity(card,e.target.dataset.variant,e.target.checked?1:0);}catch(err){toast(err.message,true);render();}});
        document.querySelector('#save-metadata').onclick=async()=>{const card=state.cards.find(c=>c.id===state.metadataCardID);if(!card)return;const wishlisted=document.querySelector('#metadata-wishlist').checked,notes=document.querySelector('#metadata-notes').value;try{await api('/api/cards/'+encodeURIComponent(card.id)+'/metadata',{method:'POST',body:JSON.stringify({wishlisted,notes})});card.wishlisted=wishlisted;card.notes=notes;document.querySelector('#metadata-dialog').close();render();toast('Wishlist and notes saved');}catch(err){toast(err.message,true);}};
        document.querySelector('#grid-columns').onchange=saveLayout;document.querySelector('#grid-spacing').onchange=saveLayout;document.querySelector('[data-close-market]').onclick=()=>document.querySelector('#market-dialog').close();
        document.querySelectorAll('dialog').forEach(dialog=>dialog.addEventListener('click',e=>{if(e.target===dialog)dialog.close();}));
        start();
        </script></body></html>
        """
    }

    private static let sharedCSS = """
    :root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#14213d;background:#f3f5f9;color-scheme:light}*{box-sizing:border-box}body{margin:0}.brand{font-weight:900;font-size:2rem;color:#ffcb05;-webkit-text-stroke:1px #086bd8;text-shadow:2px 2px #086bd8}.pairing{width:min(92%,460px);margin:10vh auto;background:white;padding:2rem;border-radius:28px;box-shadow:0 18px 70px #0b2d5b25}.pairing h1{margin-bottom:.5rem}.pairing p{color:#59677c;line-height:1.5}.pairing label,.field label,details label{display:block;font-weight:700;margin:.8rem 0 .35rem}.pairing input,input,select,textarea{width:100%;font:inherit;border:1px solid #cad2df;border-radius:12px;padding:.8rem;background:white}.pairing input{font-size:2rem;letter-spacing:.35em;text-align:center}.pairing button,.button,button{border:0;border-radius:12px;background:#087fe8;color:white;font:inherit;font-weight:700;padding:.85rem 1.1rem;cursor:pointer;text-decoration:none;display:inline-block}.pairing button{width:100%;margin-top:1rem}.error{color:#b42318!important;background:#fee4e2;padding:.7rem;border-radius:10px}
    """

    private static let editorCSS = """
    header{display:flex;justify-content:space-between;align-items:center;padding:1rem 4vw;background:white;position:sticky;top:0;z-index:5;box-shadow:0 2px 20px #102a4320}header small{color:#66758a}.secure{font-weight:700;color:#18794e;background:#def7e7;padding:.55rem .8rem;border-radius:999px}.editor{width:min(94%,1400px);margin:1.5rem auto}.toolbar{display:flex;gap:1rem;align-items:end;background:white;padding:1rem;border-radius:18px}.grow{flex:1}.field label{margin-top:0}.select-button{width:100%;display:flex;align-items:center;justify-content:space-between;text-align:left;background:white;color:#14213d;border:1px solid #cad2df;font-weight:500;padding:.8rem}.statusbar{display:flex;justify-content:space-between;align-items:center;gap:1rem;padding:1rem 0;color:#536277}.view-tools{display:flex;align-items:center;gap:.7rem;margin-left:auto}.view-tools label{display:flex;align-items:center;gap:.4rem;font-size:.85rem;font-weight:700;white-space:nowrap}.view-tools select{width:auto;padding:.5rem 2rem .5rem .65rem}.filters,.set-scopes,.range-picker{display:flex;background:#e2e7ef;border-radius:12px;padding:3px}.filters button,.set-scopes button,.range-picker button{background:transparent;color:#344054;padding:.55rem .9rem}.filters button.active,.set-scopes button.active,.range-picker button.active{background:white;color:#087fe8;box-shadow:0 2px 7px #1112}.cards{--grid-columns:repeat(4,minmax(0,1fr));--card-gap:1rem;--card-padding:1rem;display:grid;grid-template-columns:var(--grid-columns);grid-auto-rows:1fr;gap:var(--card-gap);align-items:stretch}.cards[data-spacing="compact"]{--card-gap:.55rem;--card-padding:.7rem}.cards[data-spacing="spacious"]{--card-gap:1.5rem;--card-padding:1.3rem}.card{height:100%;display:flex;flex-direction:column;background:white;border-radius:20px;padding:var(--card-padding);box-shadow:0 7px 26px #102a4312;min-width:0}.cardtop{display:flex;gap:1rem;align-items:center;min-height:103px}.cardtop>div:last-child{min-width:0}.cardtop img,.placeholder{flex:none;width:74px;height:103px;object-fit:contain;border-radius:8px;background:#edf1f7}.placeholder{display:grid;place-items:center;font-weight:900;color:#087fe8}.card h2{font-size:1.1rem;margin:0 0 .35rem;overflow-wrap:anywhere}.card p{margin:0;color:#6b778c;overflow-wrap:anywhere}.variants{margin-top:1rem;border-top:1px solid #e8ebf0}.variant{min-height:48px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #e8ebf0}.check input{width:24px;height:24px}.stepper{display:flex;align-items:center;gap:.6rem}.stepper button{width:36px;height:36px;padding:0;font-size:1.3rem}.stepper strong{min-width:2ch;text-align:center}.card-actions{display:grid;grid-template-columns:1fr 1fr;gap:.5rem;margin-top:auto;padding-top:1rem}.metadata-button,.market-button{width:100%;min-width:0;background:#eef6ff;color:#075fae;display:flex;justify-content:space-between;align-items:flex-start;flex-direction:column;gap:.15rem;text-align:left;padding:.7rem}.metadata-button small,.market-button small{color:#66758a;font-weight:500}.market-button{background:#fff5d6;color:#725200}.sheet{width:min(92vw,760px);max-height:86vh;border:0;border-radius:24px;padding:0;box-shadow:0 30px 100px #102a4355}.sheet::backdrop{background:#102a4366;backdrop-filter:blur(3px)}.dialog-shell{padding:1.25rem}.dialog-heading{display:flex;align-items:flex-start;justify-content:space-between;gap:1rem}.dialog-heading h2{margin:0}.dialog-heading p{margin:.35rem 0 1rem;color:#66758a}.icon-button{flex:none;width:42px;height:42px;padding:0;border-radius:50%;font-size:1.6rem;background:#edf1f7;color:#344054}.set-scopes{margin:1rem 0;overflow-x:auto}.set-scopes button{white-space:nowrap}.set-list{max-height:55vh;overflow:auto;padding-right:.3rem}.set-group{margin:0 0 1rem}.set-group h3{position:sticky;top:0;margin:0;padding:.65rem .25rem;background:white;color:#536277;font-size:.9rem;text-transform:uppercase;letter-spacing:.04em}.set-option{width:100%;display:flex;justify-content:space-between;align-items:center;gap:1rem;text-align:left;background:white;color:#14213d;border-top:1px solid #e8ebf0;border-radius:0;padding:.8rem .25rem}.set-option span:first-child{display:flex;flex-direction:column;gap:.15rem}.set-option small,.set-date{color:#66758a;font-weight:500}.set-date{white-space:nowrap}.metadata-sheet{width:min(92vw,560px)}.metadata-sheet label{display:block;font-weight:700;margin:1rem 0 .4rem}.wish{display:flex!important;align-items:center;gap:.65rem}.wish input{width:24px;height:24px}.metadata-sheet textarea{min-height:150px;resize:vertical}.dialog-actions{display:flex;justify-content:flex-end;gap:.7rem;margin-top:1rem}.secondary{background:#e8edf4;color:#344054}.market-sheet{width:min(94vw,900px)}.market-controls{display:flex;justify-content:space-between;align-items:end;gap:1rem;margin-bottom:1rem}.market-controls label{font-weight:700}.market-controls select{margin-top:.35rem}.quote-panel{background:#f5f8fc;border-radius:18px;padding:1rem;display:grid;grid-template-columns:minmax(150px,.7fr) minmax(320px,1.5fr);gap:1rem;align-items:center}.quote-panel>div:first-child{display:flex;flex-direction:column;gap:.25rem}.quote-panel>div:first-child>strong{font-size:2rem}.quote-panel span,.summary-grid span{color:#66758a;font-size:.85rem}.quote-panel small,.summary-grid small{color:#66758a}.averages{display:grid;grid-template-columns:repeat(3,1fr);gap:.6rem}.averages div,.summary-grid div{display:flex;flex-direction:column;gap:.2rem;background:white;border-radius:12px;padding:.75rem}.market-link{grid-column:1/-1;color:#075fae;font-weight:700;text-decoration:none}.history-heading{display:flex;justify-content:space-between;align-items:end;margin:1.3rem 0 .4rem}.history-heading h3{margin:0}.history-heading p{margin:.25rem 0 0;color:#66758a}.chart{background:#f5f8fc;border-radius:16px;padding:.5rem}.chart svg{display:block;width:100%;height:auto;max-height:290px;overflow:visible}.chart line{stroke:#b8c4d4;stroke-width:1}.chart text{fill:#66758a;font-size:13px}.chart-area{fill:#cfe8ff;stroke:none}.chart-line{fill:none;stroke:#087fe8;stroke-width:4;stroke-linecap:round;stroke-linejoin:round}.chart circle{fill:white;stroke:#087fe8;stroke-width:3}.summary-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:.6rem;margin-top:.8rem}.summary-grid strong{font-size:1.15rem}.up{color:#18794e}.down{color:#b42318}.market-note{color:#66758a;font-size:.85rem;line-height:1.45}.market-empty{min-height:240px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:.45rem;text-align:center;color:#66758a}.market-empty strong{font-size:1.1rem;color:#344054}.market-empty.compact{min-height:auto;padding:1.2rem;background:#f5f8fc;border-radius:16px}#toast{position:fixed;right:1rem;bottom:1rem;background:#14213d;color:white;padding:.8rem 1rem;border-radius:12px;opacity:0;transform:translateY(20px);transition:.2s;pointer-events:none;z-index:20}#toast.show{opacity:1;transform:none}#toast.bad{background:#b42318}.loader{width:42px;height:42px;border:5px solid #d8e9fb;border-top-color:#087fe8;border-radius:50%;animation:spin .8s linear infinite;margin:4rem auto}.empty{text-align:center;color:#66758a;padding:4rem}.empty.compact{padding:2rem}@keyframes spin{to{transform:rotate(360deg)}}@media(max-width:900px){.statusbar{flex-wrap:wrap}.view-tools{order:3;width:100%;margin:0}.quote-panel{grid-template-columns:1fr}.market-link{grid-column:auto}}@media(max-width:700px){.toolbar{flex-direction:column;align-items:stretch}.statusbar{align-items:flex-start;flex-direction:column}.view-tools{align-items:flex-start;flex-wrap:wrap}.cards{grid-template-columns:1fr}.secure{font-size:.8rem}.set-date{display:none}.card-actions{grid-template-columns:1fr}.market-controls{align-items:stretch;flex-direction:column}.range-picker{width:100%}.range-picker button{flex:1}.averages,.summary-grid{grid-template-columns:1fr 1fr}}
    """

    private static let browserGridColumnsKey = "browserEditorGridColumns"
    private static let browserGridSpacingKey = "browserEditorGridSpacing"

    private static func browserCategory(for set: CatalogSet, seriesName: String) -> String {
        let normalizedSeries = seriesName.lowercased()
        if normalizedSeries == "trainer kits"
            || normalizedSeries == "mcdonald's collection"
            || normalizedSeries == "pop"
            || normalizedSeries == "miscellaneous" {
            return "other"
        }

        let normalizedName = set.name.lowercased()
        let specialMarkers = [
            "promo", "trainer gallery", "galarian gallery", "shiny vault",
            "classic collection", " energy", "alternate", "unown collection"
        ]
        return specialMarkers.contains(where: normalizedName.contains) ? "special" : "main"
    }
}
