import AVFoundation

enum AudioSessionController {
    static func configure() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback)
        try session.setActive(true)
    }

    @MainActor
    static func observe(controller: PlaybackController) -> [NSObjectProtocol] {
        let center = NotificationCenter.default
        return [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak controller] notification in
                guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
                let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                Task { @MainActor [weak controller] in
                    controller?.handleInterruption(ended: type == .ended, shouldResume: options.contains(.shouldResume))
                }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak controller] notification in
                guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                Task { @MainActor [weak controller] in controller?.handleHeadphonesDisconnected() }
            }
        ]
    }
}
