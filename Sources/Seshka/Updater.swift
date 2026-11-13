import Sparkle
import SwiftUI

/// Keeps seshka up to date with Sparkle: it checks the feed named in Info.plist (SUFeedURL),
/// downloads a new version when there is one, and installs it with the user's consent.
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    @Published private(set) var canCheck = false
    /// The version that is waiting, once an update has been found or downloaded. A menu bar app has no
    /// window to put an alert on, so the popover shows a button instead of stealing focus.
    @Published private(set) var availableVersion: String?

    private var controller: SPUStandardUpdaterController!
    /// Installs the downloaded update and restarts seshka. Set once Sparkle has an update ready.
    private var installNow: (() -> Void)?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    /// Opens Sparkle's own window: release notes, download progress, install and relaunch.
    func check() {
        controller.checkForUpdates(nil)
    }

    /// Installs the waiting update and restarts, or opens Sparkle's window if nothing is downloaded yet.
    func applyUpdate() {
        if let installNow {
            installNow()
        } else {
            check()
        }
    }

    // MARK: - SPUUpdaterDelegate

    /// Updates download quietly in the background. Sparkle calls this once one is ready and would then
    /// say nothing until seshka quits, which a menu bar app rarely does. Taking it over lets the popover
    /// show that a new version is waiting and install it on a click. It still installs on quit either way.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installNow = immediateInstallHandler
        availableVersion = item.displayVersionString
        return true
    }

    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    // MARK: - SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows its alert itself only when the user is already looking at seshka.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate {
            availableVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
