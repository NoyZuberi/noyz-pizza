import MapKit
import Photos
import SwiftUI

struct TripDetailView: View {
    @EnvironmentObject private var store: TravelStore
    @Environment(\.openURL) private var openURL
    let trip: Trip

    @State private var assets: [PHAsset] = []
    @State private var viewerStart: ViewerStart?

    private struct ViewerStart: Identifiable { let id: Int }
    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 2)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                TripMap(trip: trip)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                Button {
                    openURL(GoogleMaps.routeURL(stops: trip.stops))
                } label: {
                    Label(trip.stops.count > 1 ? "Open trip route in Google Maps" : "Open in Google Maps",
                          systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                if trip.stops.count > 1 { stopsSection }
                photosSection
            }
            .padding(.vertical)
        }
        .navigationTitle(store.title(for: trip))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: trip.id) {
            store.enqueueNames(for: trip.stops)
            assets = ImageLoader.shared.assets(for: trip.assetIdentifiers)
        }
        .fullScreenCover(item: $viewerStart) { start in
            PhotoViewer(assets: assets, selection: start.id)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(store.flags(for: trip)) \(store.title(for: trip))")
                .font(.title2.bold())
            Text("\(trip.dateRangeText) · \(trip.dayCount) \(trip.dayCount == 1 ? "day" : "days")")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var stopsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Path").font(.headline).padding(.horizontal).padding(.bottom, 8)
            ForEach(Array(trip.stops.enumerated()), id: \.element.id) { index, stop in
                Button {
                    openURL(GoogleMaps.placeURL(latitude: stop.latitude, longitude: stop.longitude))
                } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.accentColor))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.name(for: stop) ?? "Locating…")
                                .foregroundStyle(.primary)
                            Text("\(stop.firstDate.formatted(date: .abbreviated, time: .shortened)) · \(stop.photoCount) photos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos (\(trip.assetIdentifiers.count))").font(.headline).padding(.horizontal)
            Text("These are the original photos from your iPhone library — nothing was copied.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    Button {
                        viewerStart = ViewerStart(id: index)
                    } label: {
                        AssetThumbnail(asset: asset)
                            .aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct TripMap: View {
    @EnvironmentObject private var store: TravelStore
    let trip: Trip

    var body: some View {
        Map(initialPosition: .automatic) {
            if trip.stops.count > 1 {
                MapPolyline(coordinates: trip.stops.map(\.coordinate))
                    .stroke(.blue, lineWidth: 3)
            }
            ForEach(Array(trip.stops.enumerated()), id: \.element.id) { index, stop in
                Marker(store.name(for: stop) ?? "", monogram: Text("\(index + 1)"), coordinate: stop.coordinate)
            }
        }
    }
}
