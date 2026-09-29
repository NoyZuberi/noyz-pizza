import MapKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TravelStore
    @State private var path: [Trip] = []
    @State private var showMap = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch store.state {
                case .idle, .loading:
                    ProgressView("Finding your trips…")
                case .needsPermission:
                    PermissionView()
                case .denied:
                    DeniedView()
                case .loaded:
                    if store.trips.isEmpty {
                        ContentUnavailableView(
                            "No trips yet",
                            systemImage: "airplane",
                            description: Text("No photos with a location were found away from home.")
                        )
                    } else if showMap {
                        TripsMap(path: $path)
                    } else {
                        TripList()
                    }
                }
            }
            .navigationTitle("My Travels")
            .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
            .toolbar {
                if store.state == .loaded, !store.trips.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Picker("View", selection: $showMap) {
                            Image(systemName: "list.bullet").tag(false)
                            Image(systemName: "map").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    ToolbarItem(placement: .topBarTrailing) { SettingsMenu() }
                }
            }
        }
        .task { await store.start() }
    }
}

private struct TripList: View {
    @EnvironmentObject private var store: TravelStore

    private var tripsByYear: [(year: Int, trips: [Trip])] {
        let grouped = Dictionary(grouping: store.trips) { Calendar.current.component(.year, from: $0.startDate) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    var body: some View {
        List {
            Section {
                Text("\(store.trips.count) trips · \(store.countryCount) countries")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(tripsByYear, id: \.year) { group in
                Section(String(group.year)) {
                    ForEach(group.trips) { trip in
                        NavigationLink(value: trip) { TripRow(trip: trip) }
                    }
                }
            }
        }
        .refreshable { await store.load() }
    }
}

struct TripRow: View {
    @EnvironmentObject private var store: TravelStore
    let trip: Trip

    var body: some View {
        HStack(spacing: 12) {
            TripCover(trip: trip)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(store.flags(for: trip)) \(store.title(for: trip))")
                    .font(.headline)
                    .lineLimit(2)
                Text(trip.dateRangeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(trip.assetIdentifiers.count) photos · \(trip.stops.count) \(trip.stops.count == 1 ? "place" : "places")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct TripsMap: View {
    @EnvironmentObject private var store: TravelStore
    @Binding var path: [Trip]
    @State private var selection: String?

    var body: some View {
        Map(selection: $selection) {
            ForEach(store.trips) { trip in
                Marker(store.title(for: trip), systemImage: "camera.fill", coordinate: trip.mainStop.coordinate)
                    .tag(trip.id)
            }
        }
        .onChange(of: selection) { _, id in
            guard let id, let trip = store.trips.first(where: { $0.id == id }) else { return }
            path.append(trip)
            selection = nil
        }
    }
}

private struct SettingsMenu: View {
    @EnvironmentObject private var store: TravelStore

    var body: some View {
        Menu {
            Picker("Ignore photos within", selection: $store.homeRadiusKm) {
                ForEach([10.0, 25, 50, 100, 200], id: \.self) { km in
                    Text("\(Int(km)) km of home").tag(km)
                }
            }
            Button {
                Task { await store.load() }
            } label: {
                Label("Rescan photos", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "gearshape")
        }
    }
}

private struct PermissionView: View {
    @EnvironmentObject private var store: TravelStore

    var body: some View {
        ContentUnavailableView {
            Label("Your trips, from your photos", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("My Travels reads where and when your photos were taken to build a list of the places you travelled to. Your photos are not copied, moved or uploaded.")
        } actions: {
            Button("Allow access to Photos") { Task { await store.requestAccess() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct DeniedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No access to Photos", systemImage: "lock")
        } description: {
            Text("Allow access to your photos in Settings so My Travels can find your trips.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

extension Stop {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension Trip {
    var dateRangeText: String {
        let sameDay = Calendar.current.isDate(startDate, inSameDayAs: endDate)
        if sameDay { return startDate.formatted(date: .abbreviated, time: .omitted) }
        return (startDate..<endDate).formatted(.interval.day().month(.abbreviated).year())
    }

    var dayCount: Int {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: startDate),
            to: Calendar.current.startOfDay(for: endDate)
        ).day ?? 0
        return days + 1
    }
}
