import CoreLocation
import Photos
import SwiftUI

/// Reverse-geocoded name of a place.
struct PlaceInfo: Codable {
    var city: String?
    var country: String?
    var countryCode: String?

    var flag: String {
        guard let code = countryCode?.uppercased(), code.count == 2 else { return "" }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }))
    }
}

@MainActor
final class TravelStore: ObservableObject {
    enum State { case idle, needsPermission, denied, loading, loaded }

    @Published private(set) var state: State = .idle
    @Published private(set) var trips: [Trip] = []
    @Published private(set) var places: [String: PlaceInfo] = [:]
    @Published var homeRadiusKm: Double {
        didSet {
            UserDefaults.standard.set(homeRadiusKm, forKey: Keys.homeRadius)
            rebuild()
        }
    }

    private enum Keys {
        static let homeRadius = "homeRadiusKm"
        static let places = "placeCache.v1"
    }

    private var points: [PhotoPoint] = []
    private let geocoder = CLGeocoder()
    private var geocodeQueue: [Stop] = []
    private var isGeocoding = false

    init() {
        let saved = UserDefaults.standard.double(forKey: Keys.homeRadius)
        homeRadiusKm = saved > 0 ? saved : 50
        if let data = UserDefaults.standard.data(forKey: Keys.places),
           let cached = try? JSONDecoder().decode([String: PlaceInfo].self, from: data) {
            places = cached
        }
    }

    // MARK: Photos access

    func start() async {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            await load()
        case .notDetermined:
            state = .needsPermission
        default:
            state = .denied
        }
    }

    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if status == .authorized || status == .limited {
            await load()
        } else {
            state = .denied
        }
    }

    func load() async {
        if trips.isEmpty { state = .loading }
        points = await Task.detached(priority: .userInitiated) { TravelStore.fetchPoints() }.value
        rebuild()
        state = .loaded
    }

    /// Reads only each asset's identifier, date and GPS location. No image data is loaded or copied.
    nonisolated private static func fetchPoints() -> [PhotoPoint] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
        )
        let assets = PHAsset.fetchAssets(with: options)
        var points: [PhotoPoint] = []
        points.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            guard let location = asset.location, let date = asset.creationDate else { return }
            let c = location.coordinate
            guard CLLocationCoordinate2DIsValid(c), !(c.latitude == 0 && c.longitude == 0) else { return }
            points.append(PhotoPoint(id: asset.localIdentifier, date: date, latitude: c.latitude, longitude: c.longitude))
        }
        return points
    }

    private func rebuild() {
        var settings = TripBuilder.Settings()
        settings.homeRadiusKm = homeRadiusKm
        trips = TripBuilder.build(points: points, settings: settings).trips
        enqueueNames(for: trips.flatMap(\.namingStops))
    }

    // MARK: Place names

    func title(for trip: Trip) -> String {
        let infos = trip.namingStops.compactMap { places[$0.placeKey] }
        guard !infos.isEmpty else { return "Locating…" }
        var names: [String] = []
        for info in infos {
            if let name = info.city ?? info.country, !names.contains(name) { names.append(name) }
        }
        return names.isEmpty ? "Unknown place" : names.joined(separator: " · ")
    }

    func flags(for trip: Trip) -> String {
        var flags: [String] = []
        for stop in trip.namingStops {
            if let flag = places[stop.placeKey]?.flag, !flag.isEmpty, !flags.contains(flag) { flags.append(flag) }
        }
        return flags.joined()
    }

    func name(for stop: Stop) -> String? {
        guard let info = places[stop.placeKey] else { return nil }
        let name = [info.city, info.country].compactMap { $0 }.joined(separator: ", ")
        return name.isEmpty ? "Unknown place" : name
    }

    var countryCount: Int {
        Set(trips.flatMap { $0.namingStops.compactMap { places[$0.placeKey]?.countryCode } }).count
    }

    /// Names are looked up one at a time (Apple limits geocoding requests) and cached forever.
    func enqueueNames(for stops: [Stop]) {
        let missing = stops.filter { places[$0.placeKey] == nil }
        // Newly requested stops (e.g. the trip being viewed) go to the front of the queue.
        geocodeQueue.insert(contentsOf: missing, at: 0)
        guard !isGeocoding else { return }
        isGeocoding = true
        Task { await drainGeocodeQueue() }
    }

    private func drainGeocodeQueue() async {
        defer { isGeocoding = false }
        var failures = 0
        while !geocodeQueue.isEmpty {
            let stop = geocodeQueue.removeFirst()
            if places[stop.placeKey] != nil { continue }
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(
                    CLLocation(latitude: stop.latitude, longitude: stop.longitude)
                )
                failures = 0
                let p = placemarks.first
                places[stop.placeKey] = PlaceInfo(
                    city: p?.locality ?? p?.subAdministrativeArea ?? p?.administrativeArea ?? p?.name,
                    country: p?.country ?? p?.ocean,
                    countryCode: p?.isoCountryCode
                )
                savePlaces()
                try? await Task.sleep(for: .seconds(1.2))
            } catch {
                // Usually rate limiting or no network: wait, then retry this stop a couple of times.
                failures += 1
                if failures <= 3 {
                    geocodeQueue.insert(stop, at: 0)
                    try? await Task.sleep(for: .seconds(15))
                } else {
                    failures = 0
                }
            }
        }
    }

    private func savePlaces() {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: Keys.places)
        }
    }
}
