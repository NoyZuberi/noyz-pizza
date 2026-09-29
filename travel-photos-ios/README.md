# My Travels (iPhone app)

An iPhone app that turns the photos already on your iPhone into a list of the places you travelled to.

- **Trip list.** Photos with a GPS location, taken away from home, are grouped into trips. Each trip gets a
  name ("🇮🇹 Rome · Florence"), dates, and a photo count. They are grouped by year. You can also see all trips on a map.
- **Path in Google Maps.** Open a trip to see its path: every place you took photos, in order.
  "Open trip route in Google Maps" opens the whole route in Google Maps, or in Safari if the app isn't installed.
  Tap any stop to open just that place.
- **Your original photos.** The trip page shows that trip's photos straight from your iPhone photo library,
  including iCloud photos. **Nothing is copied, moved, or put in a new album or folder.** Tap a photo to view it
  full screen and swipe through the trip. Videos play too.

## How trips are found

1. Your **home** is the place you took photos on the most different days. A previous home counts too
   if you took photos there on 60+ different days. Photos within 50 km of home are ignored.
   You can change this in ⚙️: 10 / 25 / 50 / 100 / 200 km.
2. Photos taken away from home belong to the same trip unless there's a gap of more than 3 days between them.
3. Inside a trip, photos taken more than 5 km apart are separate stops. The stops, in order, are the trip's path.
4. Place names come from Apple's geocoder. Only a photo's coordinates are sent, never the photo. Names are
   saved on the phone, so they load instantly next time.

## Install it on your iPhone

You need a Mac with **Xcode 16 or newer** (free on the Mac App Store) and your iPhone on **iOS 17 or newer**.

1. Open `travel-photos-ios/TravelPhotos.xcodeproj` in Xcode.
2. Click the **TravelPhotos** project, then **Signing & Capabilities**. Under **Team**, choose your Apple ID.
   A free Apple ID works. If Xcode says the bundle identifier is taken, change `com.noyzuberi.TravelPhotos` to something unique.
3. Connect your iPhone with a cable, pick it at the top of the Xcode window, and press **▶ Run**.
4. The first time only: on the iPhone, go to **Settings → General → VPN & Device Management**, trust your developer
   profile, and turn on **Developer Mode** if iOS asks.
5. Open **My Travels** and allow access to **All Photos**.

With a free Apple ID, the app has to be re-installed from Xcode every 7 days. A paid Apple Developer account
removes that limit.

## Files

| File | What it does |
| --- | --- |
| `TripBuilder.swift` | Detects home, groups photos into trips and stops, builds Google Maps links |
| `TravelStore.swift` | Asks for photo access, reads photo locations, looks up place names |
| `ContentView.swift` | Trip list, all-trips map, settings |
| `TripDetailView.swift` | Trip page: map of the path, Google Maps buttons, photo grid |
| `PhotoViews.swift` | Loads thumbnails and full photos from the library; full-screen viewer |
