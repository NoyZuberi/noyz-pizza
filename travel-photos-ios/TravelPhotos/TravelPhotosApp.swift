import SwiftUI

@main
struct TravelPhotosApp: App {
    @StateObject private var store = TravelStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
