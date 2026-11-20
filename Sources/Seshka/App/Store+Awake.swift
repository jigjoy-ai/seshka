import Foundation

/// Where staying awake stands.
enum Awake: Equatable {
    /// The switch is off.
    case off
    /// On, and nothing is working: the Mac sleeps as it always does.
    case waiting
    /// Sleep is switched off, for this many working sessions. Zero in the minutes after the last one finished.
    case holding(Int)
    /// Sessions are working, but the Mac is left to sleep, and why.
    case paused(String)
}

/// Keeps the Mac awake, lid closed or not, while a Claude Code session is working, and lets it sleep
/// again when the last one is done. `Lid` does the switching; this decides when.
extension Store {
    /// A session that finished may carry on a moment later. Sleep stays off this long after the last
    /// one stopped working, so the Mac does not drop off between two steps.
    static let awakeLinger: TimeInterval = 60

    /// True while it is seshka that switched sleep off. Kept between runs, so a copy that was killed
    /// with sleep off puts it back the next time it starts.
    private var holdsSleep: Bool {
        get { UserDefaults.standard.bool(forKey: "holdsSleep") }
        set { UserDefaults.standard.set(newValue, forKey: "holdsSleep") }
    }

    /// The switch. Turning it on the first time asks for the password that adds seshka's rule to sudo.
    func setStaysAwake(_ on: Bool) {
        awakeFailure = nil
        if on, !Lid.isAllowed {
            switch Lid.allow() {
            case .done: break
            case .cancelled: return
            case .failed(let why):
                awakeFailure = why
                return
            }
        }
        staysAwake = on
        updateAwake()
    }

    /// Removes the rule from sudo. The switch goes off first, so sleep is never left disabled behind it.
    func forgetAwakePermission() {
        setStaysAwake(false)
        if case .failed(let why) = Lid.forbid() { awakeFailure = why }
        objectWillChange.send()
    }

    /// Looks at the sessions, the battery and the heat, and switches sleep off or back on to match.
    /// Called after every scan, and every few seconds while the switch is on.
    func updateAwake(now: Date = Date()) {
        guard !awakeFrozen else { return }
        watchAwake()
        let working = sessions.filter { $0.status == .busy }.count
        if working > 0 { lastWorking = now }
        let lingering = lastWorking.map { now.timeIntervalSince($0) < Store.awakeLinger } ?? false

        var pause: String?
        if let battery = Lid.battery, battery.unplugged, battery.percent < awakeBatteryFloor {
            pause = "the battery is below \(awakeBatteryFloor)%"
        } else if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            pause = "the Mac is running hot"
        }

        guard staysAwake, working > 0 || lingering, pause == nil else {
            releaseSleep(sleeping: true)
            awake = !staysAwake ? .off : (working > 0 ? .paused(pause ?? "") : .waiting)
            return
        }
        // Sleep that is already off without seshka's doing was switched by something else, and is left alone.
        if !Lid.sleepDisabled {
            if let failure = Lid.setSleepDisabled(true) {
                awakeFailure = failure
                awake = .paused("macOS did not allow it")
                return
            }
            holdsSleep = true
            awakeFailure = nil
        }
        if awakeActivity == nil {
            awakeActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                                  reason: "Keeping the Mac awake while Claude Code works")
        }
        let closed = Lid.isClosed
        if closed, !lidWasClosed { Lid.turnDisplayOff() }
        lidWasClosed = closed
        awake = .holding(working)
    }

    /// Switches sleep back on if seshka switched it off. With `sleeping`, a Mac whose lid is closed is
    /// then put to sleep: it would have been asleep all along, had seshka not kept it up.
    func releaseSleep(sleeping: Bool) {
        guard !awakeFrozen else { return }
        if let activity = awakeActivity {
            ProcessInfo.processInfo.endActivity(activity)
            awakeActivity = nil
        }
        lidWasClosed = false
        guard holdsSleep else { return }
        if Lid.sleepDisabled, let failure = Lid.setSleepDisabled(false) {
            // Still held. The next look tries again.
            awakeFailure = failure
            return
        }
        holdsSleep = false
        if sleeping, Lid.isClosed { Lid.sleepNow() }
    }

    /// A scan may be minutes apart. While the switch is on, the lid, the battery and the heat are
    /// looked at more often than that, and while the Mac is held awake so are the sessions: it should
    /// not stay up minutes after the last one finished.
    private func watchAwake() {
        if staysAwake, awakeTimer == nil {
            awakeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if case .holding = self.awake { self.refresh() } else { self.updateAwake() }
                }
            }
        } else if !staysAwake, let timer = awakeTimer {
            timer.invalidate()
            awakeTimer = nil
        }
    }
}
