import AVKit
import Photos
import SwiftUI

/// Loads images straight from the iPhone photo library (including iCloud originals). Nothing is copied to disk.
final class ImageLoader {
    static let shared = ImageLoader()
    private let manager = PHCachingImageManager()

    /// Fetches assets and returns them in the same order as `identifiers`.
    func assets(for identifiers: [String]) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var byID: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return identifiers.compactMap { byID[$0] }
    }

    func image(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat   // one callback only
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func playerItem(for asset: PHAsset) async -> AVPlayerItem? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        return await withCheckedContinuation { continuation in
            manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }
}

struct AssetThumbnail: View {
    let asset: PHAsset
    var pointSize: CGFloat = 120
    @State private var image: UIImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(5)
                }
            }
            .clipped()
            .task(id: asset.localIdentifier) {
                let side = pointSize * scale
                image = await ImageLoader.shared.image(for: asset, targetSize: CGSize(width: side, height: side))
            }
    }
}

/// Cover photo for a trip in the list.
struct TripCover: View {
    let trip: Trip
    @State private var asset: PHAsset?

    var body: some View {
        Group {
            if let asset {
                AssetThumbnail(asset: asset, pointSize: 64)
            } else {
                Rectangle().fill(Color(.secondarySystemFill))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: trip.id) {
            // Use a photo from the middle of the trip — usually more representative than the first.
            let id = trip.assetIdentifiers[trip.assetIdentifiers.count / 2]
            asset = ImageLoader.shared.assets(for: [id]).first
        }
    }
}

/// Full-screen, swipeable viewer for the original photos of a trip.
struct PhotoViewer: View {
    let assets: [PHAsset]
    @State var selection: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(assets.indices, id: \.self) { index in
                    AssetPage(asset: assets[index], isVisible: index == selection)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black.ignoresSafeArea())
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        if let date = assets[selection].creationDate {
                            Text(date, format: .dateTime.day().month(.wide).year()).font(.subheadline.bold())
                            Text(date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let location = assets[selection].location {
                        Link(destination: GoogleMaps.placeURL(latitude: location.coordinate.latitude,
                                                              longitude: location.coordinate.longitude)) {
                            Label("Show in Google Maps", systemImage: "mappin.and.ellipse")
                        }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Text("\(selection + 1) of \(assets.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct AssetPage: View {
    let asset: PHAsset
    let isVisible: Bool
    @State private var image: UIImage?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: asset.localIdentifier) {
            let size = CGSize(width: 2048, height: 2048)
            image = await ImageLoader.shared.image(for: asset, targetSize: size, contentMode: .aspectFit)
            if asset.mediaType == .video, let item = await ImageLoader.shared.playerItem(for: asset) {
                player = AVPlayer(playerItem: item)
            }
        }
        .onChange(of: isVisible) { _, visible in
            if !visible { player?.pause() }
        }
    }
}
