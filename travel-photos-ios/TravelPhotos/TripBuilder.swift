import Foundation

/// One photo (or video) from the library, reduced to what we need for grouping.
struct PhotoPoint: Sendable {
    let id: String          // PHAsset.localIdentifier — a reference, never a copy
    let date: Date
    let latitude: Double
    let longitude: Double
}

/// A place inside a trip where photos were taken close together.
struct Stop: Identifiable, Sendable {
    let id: Int
    let latitude: Double
    let longitude: Double
    let firstDate: Date
    let photoCount: Int

    /// Key used for caching reverse-geocoded names (~1 km precision).
    var placeKey: String { String(format: "%.2f,%.2f", latitude, longitude) }
}

struct Trip: Identifiable, Hashable, Sendable {
    let id: String
    let assetIdentifiers: [String]   // chronological
    let startDate: Date
    let endDate: Date
    let stops: [Stop]                // chronological — this is the travel path
    let namingStops: [Stop]          // the biggest, clearly separate stops, used for the title

    var mainStop: Stop { namingStops[0] }

    static func == (lhs: Trip, rhs: Trip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum TripBuilder {
    struct Settings {
        var homeRadiusKm: Double = 50
        /// A new trip starts when there is a longer gap than this between photos taken away from home.
        var maxGapHours: Double = 72
        /// Photos further apart than this start a new stop within a trip.
        var stopRadiusKm: Double = 5
        var minPhotosPerTrip: Int = 2
        /// A place counts as "home" when photos were taken there on at least this many different days.
        var homeMinDistinctDays: Int = 60
    }

    struct Result {
        let homes: [(latitude: Double, longitude: Double)]
        let trips: [Trip]
    }

    static func build(points: [PhotoPoint], settings: Settings = Settings()) -> Result {
        let sorted = points.sorted { $0.date < $1.date }
        let homes = detectHomes(sorted, minDistinctDays: settings.homeMinDistinctDays)

        let away = sorted.filter { p in
            !homes.contains { distanceKm(p.latitude, p.longitude, $0.latitude, $0.longitude) <= settings.homeRadiusKm }
        }

        var groups: [[PhotoPoint]] = []
        for p in away {
            if let last = groups.last?.last,
               p.date.timeIntervalSince(last.date) <= settings.maxGapHours * 3600 {
                groups[groups.count - 1].append(p)
            } else {
                groups.append([p])
            }
        }

        let trips = groups
            .filter { $0.count >= settings.minPhotosPerTrip }
            .map { makeTrip($0, stopRadiusKm: settings.stopRadiusKm) }
            .sorted { $0.startDate > $1.startDate }   // newest first

        return Result(homes: homes, trips: trips)
    }

    /// Home = the ~20 km grid cell photographed on the most distinct days, plus any other cell
    /// photographed on many distinct days (e.g. a previous home after moving).
    static func detectHomes(_ points: [PhotoPoint], minDistinctDays: Int) -> [(latitude: Double, longitude: Double)] {
        struct Cell { var days = Set<Int>(); var latSum = 0.0; var lonSum = 0.0; var count = 0 }
        var cells: [String: Cell] = [:]
        let cellSize = 0.2
        for p in points {
            let key = "\(Int((p.latitude / cellSize).rounded(.down))):\(Int((p.longitude / cellSize).rounded(.down)))"
            var cell = cells[key, default: Cell()]
            cell.days.insert(Int(p.date.timeIntervalSince1970 / 86_400))
            cell.latSum += p.latitude
            cell.lonSum += p.longitude
            cell.count += 1
            cells[key] = cell
        }
        let ranked = cells.values.sorted { $0.days.count > $1.days.count }
        return ranked
            .enumerated()
            .filter { $0.offset == 0 || $0.element.days.count >= minDistinctDays }
            .map { (latitude: $0.element.latSum / Double($0.element.count), longitude: $0.element.lonSum / Double($0.element.count)) }
    }

    static func makeTrip(_ points: [PhotoPoint], stopRadiusKm: Double) -> Trip {
        var stopGroups: [[PhotoPoint]] = []
        for p in points {
            if let anchor = stopGroups.last?.first,
               distanceKm(anchor.latitude, anchor.longitude, p.latitude, p.longitude) <= stopRadiusKm {
                stopGroups[stopGroups.count - 1].append(p)
            } else {
                stopGroups.append([p])
            }
        }

        let stops = stopGroups.enumerated().map { index, group in
            Stop(
                id: index,
                latitude: group.map(\.latitude).reduce(0, +) / Double(group.count),
                longitude: group.map(\.longitude).reduce(0, +) / Double(group.count),
                firstDate: group[0].date,
                photoCount: group.count
            )
        }

        // Pick up to 3 of the biggest stops that are clearly different places (> 30 km apart).
        var naming: [Stop] = []
        for stop in stops.sorted(by: { $0.photoCount > $1.photoCount }) where naming.count < 3 {
            if naming.allSatisfy({ distanceKm($0.latitude, $0.longitude, stop.latitude, stop.longitude) > 30 }) {
                naming.append(stop)
            }
        }

        return Trip(
            id: points[0].id,
            assetIdentifiers: points.map(\.id),
            startDate: points[0].date,
            endDate: points[points.count - 1].date,
            stops: stops,
            namingStops: naming
        )
    }

    /// Great-circle distance (haversine).
    static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

enum GoogleMaps {
    /// Pin on a single place.
    static func placeURL(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents(string: "https://www.google.com/maps/search/")!
        c.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: coordinate(latitude, longitude)),
        ]
        return c.url!
    }

    /// The trip's path, in the order the photos were taken. Google Maps URLs allow
    /// at most 9 waypoints, so long trips are sampled evenly (first and last stop always kept).
    static func routeURL(stops: [Stop]) -> URL {
        guard stops.count >= 2 else {
            let s = stops[0]
            return placeURL(latitude: s.latitude, longitude: s.longitude)
        }
        let path = sample(stops, max: 11)
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: coordinate(path[0].latitude, path[0].longitude)),
            URLQueryItem(name: "destination", value: coordinate(path[path.count - 1].latitude, path[path.count - 1].longitude)),
        ]
        let middle = path.dropFirst().dropLast()
        if !middle.isEmpty {
            items.append(URLQueryItem(name: "waypoints", value: middle.map { coordinate($0.latitude, $0.longitude) }.joined(separator: "|")))
        }
        var c = URLComponents(string: "https://www.google.com/maps/dir/")!
        c.queryItems = items
        return c.url!
    }

    static func sample<T>(_ items: [T], max: Int) -> [T] {
        guard items.count > max else { return items }
        return (0..<max).map { i in items[Int((Double(i) * Double(items.count - 1) / Double(max - 1)).rounded())] }
    }

    private static func coordinate(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.6f,%.6f", lat, lon)
    }
}
