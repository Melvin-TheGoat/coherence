import Foundation

/// The seam between 808 and a Garmin watch.
///
/// Everything above this protocol (`GarminBatch`, `GarminStream`, the engine,
/// the score) is plain Swift and is tested without a watch, a phone or the
/// Connect IQ framework. Everything below it is Garmin's SDK. The Friends work
/// set the precedent with `MemoryCommunityDatabase`, and it paid for itself:
/// the real CloudKit semantics that the fake did not model are exactly where
/// the bugs were, so the fake is for building, never for certifying.
protocol GarminLink: AnyObject {
    /// Watches this phone has been given access to. Empty until the user has
    /// picked one, which is a trip through the Garmin Connect app.
    var devices: [GarminDevice] { get }
    /// Ask Garmin Connect for the device list. It leaves 808, the user picks,
    /// and Garmin Connect reopens 808 through its URL scheme with the answer.
    func chooseDevice()
    /// Handle that return trip.
    func absorbDeviceSelection(from url: URL) -> Bool
    /// Start listening to the 808 watch app on `device`.
    func listen(to device: GarminDevice, onMessage: @escaping ([AnyHashable: Any]) -> Void)
    func stopListening()
}

struct GarminDevice: Equatable, Identifiable {
    let id: String          // the SDK's device identifier
    let name: String        // "fenix 7", as the user knows it
    var isConnected: Bool
}

/// A watch that exists only in memory, for tests, previews and building the
/// screens before the framework is linked. It replays batches on demand.
final class MemoryGarminLink: GarminLink {

    private(set) var devices: [GarminDevice]
    private var handler: (([AnyHashable: Any]) -> Void)?
    private(set) var listening = false
    private(set) var chooseDeviceCalls = 0

    init(devices: [GarminDevice] = [GarminDevice(id: "sim", name: "vivoactive 5", isConnected: true)]) {
        self.devices = devices
    }

    func chooseDevice() { chooseDeviceCalls += 1 }

    func absorbDeviceSelection(from url: URL) -> Bool { true }

    func listen(to device: GarminDevice, onMessage: @escaping ([AnyHashable: Any]) -> Void) {
        handler = onMessage
        listening = true
    }

    func stopListening() {
        handler = nil
        listening = false
    }

    /// Push a message as though the watch had sent it.
    func deliver(_ message: [AnyHashable: Any]) { handler?(message) }
}

// MARK: - The real link, not yet built
//
// `ConnectIQGarminLink` goes here, and it is deliberately NOT written yet
// because linking the framework changes things App Review looks at, and none
// of it can be undone quietly. What it takes, in order:
//
// 1. `project.yml`: add the package
//        ConnectIQ:
//          url: https://github.com/garmin/connectiq-companion-app-sdk-ios
//          from: <current>
//    and list it in the Coherence target's dependencies, then `xcodegen
//    generate`. NOTE: Aziz's `project.yml` is skip-worktree and carries his
//    personal team and bundle ids, so the package edit must be committed
//    through the index without his signing values riding along.
// 2. Info.plist: a URL type of our own (the SDK calls back through it),
//    `gcm-ciq` in `LSApplicationQueriesSchemes`, and
//    `NSBluetoothAlwaysUsageDescription` written about what it is for. The
//    SDK also REQUIRES `CFBundleDisplayName` or device selection fails with
//    no error at all.
// 3. Background mode `bluetooth-central`, so a batch that arrives while the
//    screen is off still lands.
// 4. `-ObjC` in Other Linker Flags.
// 5. The app UUID from the Connect IQ store listing, to address the watch app.
//
// Items 2 and 3 change the Info.plist and the entitlements, which means the
// build carrying them RE-ENTERS Beta App Review and needs the privacy policy
// paragraph and the App Privacy answers moved in the same pass. That belongs
// on RELEASE_CHECKLIST.md the day it is done, not after (the CloudKit
// promotion taught this the expensive way).
//
// The adapter itself is small: `initializeWithUrlScheme`, keep the devices
// from `parseDeviceSelectionResponseFromURL`, `registerForAppMessages`, and
// hand each message straight to the closure. Everything interesting already
// lives above this line and is already under test.
