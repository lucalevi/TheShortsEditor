import AVFoundation
import EditorCore
import Observation

/// The player and everything about playing: the playhead, play/pause, J/K/L shuttle, stepping,
/// playing a stretch (once or looping), and skimming the timeline (the viewer shows the moment
/// under the pointer while the playhead stays put).
///
/// It knows nothing about the project: `EditorModel` gives it each rebuilt player item with
/// `show(_:duration:)`, and hears about every playhead move through `onPlayheadMove` (to stop a
/// voice-over at the end, or jump over pauses being previewed).
@Observable
final class PlaybackController {
    let player = AVPlayer()
    /// Where the playhead is, on whole frames.
    private(set) var currentTime: CMTime = .zero
    private(set) var isPlaying = false
    /// The length of what the player shows (the Short's length), set as soon as it changes.
    var duration: CMTime = .zero {
        // A shorter Short (clips deleted while the pointer was over the timeline) mustn't keep
        // showing a moment past its end.
        didSet { if let skim = skimTime, skim >= duration { skimTime = nil } }
    }
    /// Playing starts again from the beginning (or the stretch being played) at the end (⌘L).
    var loopsPlayback = AppEnvironment.defaults.bool(forKey: SettingsKey.loopPlayback) {
        didSet { AppEnvironment.defaults.set(loopsPlayback, forKey: SettingsKey.loopPlayback) }
    }
    /// Playing only this stretch (/), stopping or looping at its end.
    @ObservationIgnored private(set) var playRange: CMTimeRange?
    /// Hovering over the timeline shows that moment in the viewer (iMovie's skimming).
    var skimsTimeline = AppEnvironment.defaults.object(forKey: SettingsKey.skimming) as? Bool ?? true {
        didSet {
            AppEnvironment.defaults.set(skimsTimeline, forKey: SettingsKey.skimming)
            if !skimsTimeline { skim(to: nil) }
        }
    }
    /// Skimming also plays a moment of sound (⇧S).
    var skimsAudio = AppEnvironment.defaults.bool(forKey: SettingsKey.audioSkimming) {
        didSet { AppEnvironment.defaults.set(skimsAudio, forKey: SettingsKey.audioSkimming) }
    }
    /// Where the pointer is skimming on the timeline (the white line), nil when it isn't.
    private(set) var skimTime: CMTime?
    /// Set while skimming must not happen (counting down to a voice-over).
    @ObservationIgnored var blocksSkimming = false
    /// Called on the main actor whenever the playhead moves while playing or seeking.
    @ObservationIgnored var onPlayheadMove: ((CMTime) -> Void)?

    @ObservationIgnored private var chaseTarget: CMTime?
    @ObservationIgnored private var isChasing = false
    /// A moment of sound playing while skimming: the player runs, but nothing should react.
    @ObservationIgnored private var isSkimBlip = false
    @ObservationIgnored private var skimBlipTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    /// Seeks asked for and not yet landed. Meanwhile the player still reports where it was (e.g.
    /// 0 for an item just swapped in after an edit), which must not move the playhead back.
    @ObservationIgnored private var seeksUnderWay = 0
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init() {
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: .oneFrame, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.playheadMoved(to: time) }
        }
        statusObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                guard let self, !self.isSkimBlip else { return }
                self.isPlaying = playing
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) {
            [weak self] note in
            let item = note.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, item === self.player.currentItem else { return }
                self.reachedEnd()
            }
        }
    }

    // MARK: What is shown

    /// Shows a newly built item (nil: nothing to play), keeping the playhead where it was.
    func show(_ item: AVPlayerItem?, duration: CMTime) {
        self.duration = item == nil ? .zero : duration
        player.replaceCurrentItem(with: item)
        seek(to: item == nil ? .zero : min(currentTime, duration))
        // While skimming, the viewer keeps showing the skimmed moment (the title boxes over it
        // are placed for that moment too).
        if item != nil, let skim = skimTime { chaseSeek(to: skim.clamped(.zero, max(.zero, duration - .oneFrame))) }
    }

    /// Back to the start with nothing playing (another Short is opened).
    func reset() {
        player.pause()
        playRange = nil
        skimTime = nil
        currentTime = .zero
    }

    // MARK: Playing

    func play() { player.play() }

    /// Pauses, and forgets any stretch being played.
    func pause() {
        player.pause()
        playRange = nil
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else if let skim = skimTime {
            // Space while skimming plays from the skimmer, as in iMovie.
            skimTime = nil
            seek(to: skim)
            player.play()
        } else {
            if currentTime >= duration - .oneFrame { seek(to: .zero) }
            player.play()
        }
    }

    /// Plays `range`, then stops at its end (or plays it again, with loop on).
    func play(_ range: CMTimeRange) {
        skimTime = nil
        seek(to: range.start)
        playRange = range
        player.play()
    }

    /// \: plays from the start of the Short.
    func playFromStart() {
        skimTime = nil
        playRange = nil
        seek(to: .zero)
        player.play()
    }

    /// J/K/L shuttle: each press of L (or J) doubles the speed forwards (or backwards).
    func shuttle(forward: Bool) {
        let rate = player.rate
        if forward {
            player.rate = rate > 0 ? min(rate * 2, 8) : 1
        } else {
            player.rate = rate < 0 ? max(rate * 2, -8) : -1
        }
    }

    func step(frames: Int) {
        player.pause()
        seek(to: currentTime + CMTime(value: Int64(frames), timescale: Project.frameRate))
    }

    /// Moves the playhead to `time` (on a whole frame, inside the Short).
    func seek(to time: CMTime) {
        let clamped = time.snappedToFrame().clamped(.zero, duration)
        currentTime = clamped
        seeksUnderWay += 1
        player.seek(to: clamped, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.seeksUnderWay -= 1 }
        }
    }

    // MARK: Skimming

    /// The pointer is over the timeline at `time` (nil: it left). The viewer shows that moment;
    /// the playhead stays where it is. Ignored while playing.
    func skim(to time: CMTime?) {
        guard let time else {
            guard skimTime != nil else { return }
            skimTime = nil
            stopSkimBlip()
            chaseSeek(to: currentTime)
            return
        }
        guard skimsTimeline, !isPlaying || isSkimBlip, !blocksSkimming, duration > .zero else { return }
        let frame = time.snappedToFrame().clamped(.zero, max(.zero, duration - .oneFrame))
        guard frame != skimTime else { return }
        skimTime = frame
        chaseSeek(to: frame)
    }

    /// Stops skimming without moving the viewer back (something else is shown next).
    func endSkimming() {
        skimTime = nil
    }

    /// Seeks the player to `time`, dropping in-between targets while a seek is under way, so
    /// skimming stays smooth however fast the pointer moves.
    func chaseSeek(to time: CMTime) {
        chaseTarget = time
        guard !isChasing, player.currentItem != nil else { return }
        isChasing = true
        Task {
            while let target = chaseTarget {
                chaseTarget = nil
                if isSkimBlip { player.pause() }
                _ = await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            isChasing = false
            if skimsAudio, skimTime != nil { playSkimBlip() }
        }
    }

    /// A tenth of a second of sound at the skimmer.
    private func playSkimBlip() {
        skimBlipTask?.cancel()
        isSkimBlip = true
        player.rate = 1
        skimBlipTask = Task {
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }
            stopSkimBlip()
        }
    }

    private func stopSkimBlip() {
        skimBlipTask?.cancel()
        guard isSkimBlip else { return }
        player.pause()
        isSkimBlip = false
    }

    // MARK: Following the player

    private func playheadMoved(to time: CMTime) {
        // While skimming, the player shows the skimmer's moment; the playhead stays put.
        if isSkimBlip || (skimTime != nil && !isPlaying) || isChasing || seeksUnderWay > 0 { return }
        currentTime = time
        if let range = playRange, player.rate > 0, time.snappedToFrame() >= range.end {
            playRangeEnded(range)
            return
        }
        onPlayheadMove?(time)
    }

    private func reachedEnd() {
        guard loopsPlayback, playRange == nil, player.currentItem != nil else { return }
        seek(to: .zero)
        player.play()
    }

    /// Reached the end of the stretch being played: again from its start (loop), or stop there.
    private func playRangeEnded(_ range: CMTimeRange) {
        if loopsPlayback {
            seek(to: range.start)
        } else {
            player.pause()
            playRange = nil
            seek(to: range.end)
        }
    }
}
