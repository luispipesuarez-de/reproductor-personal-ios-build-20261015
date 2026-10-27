import AVFoundation
import Combine

enum PlaybackState: Equatable {
    case idle
    case loading(Video)
    case playing(Video)
    case paused(Video)
    case failed(video: Video?, message: String)

    var video: Video? {
        switch self {
        case .loading(let video), .playing(let video), .paused(let video): return video
        case .failed(let video, _): return video
        case .idle: return nil
        }
    }
    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
}

enum RadioStatus: Equatable {
    case idle, loading, exhausted
    case failed(String)
}

@MainActor
final class PlaybackController: ObservableObject {
    let player: AVQueuePlayer
    @Published private(set) var state: PlaybackState = .idle {
        didSet { updateMediaInfo(); onPlaybackChange?() }
    }
    @Published private(set) var queue = PlaybackQueue() { didSet { onPlaybackChange?() } }
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double?
    // ponytail: one app session owns persistence; use a publisher only for multiple owners.
    var onPlaybackChange: (() -> Void)?
    @Published private(set) var autoplayEnabled = true { didSet { onPlaybackChange?() } }
    @Published private(set) var radioSeed: RecommendationSeed? { didSet { onPlaybackChange?() } }
    @Published private(set) var radioStatus: RadioStatus = .idle
    private let source: any YouTubeProviding
    private let dislikedIDs: () -> Set<String>
    private let resourceCache: PlaybackResourceCache
    private let radio: RadioSession
    private var refillTask: Task<Void, Never>?
    private var radioGeneration = UUID()
    private var radioStartPending = false
    private var automaticFailures = 0
    private var allowsAutomaticFailureSkip = false
    private var requestID = UUID()
    private var navigationID = UUID()
    private var activeEntryID: UUID?
    private var activeResource: PlaybackResource?
    private var wantsPlayback = false
    private var resumeAfterInterruption = false
    private var isStartingItem = false
    private var isInterrupted = false
    private var nativeEndCandidateEntryID: UUID?
    private var recoveredEntries: Set<UUID> = []
    private var recoveringEntryID: UUID?
    private var timeObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var periodicObserver: Any?
    private var itemNotifications: [NSObjectProtocol] = []
    private var audioNotifications: [NSObjectProtocol] = []
    private var mediaControls: SystemMediaControls?
    private var prefetchTask: Task<Void, Never>?
    private var prefetchID = UUID()
    private var prepared: PreparedEntry?

    private enum PreparedEntry {
        case ready(UUID, PlaybackResource, AVPlayerItem)
        case failed(UUID, Error)
        var id: UUID {
            switch self { case .ready(let id, _, _), .failed(let id, _): return id }
        }
    }

    init(source: any YouTubeProviding, player: AVQueuePlayer = AVQueuePlayer(), dislikedIDs: @escaping () -> Set<String> = { [] }) {
        self.source = source
        self.dislikedIDs = dislikedIDs
        self.resourceCache = PlaybackResourceCache()
        self.radio = RadioSession(source: source)
        self.player = player
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        timeObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateNativeState() }
        }
        periodicObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateProgress() }
        }
        audioNotifications = AudioSessionController.observe(controller: self)
        mediaControls = SystemMediaControls(controller: self)
    }

    deinit {
        prefetchTask?.cancel()
        refillTask?.cancel()
        if let periodicObserver { player.removeTimeObserver(periodicObserver) }
        for token in itemNotifications + audioNotifications { NotificationCenter.default.removeObserver(token) }
    }

    func play(_ video: Video) async {
        allowsAutomaticFailureSkip = false
        navigationID = UUID()
        if case .loading(let current) = state, current.id == video.id { return }
        await play([video])
    }

    func play(_ videos: [Video], startingAt index: Int = 0) async {
        resetRadio(seed: videos.last.map { .video($0.id) })
        clearNativeItems()
        queue = PlaybackQueue(entries: videos.map { QueueEntry(video: $0) }, currentIndex: index)
        recoveredEntries.removeAll()
        elapsed = 0
        guard queue.current != nil else { state = .idle; return }
        await startCurrent(progress: 0)
    }

    func startRadio(from video: Video) async {
        autoplayEnabled = true
        await play([video])
    }

    func startRadio(genre: String) async {
        let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        autoplayEnabled = true
        resetRadio(seed: .genre(trimmed), starting: true)
        let previousNext = nextEntry?.id
        queue.removeUpcomingAutomatic()
        refreshPreparedNext(previousID: previousNext)
        requestRadioRefill(replacingQueue: true)
        if let refillTask { await refillTask.value }
    }

    func setAutoplayEnabled(_ enabled: Bool) {
        guard enabled != autoplayEnabled else { return }
        autoplayEnabled = enabled
        let seed = radioSeed ?? queue.entries.last.map { .video($0.video.id) }
        resetRadio(seed: seed)
        if enabled { requestRadioRefill() }
        else {
            let previousNext = nextEntry?.id
            queue.removeUpcomingAutomatic()
            refreshPreparedNext(previousID: previousNext)
        }
    }

    func retryRadio() async {
        guard autoplayEnabled, let seed = radioSeed else { return }
        let starting = radioStartPending
        resetRadio(seed: seed, starting: starting)
        requestRadioRefill(replacingQueue: starting)
        if let refillTask { await refillTask.value }
    }

    func pause() {
        requestID = UUID()
        wantsPlayback = false
        resumeAfterInterruption = false
        isStartingItem = false
        nativeEndCandidateEntryID = nil
        player.pause()
        updateProgress()
        guard let video = queue.current?.video else { return }
        if case .failed = state { return }
        state = .paused(video)
    }

    func dismissPausedPlayback() {
        guard case .paused = state else { return }
        navigationID = UUID()
        clearNativeItems()
        resetRadio(seed: nil)
        queue = PlaybackQueue()
        recoveredEntries.removeAll()
        recoveringEntryID = nil
        allowsAutomaticFailureSkip = false
        isInterrupted = false
        elapsed = 0
        state = .idle
    }

    func resume(allowAutomaticSkip: Bool = false) async {
        guard let entry = queue.current else { return }
        allowsAutomaticFailureSkip = allowAutomaticSkip
        if radioSeed == nil {
            let lastManual = queue.entries.last(where: { !$0.isAutomatic }) ?? entry
            resetRadio(seed: .video(lastManual.video.id))
        }
        if isFailed { automaticFailures = 0 }
        if isFailed || activeEntryID != entry.id || player.currentItem == nil || player.currentItem?.status == .failed || isExpired(activeResource) {
            recoveredEntries.remove(entry.id) // Explicit user retry has its own bounded recovery.
            clearNativeItems()
            await startCurrent(progress: elapsed, allowAutomaticSkip: allowAutomaticSkip)
            return
        }
        let currentRequest = UUID()
        requestID = currentRequest
        wantsPlayback = true
        isStartingItem = true
        nativeEndCandidateEntryID = nil
        do {
            try AudioSessionController.configure()
            if let item = player.currentItem, item.duration.seconds.isFinite,
               item.duration.seconds > 0, player.currentTime().seconds >= item.duration.seconds - 0.05 {
                await nativeSeek(0)
            }
            guard requestID == currentRequest, !Task.isCancelled else { return }
            isStartingItem = false
            state = .loading(entry.video)
            player.play()
            prepareNext()
            requestRadioRefill()
        } catch { fail(error) }
    }

    func enqueue(_ video: Video) {
        let hadSelection = queue.current != nil
        let previousNext = nextEntry?.id
        queue.append(video)
        if !hadSelection, let selected = queue.current?.video { state = .paused(selected) }
        refreshPreparedNext(previousID: previousNext)
    }

    func removeQueueEntry(id: UUID) async {
        guard queue.entries.contains(where: { $0.id == id }) else { return }
        let removedCurrent = queue.current?.id == id
        queue.remove(id: id)
        recoveredEntries.remove(id)
        if removedCurrent {
            clearNativeItems()
            elapsed = 0
            if queue.entries.isEmpty { resetRadio(seed: nil) }
            state = queue.current.map { .paused($0.video) } ?? .idle
        } else {
            discardPrepared()
            prepareNext()
        }
    }

    func next() async {
        let selected = queue.current?.id
        let transport = requestID
        let navigation = navigationID
        if queue.upcomingCount == 0 {
            requestRadioRefill()
            if let refillTask { await refillTask.value }
            guard queue.current?.id == selected, requestID == transport,
                  navigationID == navigation, !Task.isCancelled else { return }
        }
        guard queue.next() != nil else { pause(); return }
        trimPast()
        await startCurrent(progress: 0, usePrepared: true, allowAutomaticSkip: true)
    }

    func playQueueEntry(id: UUID) async {
        guard queue.entries.contains(where: { $0.id == id }) else { return }
        allowsAutomaticFailureSkip = false
        navigationID = UUID()
        if case .loading = state, queue.current?.id == id { return }
        queue.select(id: id)
        trimPast()
        await startCurrent(progress: 0, usePrepared: true)
    }

    func previous() async {
        guard queue.previous() != nil else { seek(to: 0); return }
        await startCurrent(progress: 0)
    }

    func shuffleUpcoming() {
        discardPrepared()
        queue.shuffleUpcoming()
        prepareNext()
    }

    func seek(to seconds: Double) {
        navigationID = UUID()
        allowsAutomaticFailureSkip = false
        let normalized = seconds.isFinite ? max(0, seconds) : 0
        let target = duration.map { min($0, normalized) } ?? normalized
        elapsed = target
        if player.currentItem != nil {
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        updateMediaInfo()
        onPlaybackChange?()
    }

    func snapshot() -> QueueSnapshot {
        let native = player.currentTime().seconds
        let ownsNativeProgress = activeEntryID == queue.current?.id && player.currentItem != nil
        return QueueSnapshot(entries: queue.entries, currentIndex: queue.currentIndex,
                             progressSeconds: ownsNativeProgress && native.isFinite ? native : elapsed,
                             autoplayEnabled: autoplayEnabled, radioSeed: radioSeed)
    }

    func restore(_ snapshot: QueueSnapshot) {
        clearNativeItems()
        allowsAutomaticFailureSkip = false
        autoplayEnabled = snapshot.autoplayEnabled
        resetRadio(seed: snapshot.radioSeed)
        queue = PlaybackQueue(entries: snapshot.entries, currentIndex: snapshot.currentIndex)
        elapsed = snapshot.progressSeconds.isFinite ? max(0, snapshot.progressSeconds) : 0
        if queue.current == nil { elapsed = 0 }
        recoveredEntries.removeAll()
        state = queue.current.map { .paused($0.video) } ?? .idle
    }

    func handlePlaybackFailure(entryID: UUID, progressSeconds: Double) async {
        guard queue.current?.id == entryID, recoveringEntryID != entryID else { return }
        guard isExpired(activeResource), !recoveredEntries.contains(entryID) else {
            await handleCurrentFailure(AppError.unavailable)
            return
        }
        recoveredEntries.insert(entryID)
        recoveringEntryID = entryID
        let shouldPlay = wantsPlayback
        await startCurrent(progress: progressSeconds, autoplay: shouldPlay,
                           allowAutomaticSkip: allowsAutomaticFailureSkip)
        if recoveringEntryID == entryID { recoveringEntryID = nil }
    }

    func handleInterruption(ended: Bool, shouldResume: Bool) {
        if !ended {
            resumeAfterInterruption = wantsPlayback
            isInterrupted = true
            isStartingItem = false
            nativeEndCandidateEntryID = nil
            requestID = UUID()
            player.pause()
            updateProgress()
            if let video = queue.current?.video, !isFailed { state = .paused(video) }
        } else {
            let resume = shouldResume && resumeAfterInterruption && wantsPlayback
            resumeAfterInterruption = false
            isInterrupted = false
            if resume {
                // Preserve intention while the interruption's pause observation is queued.
                isStartingItem = true
                let interruptionRequest = requestID
                Task { [weak self] in
                    guard let self, self.wantsPlayback, self.requestID == interruptionRequest else { return }
                    await self.resume(allowAutomaticSkip: self.allowsAutomaticFailureSkip)
                }
            }
            else { wantsPlayback = false }
        }
    }

    func handleHeadphonesDisconnected() { pause() }

    private var isFailed: Bool { if case .failed = state { return true }; return false }
    private var nextEntry: QueueEntry? {
        guard let index = queue.currentIndex, queue.entries.indices.contains(index + 1) else { return nil }
        return queue.entries[index + 1]
    }

    private func resetRadio(seed: RecommendationSeed?, starting: Bool = false) {
        radioGeneration = UUID()
        refillTask?.cancel()
        refillTask = nil
        radio.reset(seed: autoplayEnabled ? seed : nil)
        radioSeed = seed
        radioStartPending = starting
        automaticFailures = 0
        radioStatus = .idle
    }

    private func requestRadioRefill(replacingQueue: Bool = false) {
        guard autoplayEnabled, radioSeed != nil, refillTask == nil,
              replacingQueue || queue.upcomingCount <= 2, radioStatus != .exhausted else { return }
        if case .failed = radioStatus { return }
        guard radio.hasMore else {
            if queue.upcomingCount == 0 { radioStatus = .exhausted }
            return
        }
        let generation = radioGeneration
        let selection = queue.current?.id
        let transport = requestID
        let navigation = navigationID
        let originalEntryIDs = Set(queue.entries.map(\.id))
        let disliked = dislikedIDs()
        let excluded = Set(queue.entries.map(\.video.id)).union(disliked)
        radioStatus = .loading
        refillTask = Task { [weak self, radio] in
            let result: Result<[Video], Error>
            do { result = .success(try await radio.batch(excluding: excluded, dislikedIDs: disliked, limit: 10)) }
            catch { result = .failure(error) }
            guard let self, !Task.isCancelled, self.radioGeneration == generation else { return }
            // A startup failure can call next(); it must never await this same task.
            self.refillTask = nil
            switch result {
            case .failure(let error): self.radioStatus = .failed(AppError.classify(error).localizedDescription)
            case .success(let candidates):
                let currentIDs = Set(self.queue.entries.map(\.video.id))
                let fresh = candidates.filter { !currentIDs.contains($0.id) }
                guard !fresh.isEmpty else {
                    self.radioStatus = !candidates.isEmpty && radio.hasMore ? .idle : .exhausted
                    return
                }
                self.radioStatus = .idle
                self.radioStartPending = false
                if replacingQueue, self.queue.current?.id == selection, self.requestID == transport,
                   self.navigationID == navigation {
                    let manual = self.queue.entries.filter { !$0.isAutomatic && !originalEntryIDs.contains($0.id) }
                    let automatic = fresh.map { QueueEntry(video: $0, isAutomatic: true) }
                    self.clearNativeItems()
                    self.queue = PlaybackQueue(entries: [automatic[0]] + manual + Array(automatic.dropFirst()), currentIndex: 0)
                    self.recoveredEntries.removeAll()
                    self.elapsed = 0
                    await self.startCurrent(progress: 0, allowAutomaticSkip: true)
                } else {
                    let hadSelection = self.queue.current != nil
                    let previousNext = self.nextEntry?.id
                    self.queue.appendAutomatic(fresh)
                    if !hadSelection, let entry = self.queue.current { self.state = .paused(entry.video) }
                    self.refreshPreparedNext(previousID: previousNext)
                }
            }
        }
    }

    private func refreshPreparedNext(previousID: UUID?) {
        guard previousID != nextEntry?.id else { return }
        discardPrepared()
        prepareNext()
    }

    private func trimPast() {
        queue.trimPast(keeping: 50)
        recoveredEntries.formIntersection(Set(queue.entries.map(\.id)))
    }

    private func handleCurrentFailure(_ error: Error) async {
        let shouldContinue = wantsPlayback && !isInterrupted
        fail(error)
        guard shouldContinue, autoplayEnabled, allowsAutomaticFailureSkip,
              queue.current?.isAutomatic == true else { return }
        automaticFailures += 1
        if automaticFailures < 3 { await next() }
    }

    private func startCurrent(progress: Double, autoplay: Bool = true, usePrepared: Bool = false,
                              allowAutomaticSkip: Bool = false) async {
        guard let entry = queue.current else { return }
        allowsAutomaticFailureSkip = allowAutomaticSkip
        let cached = usePrepared && prepared?.id == entry.id ? prepared : nil
        // Keep a prepared native item long enough to advance the same AVQueuePlayer.
        prefetchTask?.cancel()
        prefetchID = UUID()
        prefetchTask = nil
        prepared = nil
        removeItemObservers()
        requestID = UUID()
        let currentRequest = requestID
        activeEntryID = nil
        activeResource = nil
        wantsPlayback = autoplay
        isStartingItem = true
        nativeEndCandidateEntryID = nil
        player.pause()
        elapsed = progress.isFinite ? max(0, progress) : 0
        duration = nil
        state = .loading(entry.video)
        do {
            let resource: PlaybackResource
            let item: AVPlayerItem
            if case .ready(_, let resolved, let prefetchedItem)? = cached, !isExpired(resolved), player.items().contains(where: { $0 === prefetchedItem }) {
                resource = resolved
                item = prefetchedItem
                player.advanceToNextItem()
            } else {
                player.removeAllItems()
                if case .failed(_, let error)? = cached { throw error }
                resource = try await resourceCache.resolve(videoID: entry.video.id, source: source)
                guard requestID == currentRequest, queue.current?.id == entry.id else { return }
                guard !Task.isCancelled else { pause(); return }
                item = AVPlayerItem(url: resource.url)
                player.insert(item, after: nil)
            }
            guard requestID == currentRequest, queue.current?.id == entry.id else { return }
            activeEntryID = entry.id
            activeResource = resource
            observe(item: item, entryID: entry.id)
            try AudioSessionController.configure()
            if elapsed > 0 { await nativeSeek(elapsed) }
            guard requestID == currentRequest, !Task.isCancelled else { return }
            isStartingItem = false
            if autoplay { player.play() }
            else { state = .paused(entry.video) }
            prepareNext()
            requestRadioRefill()
        } catch {
            guard requestID == currentRequest else { return }
            guard !Task.isCancelled else { pause(); return }
            await handleCurrentFailure(error)
        }
    }

    private func prepareNext() {
        guard let entry = nextEntry, let currentID = queue.current?.id,
              let currentItem = player.currentItem, activeEntryID == currentID else { return }
        if prepared?.id == entry.id { return }
        discardPrepared()
        let token = prefetchID
        prefetchTask = Task { [weak self] in
            let result: Result<PlaybackResource, Error>
            guard let self else { return }
            do { result = .success(try await self.resourceCache.resolve(videoID: entry.video.id, source: self.source)) }
            catch { result = .failure(error) }
            guard !Task.isCancelled, self.prefetchID == token,
                  self.queue.current?.id == currentID, self.nextEntry?.id == entry.id,
                  self.player.currentItem === currentItem else { return }
            switch result {
            case .success(let resource):
                let item = AVPlayerItem(url: resource.url)
                self.prepared = .ready(entry.id, resource, item)
                self.player.insert(item, after: currentItem)
            case .failure(let error): self.prepared = .failed(entry.id, error)
            }
        }
    }

    private func discardPrepared() {
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchID = UUID()
        if case .ready(_, _, let item)? = prepared, player.currentItem !== item { player.remove(item) }
        prepared = nil
    }

    private func clearNativeItems() {
        requestID = UUID()
        wantsPlayback = false
        resumeAfterInterruption = false
        isStartingItem = false
        nativeEndCandidateEntryID = nil
        activeEntryID = nil
        activeResource = nil
        discardPrepared()
        removeItemObservers()
        player.pause()
        player.removeAllItems()
        duration = nil
    }

    private func observe(item: AVPlayerItem, entryID: UUID) {
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor [weak self, weak observed] in
                guard let self, let observed, self.player.currentItem === observed else { return }
                self.updateNativeState()
            }
        }
        let center = NotificationCenter.default
        itemNotifications = [
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self, weak item] in
                    guard let self, self.player.currentItem === item, self.queue.current?.id == entryID else { return }
                    self.updateProgress()
                    // AVPlayer may report paused before delivering its natural-end notification.
                    let shouldAdvance = self.wantsPlayback || self.nativeEndCandidateEntryID == entryID
                    self.nativeEndCandidateEntryID = nil
                    if shouldAdvance { await self.next() }
                }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self, weak item] in
                    guard let self, self.player.currentItem === item else { return }
                    await self.handlePlaybackFailure(entryID: entryID, progressSeconds: self.elapsed)
                }
            }
        ]
    }

    private func removeItemObservers() {
        itemObservation = nil
        for token in itemNotifications { NotificationCenter.default.removeObserver(token) }
        itemNotifications.removeAll()
    }

    private func nativeSeek(_ seconds: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in continuation.resume() }
        }
        updateProgress()
    }

    private func updateNativeState() {
        guard let entry = queue.current, activeEntryID == entry.id, let item = player.currentItem, !isFailed else { return }
        if item.status == .failed {
            Task { await handlePlaybackFailure(entryID: entry.id, progressSeconds: elapsed) }
            return
        }
        guard item.status == .readyToPlay else { return }
        updateProgress()
        if !wantsPlayback, player.timeControlStatus != .paused {
            allowsAutomaticFailureSkip = false
        }
        switch player.timeControlStatus {
        case .playing:
            wantsPlayback = true
            automaticFailures = 0
            nativeEndCandidateEntryID = nil
            state = .playing(entry.video)
        case .paused:
            if isStartingItem { return }
            if !isInterrupted {
                if wantsPlayback { nativeEndCandidateEntryID = entry.id }
                wantsPlayback = false
                resumeAfterInterruption = false
            }
            state = .paused(entry.video)
        case .waitingToPlayAtSpecifiedRate:
            wantsPlayback = true
            nativeEndCandidateEntryID = nil
            state = .loading(entry.video)
        @unknown default: break
        }
    }

    private func updateProgress() {
        guard let item = player.currentItem, activeEntryID == queue.current?.id else { return }
        let time = player.currentTime().seconds
        if time.isFinite { elapsed = max(0, time) }
        let total = item.duration.seconds
        duration = total.isFinite && total > 0 ? total : nil
        updateMediaInfo()
    }

    private func updateMediaInfo() {
        mediaControls?.update(video: state.video, elapsed: elapsed, duration: duration, isPlaying: state.isPlaying)
    }

    private func isExpired(_ resource: PlaybackResource?) -> Bool {
        resource?.expiresAt.map { $0 <= Date() } ?? false
    }

    private func fail(_ error: Error) {
        wantsPlayback = false
        isStartingItem = false
        nativeEndCandidateEntryID = nil
        player.pause()
        updateProgress()
        state = .failed(video: queue.current?.video, message: AppError.classify(error).localizedDescription)
    }
}
