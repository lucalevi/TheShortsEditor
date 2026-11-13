import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI
import UniformTypeIdentifiers

/// The rows over and under the clips: B-roll, titles, sounds, captions, music and pauses.
extension TimelineView {
    // MARK: B-roll

    /// Videos and pictures over the clips. Drag to move, drag an edge to trim, drop files here to
    /// add them at that time.
    var overlayLane: some View {
        let rows = overlayRows
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: max(contentWidth, 1), height: overlaysHeight)
                .contentShape(Rectangle())
                .gesture(emptySpaceGesture)
                .dropDestination(for: URL.self) { urls, location in
                    model.importFiles(urls, to: .overlay(at: time(at: location.x)))
                    return true
                }
                .allowsHitTesting(true)
            if model.project.overlays.isEmpty {
                Label("Drop B-roll or pictures here to show them over your clips", systemImage: "rectangle.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: overlayRowHeight)
                    .offset(x: leadingInset + 4)
                    .allowsHitTesting(false)
            }
            ForEach(model.project.overlays) { overlay in
                overlayView(overlay, row: rows[overlay.id] ?? 0)
            }
        }
    }

    func overlayView(_ overlay: Overlay, row: Int) -> some View {
        let item = TimelineItem.overlay(overlay.id)
        let (start, length) = shownRange(of: item, start: overlay.start, duration: overlay.duration)
        let asset = model.project.asset(id: overlay.clip.assetID)
        return OverlayBlock(
            overlay: overlay,
            name: asset?.name ?? "Missing",
            aspect: aspect(of: asset),
            filmstrip: model.filmstrips[overlay.clip.assetID],
            pointsPerSecond: pointsPerSecond,
            sourceStart: overlay.clip.sourceTime(atOffset: start - overlay.start),
            isSelected: model.isSelected(item),
            isAfterEnd: overlay.visibleRange(in: model.project) == nil
        )
        .overlay(alignment: .leading) {
            EdgeHandle(edge: .leading, help: "Drag to trim the start") { dx in
                updateBlockDrag(item, kind: .start, points: dx, start: overlay.start, duration: overlay.duration)
            } onEnd: { endBlockDrag() }
        }
        .overlay(alignment: .trailing) {
            EdgeHandle(edge: .trailing, help: "Drag to trim the end") { dx in
                updateBlockDrag(item, kind: .end, points: dx, start: overlay.start, duration: overlay.duration)
            } onEnd: { endBlockDrag() }
        }
        .frame(width: max(width(of: length) - 2, 6), height: overlayRowHeight)
        .offset(x: x(for: start) + 1, y: CGFloat(row) * (overlayRowHeight + rowGap))
        .zIndex(blockDrag?.item == item ? 1 : 0)
        .gesture(clickTap { _, modifiers in
            if modifiers.isDisjoint(with: [.command, .shift]) {
                model.selectOverlay(overlay.id)
            } else {
                model.click(item, modifiers: modifiers)
            }
        })
        .gesture(DragGesture(minimumDistance: 3)
            .onChanged { value in
                updateBlockDrag(item, kind: .move, points: value.translation.width, start: overlay.start, duration: overlay.duration)
            }
            .onEnded { _ in endBlockDrag() })
        .contextMenu {
            Button("Split at Playhead") {
                model.selection = item
                model.splitAtPlayhead()
            }
            Button("Start at Playhead") { model.moveOverlay(overlay.id, to: model.currentTime) }
            Button(overlay.clip.isMuted ? "Turn Sound On" : "Turn Sound Off") { model.setClipMuted(overlay.id, !overlay.clip.isMuted) }
                .disabled(asset?.hasAudio != true)
            Divider()
            settingsMenuItems(for: item, clipID: overlay.id)
            Divider()
            deleteButton(for: item, single: "Delete")
        }
    }

    // MARK: Titles

    /// The titles, above everything. Click to select, drag to move, drag the right edge to change the length.
    var titleLane: some View {
        let rows = titleRows
        return ZStack(alignment: .topLeading) {
            if model.project.titles.isEmpty, !model.project.timeline.clips.isEmpty {
                Label("Titles go here: ⌘T adds one at the playhead", systemImage: "textformat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: titleRowHeight)
                    .offset(x: leadingInset + 4)
                    .allowsHitTesting(false)
            }
            ForEach(model.project.titles) { title in
                let item = TimelineItem.title(title.id)
                let (start, length) = shownRange(of: item, start: title.start, duration: title.duration)
                let isAfterEnd = title.visibleRange(in: model.project) == nil
                TitleBlock(title: title, isSelected: model.isSelected(item), isAfterEnd: isAfterEnd) { dx in
                    updateBlockDrag(item, kind: .end, points: dx, start: title.start, duration: title.duration)
                } onResizeEnd: {
                    endBlockDrag()
                }
                .frame(width: max(width(of: length) - 2, 6), height: titleRowHeight)
                .offset(x: x(for: start) + 1, y: CGFloat(rows[title.id] ?? 0) * (titleRowHeight + 2))
                .zIndex(blockDrag?.item == item ? 1 : 0)
                .gesture(clickTap { _, modifiers in
                    if modifiers.isDisjoint(with: [.command, .shift]) {
                        model.selectTitle(title.id)
                    } else {
                        model.click(item, modifiers: modifiers)
                    }
                })
                .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                    updateBlockDrag(item, kind: .move, points: value.translation.width, start: title.start, duration: title.duration)
                }.onEnded { _ in
                    endBlockDrag()
                    if model.timelineSelection.count <= 1 { model.selectTitle(title.id) }
                })
                .contextMenu {
                    Button("Start at Playhead") { model.moveTitle(title.id, to: model.currentTime) }
                    Divider()
                    Button("Copy Title Design") {
                        if !model.isSelected(item) { model.selection = item }
                        model.copySettings()
                    }
                    Button("Paste Title Design") {
                        if !model.isSelected(item) { model.selection = item }
                        model.pasteTitleDesign()
                    }
                    .disabled(model.copiedTitle == nil)
                    Divider()
                    deleteButton(for: item, single: "Delete Title")
                }
            }
        }
    }

    // MARK: Dragging titles and B-roll

    /// Where a title or overlay is drawn: where it is, or where it is being dragged to.
    func shownRange(of item: TimelineItem, start: CMTime, duration: CMTime) -> (CMTime, CMTime) {
        guard let drag = blockDrag, drag.item == item else { return (start, duration) }
        switch drag.kind {
        case .move: return (start + drag.delta, duration)
        case .start: return (start + drag.delta, duration - drag.delta)
        case .end: return (start, duration + drag.delta)
        }
    }

    func updateBlockDrag(_ item: TimelineItem, kind: BlockDrag.Kind, points: CGFloat, start: CMTime, duration: CMTime) {
        model.pause()
        if !model.isSelected(item) { model.selection = item }
        var delta = seconds(points)
        snapLine = nil
        switch kind {
        case .move:
            let moved = max(.zero, start + delta)
            if let stuck = model.snappedStart(moved, duration: duration, excluding: item) {
                delta = stuck - start
                // Draw the line at whichever edge stuck.
                let targets = Snapping.targets(in: model.project, playhead: model.currentTime, excluding: [item])
                snapLine = targets.contains(stuck) ? stuck : stuck + duration
            }
            delta = max(delta, -start)
        case .start:
            if let stuck = model.snapped(start + delta, excluding: item) {
                delta = stuck - start
                snapLine = stuck
            }
            delta = min(max(delta, -start), duration - Clip.minimumDuration)
        case .end:
            if let stuck = model.snapped(start + duration + delta, excluding: item) {
                delta = stuck - start - duration
                snapLine = stuck
            }
            delta = max(delta, Clip.minimumDuration - duration)
        }
        blockDrag = BlockDrag(item: item, kind: kind, delta: delta.snappedToFrame())
    }

    func endBlockDrag() {
        defer {
            blockDrag = nil
            snapLine = nil
        }
        guard let drag = blockDrag, drag.delta != .zero else { return }
        switch (drag.item, drag.kind) {
        case (.title(let id), .move):
            if let title = model.project.title(id: id) { model.moveTitle(id, to: title.start + drag.delta) }
        case (.title(let id), .end):
            if let title = model.project.title(id: id) { model.setTitleDuration(id, title.duration + drag.delta) }
        case (.overlay(let id), .move):
            if let overlay = model.project.overlay(id: id) { model.moveOverlay(id, to: overlay.start + drag.delta) }
        case (.overlay(let id), .start):
            model.trimOverlay(id, edge: .start, by: drag.delta)
        case (.overlay(let id), .end):
            model.trimOverlay(id, edge: .end, by: drag.delta)
        case (.sound(let id), .move):
            if let sound = model.project.sound(id: id) { model.moveSound(id, to: sound.start + drag.delta) }
        case (.sound(let id), .start):
            model.trimSound(id, edge: .start, by: drag.delta)
        case (.sound(let id), .end):
            model.trimSound(id, edge: .end, by: drag.delta)
        default:
            break
        }
    }

    // MARK: Sound effects and voice-overs

    /// Sound effects and voice-overs, under the captions. Drop sound files here to add them.
    var soundLane: some View {
        let rows = soundRows
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: max(contentWidth, 1), height: soundsHeight)
                .contentShape(Rectangle())
                .gesture(emptySpaceGesture)
                .dropDestination(for: URL.self) { urls, location in
                    model.importFiles(urls, to: .sound(at: time(at: location.x)))
                    return true
                }
            if model.project.sounds.isEmpty, !model.project.timeline.clips.isEmpty {
                Label("Sound effects and voice-overs go here (Sounds panel, or drop a sound file)", systemImage: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: soundRowHeight)
                    .offset(x: leadingInset + 4)
                    .allowsHitTesting(false)
            }
            ForEach(model.project.sounds) { sound in
                soundView(sound, row: rows[sound.id] ?? 0)
            }
        }
    }

    func soundView(_ sound: SoundClip, row: Int) -> some View {
        let item = TimelineItem.sound(sound.id)
        let (start, length) = shownRange(of: item, start: sound.start, duration: sound.duration)
        let name = model.project.asset(id: sound.clip.assetID)?.name ?? "Missing"
        let isSelected = model.isSelected(item)
        return RoundedRectangle(cornerRadius: 4)
            .fill((sound.isVoiceOver ? Color.pink : Color.indigo).opacity(isSelected ? 0.6 : 0.4))
            .overlay(alignment: .bottom) {
                if let levels = model.audioLevels[sound.clip.assetID] {
                    WaveformView(levels: levels, sourceStart: sound.clip.sourceTime(atOffset: start - sound.start),
                                 pointsPerSecond: pointsPerSecond / CGFloat(sound.clip.averageSpeed),
                                 tooLoud: model.tooLoudRanges(of: sound.clip).map { CMTimeRange(start: $0.start - (start - sound.start), duration: $0.duration) })
                        .frame(height: soundRowHeight - 14)
                        .opacity(sound.clip.isMuted ? 0.3 : 0.8)
                }
            }
            .overlay(alignment: .topLeading) {
                Label(sound.detachedFrom != nil ? "Sound of \(name)" : name,
                      systemImage: sound.isVoiceOver ? "mic.fill" : sound.detachedFrom != nil ? "waveform.path" : "waveform")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.yellow : Color.white.opacity(0.4), lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .bottom) {
                if blockDrag?.item != item, model.audioLevels[sound.clip.assetID] != nil, width(of: length) > 16 {
                    volumeEditor(for: sound.clip, item: item)
                        .frame(height: soundRowHeight - 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .overlay(alignment: .leading) {
                EdgeHandle(edge: .leading, help: "Drag to trim the start") { dx in
                    updateBlockDrag(item, kind: .start, points: dx, start: sound.start, duration: sound.duration)
                } onEnd: { endBlockDrag() }
            }
            .overlay(alignment: .trailing) {
                EdgeHandle(edge: .trailing, help: "Drag to trim the end") { dx in
                    updateBlockDrag(item, kind: .end, points: dx, start: sound.start, duration: sound.duration)
                } onEnd: { endBlockDrag() }
            }
            .frame(width: max(width(of: length) - 2, 6), height: soundRowHeight)
            .contentShape(Rectangle())
            .offset(x: x(for: start) + 1, y: CGFloat(row) * (soundRowHeight + 2))
            .zIndex(blockDrag?.item == item ? 1 : 0)
            .gesture(clickTap { _, modifiers in
                if modifiers.isDisjoint(with: [.command, .shift]) { model.selectSound(sound.id) } else { model.click(item, modifiers: modifiers) }
            })
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { value in updateBlockDrag(item, kind: .move, points: value.translation.width, start: sound.start, duration: sound.duration) }
                .onEnded { _ in endBlockDrag() })
            .contextMenu {
                Button("Split at Playhead") {
                    model.selection = item
                    model.splitAtPlayhead()
                }
                Button("Start at Playhead") { model.moveSound(sound.id, to: model.currentTime) }
                Divider()
                deleteButton(for: item, single: "Delete")
            }
            .help("\(sound.isVoiceOver ? "Voice-over" : "Sound"): \(name). Drag to move, drag an edge to trim.")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(sound.isVoiceOver ? "Voice-over" : "Sound"): \(name)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The volume line over a clip's or sound's waveform.
    func volumeEditor(for clip: Clip, item: TimelineItem) -> some View {
        VolumeLineEditor(
            clip: clip,
            pointsPerSecond: pointsPerSecond,
            showsHandles: model.isSelected(item),
            onSelect: { model.selection = item },
            onVolume: { model.setClipVolume(clip.id, $0) },
            onAddPoint: { model.addVolumePoint(to: clip.id, atOffset: $0) },
            onPointLevel: { model.setVolumePoint($0, of: clip.id, level: $1) },
            onRemovePoint: { model.removeVolumePoint($0, of: clip.id) },
            onFade: { model.setFade($0, to: $1, for: [clip.id]) }
        )
    }

    // MARK: Captions, music, pauses

    /// The captions, under the clips they belong to. Click one to go there and fix its words; drag
    /// its left or right edge to change when it comes and goes.
    var captionLane: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.captionPages) { page in
                let isCurrent = model.currentCaption?.id == page.id
                let range = shownRange(of: page)
                Text(page.plainText)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .frame(width: max(width(of: range.duration) - 2, 3), height: captionLaneHeight, alignment: .leading)
                    .background(
                        Color.orange.opacity(isCurrent ? 0.55 : 0.3),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .overlay(alignment: .leading) {
                        if page.source == .sound {
                            // Heard in a voice-over: a small mark so it reads apart from the clip's own.
                            Rectangle().fill(.primary.opacity(0.5)).frame(width: 2).padding(.vertical, 4)
                        }
                    }
                    .clipped()
                    .overlay { captionEdges(page) }
                    .offset(x: x(for: range.start) + 1)
                    .onTapGesture {
                        model.pause()
                        model.seek(to: page.firstFrame)
                        model.sidebar = .captions
                        model.focusedCaptionID = page.id
                    }
                    .help(page.text + "\nDrag an edge to change when it shows")
            }
        }
        .opacity(model.project.captions.isVisible ? 1 : 0.4)
    }

    /// Where a caption is drawn: where it is, or where its edge is being dragged to.
    func shownRange(of page: CaptionPage) -> CMTimeRange {
        guard let drag = captionEdgeDrag, drag.pageID == page.id else { return page.range }
        switch drag.edge {
        case .start: return CMTimeRange(start: min(drag.time, page.range.end - .oneFrame), end: page.range.end)
        case .end: return CMTimeRange(start: page.range.start, end: max(drag.time, page.range.start + .oneFrame))
        }
    }

    func captionEdges(_ page: CaptionPage) -> some View {
        HStack(spacing: 0) {
            captionEdgeHandle(page, .start)
            Spacer(minLength: 0)
            captionEdgeHandle(page, .end)
        }
    }

    func captionEdgeHandle(_ page: CaptionPage, _ edge: CaptionEdge) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(captionEdgeDrag?.pageID == page.id && captionEdgeDrag?.edge == edge ? 0.6 : 0.001))
            .frame(width: 6)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: edge == .start ? .leading : .trailing))
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        let base = edge == .start ? page.range.start : page.range.end
                        let time = max(base + seconds(value.translation.width), .zero).snappedToFrame()
                        captionEdgeDrag = (page.id, edge, time)
                        model.pause()
                        model.seek(to: time)
                    }
                    .onEnded { _ in
                        if let drag = captionEdgeDrag { model.moveCaptionEdge(page, drag.edge, to: drag.time) }
                        captionEdgeDrag = nil
                    }
            )
            .help(edge == .start ? "Drag to change when this caption starts" : "Drag to change when this caption ends")
    }

    /// The song, under everything else, with a line showing its volume (it dips where people talk).
    @ViewBuilder
    var musicLane: some View {
        if let range = model.project.musicRange, let song = model.musicAsset {
            let width = max(width(of: range.duration) - 2, 6)
            let isSelected = model.isSelected(.music)
            let shift = musicDrag ?? .zero
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green.opacity(isSelected ? 0.45 : 0.25))
                .overlay {
                    VolumeLine(points: model.musicEnvelope, origin: range.start, fullVolume: model.project.music?.volume ?? 1, pointsPerSecond: pointsPerSecond)
                        .stroke(Color.primary.opacity(0.75), lineWidth: 1.5)
                        .padding(.top, 14)
                        .padding(.bottom, 3)
                }
                .overlay {
                    if model.project.music?.showsBeats == true {
                        BeatMarks(beats: model.project.timelineBeats, origin: range.start, pointsPerSecond: pointsPerSecond)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topLeading) {
                    Label(song.name, systemImage: "music.note")
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.top, 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Color.yellow : Color.green.opacity(0.8), lineWidth: isSelected ? 2 : 1)
                }
                .frame(width: width, height: musicLaneHeight)
                .contentShape(Rectangle())
                .offset(x: x(for: range.start + shift) + 1)
                .gesture(clickTap { _, modifiers in model.click(.music, modifiers: modifiers) })
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        model.pause()
                        if !model.isSelected(.music) { model.selection = .music }
                        var start = max(.zero, range.start + seconds(value.translation.width))
                        snapLine = nil
                        if let stuck = model.snapped(start) {
                            start = stuck
                            snapLine = stuck
                        }
                        start = min(start, max(.zero, model.duration - CMTime(value: 1, timescale: 1)))
                        musicDrag = (start - range.start).snappedToFrame()
                    }
                    .onEnded { _ in
                        if let drag = musicDrag, drag != .zero { model.setMusicTimelineStart(range.start + drag) }
                        musicDrag = nil
                        snapLine = nil
                    })
                .contextMenu {
                    deleteButton(for: .music, single: "Remove Music")
                }
                .help("Music: \(song.name). The line shows its volume; it dips while people talk. Drag it to start the music later.")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Music: \(song.name)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else if !model.project.timeline.clips.isEmpty {
            Button("Add Music…", systemImage: "music.note") { MusicImportPanel.run(model: model) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: musicLaneHeight)
                .offset(x: leadingInset + 4)
                .help("Add a song to play under your Short. You can also drop a sound file here.")
        }
    }

    /// While choosing pauses to remove: the parts that would be cut, over the clips.
    @ViewBuilder
    var pauseCuts: some View {
        if let cuts = model.silenceSession?.plan.timelineCuts {
            ZStack(alignment: .topLeading) {
                ForEach(Array(cuts.enumerated()), id: \.offset) { _, cut in
                    Rectangle()
                        .fill(Color.red.opacity(0.45))
                        .overlay(Rectangle().strokeBorder(Color.red, lineWidth: 1))
                        .frame(width: max(width(of: cut.duration), 1), height: trackHeight)
                        .offset(x: x(for: cut.start))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
