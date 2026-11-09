import EditorCore
import RenderEngine
import SwiftUI

/// Menu bar commands. Every keyboard shortcut lives here so it is also discoverable in a menu.
struct EditorCommands: Commands {
    let model: EditorModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Short") { model.newShort() }
                .keyboardShortcut("n")
            Button("Open…") { model.openProjectPanel() }
                .keyboardShortcut("o")
            Button("All Shorts") { model.showHome() }
                .keyboardShortcut("0", modifiers: [.command, .shift])
                .disabled(model.screen == .home)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { model.save() }
                .keyboardShortcut("s")
                .disabled(model.screen == .home)
            Button("Save a Copy…") { model.saveCopy() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.screen == .home || model.project.assets.isEmpty)
            Divider()
            Button("Import Media…") { MediaImportPanel.run(model: model, addToTimeline: false) }
                .keyboardShortcut("i")
            Button("Find Missing Files…") { model.findMissingFiles() }
                .disabled(model.missingAssets.isEmpty)
            Divider()
            Button("Export Short…") { model.beginExport() }
                .keyboardShortcut("e")
                .disabled(model.project.timeline.clips.isEmpty || model.exportPhase != nil)
        }

        CommandGroup(after: .pasteboard) {
            // ⌘A (Edit ▸ Select All) selects everything on the timeline when no text is being
            // edited; EditorKeys handles that, since the standard item only reaches text fields.
            Button("Deselect All") { model.selection = nil }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(model.timelineSelection.isEmpty)
            Divider()
            Button("Copy Settings") { model.copySettings() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model.settingsSource.clip == nil && model.settingsSource.title == nil)
            Menu("Paste Settings") {
                Button("All") { model.pasteAllSettings() }
                    .keyboardShortcut("v", modifiers: [.command, .option])
                Divider()
                ForEach(SettingsKind.allCases) { kind in
                    Button(kind.displayName) { model.pasteSettings([kind]) }
                        .disabled(model.copiedClip == nil)
                }
                Button("Title Design") { model.pasteTitleDesign() }
                    .disabled(model.copiedTitle == nil)
            }
            .disabled(!model.canPasteSettings)
        }

        CommandMenu("Clip") {
            Button("Split at Playhead") { model.splitAtPlayhead() }
                .keyboardShortcut("b", modifiers: [])
                .disabled(model.project.timeline.clips.isEmpty)
            Button("Trim Start to Playhead") { model.trimToPlayhead(removing: .start) }
                .keyboardShortcut("q", modifiers: [])
                .disabled(model.project.timeline.clips.isEmpty)
            Button("Trim End to Playhead") { model.trimToPlayhead(removing: .end) }
                .keyboardShortcut("w", modifiers: [])
                .disabled(model.project.timeline.clips.isEmpty)
            Button(model.timelineSelection.count > 1 ? "Delete \(model.timelineSelection.count) Items"
                   : model.selection == .music ? "Remove Music" : model.selectedTitleID != nil ? "Delete Title" : "Delete Clip") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.timelineSelection.isEmpty)
            Divider()
            Button("Select Clip Range") { model.selectClipRange() }
                .keyboardShortcut("x", modifiers: [])
                .disabled(model.project.timeline.clips.isEmpty)
            Button("Trim to Range") { model.trimToRange() }
                .keyboardShortcut("/", modifiers: .option)
                .disabled(model.timelineRange == nil)
            Button("Delete Range") { model.deleteRange() }
                .disabled(model.timelineRange == nil)
            Button("Clear Range") { model.clearRanges() }
                .disabled(model.timelineRange == nil && model.mediaRange == nil)
            Divider()
            Button("Add Selected Media to End") { model.appendSelectedMedia() }
                .keyboardShortcut("e", modifiers: [])
                .disabled(model.selectedAssetID == nil)
            Button("Insert Selected Media at Playhead (W)") { model.insertSelectedMedia() }
                .disabled(model.selectedAssetID == nil)
            Button("Add Over Clips at Playhead…") { OverlayImportPanel.run(model: model) }
                .disabled(model.project.timeline.clips.isEmpty)
            Divider()
            let selectedClips = model.timelineSelection.items.compactMap { item -> Clip? in
                switch item {
                case .clip(let id), .overlay(let id): model.project.anyClip(id: id)
                default: nil
                }
            }
            Button(model.isPunchedIn(selectedClips) ? "Remove Punch-In" : "Punch In") { model.togglePunchIn(selectedClips.map(\.id)) }
                .disabled(selectedClips.allSatisfy(\.hasMotion))
            Button("Punch In on Every Other Cut") { model.punchInOnAlternateCuts() }
                .disabled(model.project.timeline.clips.count < 2)
            Menu("Speed") {
                ForEach(Clip.speedPresets, id: \.self) { speed in
                    Button(speed == 1 ? "Normal (1×)" : "\(speed.formatted())×") {
                        if model.timelineRange != nil {
                            model.setSpeedInRange(speed)
                        } else {
                            model.setSpeed(speed, for: selectedClips.filter { model.project.asset(id: $0.assetID)?.isImage != true }.map(\.id))
                        }
                    }
                }
            }
            .disabled(selectedClips.isEmpty && model.timelineRange == nil)
            Button("Follow the Subject") { if let clip = selectedClips.first { model.followSubject(clip.id) } }
                .disabled(selectedClips.count != 1 || model.reframing != nil)
            Menu("Motion") {
                ForEach(MotionPreset.allCases) { preset in
                    Button(preset.displayName) { if let clip = model.adjustableClip { model.applyMotion(preset, to: clip.id) } }
                }
                Divider()
                Button("Add Keyframe") { if let clip = model.adjustableClip { model.addKeyframe(to: clip.id) } }
                Button("Remove Motion") { if let clip = model.adjustableClip { model.removeMotion(from: clip.id) } }
                    .disabled(model.adjustableClip?.hasMotion != true)
            }
            .disabled(model.adjustableClip == nil)
            Button("Reset All Settings") { model.resetSelectedClips() }
                .disabled(selectedClips.isEmpty)
            Divider()
            Button("Remove Pauses…") { model.beginRemovingSilences() }
                .disabled(model.project.timeline.clips.isEmpty || model.silenceSession != nil)
        }

        CommandMenu("Text") {
            Button("Add Title") { model.addTitle() }
                .keyboardShortcut("t")
                .disabled(model.project.timeline.clips.isEmpty)
            Divider()
            Button("Make Captions") { model.makeCaptions() }
                .disabled(model.project.timeline.clips.isEmpty || model.captionJob != nil)
            Toggle("Show Captions", isOn: Binding(
                get: { model.project.captions.isVisible },
                set: { model.setCaptionsVisible($0) }
            ))
            .disabled(!model.project.hasCaptions)
            Picker("Caption Style", selection: Binding(get: { model.project.captions.style }, set: { model.setCaptionStyle($0) })) {
                ForEach(CaptionStyle.allCases) { Text($0.displayName).tag($0) }
            }
            .disabled(!model.project.hasCaptions)
        }

        CommandMenu("Sound") {
            Button(model.isRecordingVoiceOver ? "Stop Recording" : "Record Voice-Over") {
                if model.isRecordingVoiceOver { model.stopVoiceOver() } else { model.startVoiceOver() }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(model.project.timeline.clips.isEmpty)
            Menu("Add Sound Effect") {
                ForEach(SoundEffectGroup.allCases) { group in
                    Menu(group.displayName) {
                        ForEach(group.effects) { effect in
                            Button(effect.displayName) { model.addSoundEffect(effect) }
                        }
                    }
                }
            }
            .disabled(model.project.timeline.clips.isEmpty)
            Divider()
            Button("Add Music…") { MusicImportPanel.run(model: model) }
                .disabled(model.project.timeline.clips.isEmpty)
            Button("Remove Music") { model.removeMusic() }
                .disabled(model.project.music == nil)
            Toggle("Lower Music While People Talk", isOn: Binding(
                get: { model.project.music?.lowersUnderSpeech ?? false },
                set: { on in model.editMusic(on ? "Lower Music Under Speech" : "Keep Music Level") { $0.lowersUnderSpeech = on } }
            ))
            .disabled(model.project.music == nil)
            Divider()
            if let clip = model.selectedClip {
                Toggle("Mute Clip", isOn: Binding(get: { clip.isMuted }, set: { model.setClipMuted(clip.id, $0) }))
                Toggle("Clean Up Voice", isOn: Binding(get: { clip.cleansVoice }, set: { model.setCleansVoice($0, for: [clip.id]) }))
                    .disabled(model.project.asset(id: clip.assetID)?.hasAudio != true)
            } else {
                Button("Mute Clip") {}.disabled(true)
                Button("Clean Up Voice") {}.disabled(true)
            }
            Button("Detach Sound") { model.detachSound() }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(model.detachableClips.isEmpty)
            Button("Add Volume Point at Playhead") { model.addVolumePointAtPlayhead() }
                .disabled(model.project.timeline.locate(model.currentTime) == nil)
            Menu("Voice Effect") {
                Button("None") { model.setVoiceEffect(nil, for: model.selectedClips.map(\.id)) }
                Divider()
                ForEach(VoiceEffect.allCases) { effect in
                    Button(effect.displayName) { model.setVoiceEffect(effect, for: model.selectedClips.map(\.id)) }
                }
            }
            .disabled(model.selectedClips.isEmpty)
        }

        CommandMenu("Playback") {
            Button(model.isPlaying ? "Pause" : "Play") { model.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
            Divider()
            Button("Play Backwards / Faster Backwards") { model.shuttle(forward: false) }
                .keyboardShortcut("j", modifiers: [])
            Button("Stop") { model.pause() }
                .keyboardShortcut("k", modifiers: [])
            Button("Play Forwards / Faster Forwards") { model.shuttle(forward: true) }
                .keyboardShortcut("l", modifiers: [])
            Divider()
            Button("Previous Frame") { model.step(frames: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next Frame") { model.step(frames: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Go to Start") { model.seek(to: .zero) }
                .keyboardShortcut(.home, modifiers: [])
            Button("Go to End") { model.seek(to: model.duration) }
                .keyboardShortcut(.end, modifiers: [])
            Button("Previous Edit") { model.goToEdit(forward: false) }
                .keyboardShortcut(";", modifiers: [])
            Button("Next Edit") { model.goToEdit(forward: true) }
                .keyboardShortcut("'", modifiers: [])
            Divider()
            Button("Play Selection") { model.playSelection() }
                .keyboardShortcut("/", modifiers: [])
            Button("Play from Start") { model.playFromStart() }
                .keyboardShortcut("\\", modifiers: [])
            Toggle("Loop Playback", isOn: Binding(get: { model.loopsPlayback }, set: { model.loopsPlayback = $0 }))
                .keyboardShortcut("l", modifiers: .command)
            Button(model.isFullScreenPreview ? "Leave Full Screen" : "Play Full Screen") { model.toggleFullScreenPreview() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(model.project.timeline.clips.isEmpty)
        }

        CommandGroup(before: .toolbar) {
            Toggle("Show YouTube Overlay Areas", isOn: Binding(get: { model.showsSafeZone }, set: { model.showsSafeZone = $0 }))
                .keyboardShortcut("'", modifiers: .command)
            Toggle("Snapping", isOn: Binding(get: { model.snapsToEdges }, set: { model.snapsToEdges = $0 }))
                .keyboardShortcut("s", modifiers: [])
            Toggle("Skimming", isOn: Binding(get: { model.skimsTimeline }, set: { model.skimsTimeline = $0 }))
            Toggle("Audio Skimming", isOn: Binding(get: { model.skimsAudio }, set: { model.skimsAudio = $0 }))
                .keyboardShortcut("s", modifiers: .shift)
                .disabled(!model.skimsTimeline)
            Button("Zoom In Timeline") { model.zoom(by: 1.5) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out Timeline") { model.zoom(by: 1 / 1.5) }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
        }
    }
}

/// The standard Open panel, filtered to videos, pictures and sound files.
enum MediaImportPanel {
    static func run(model: EditorModel, addToTimeline: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .image, .audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = addToTimeline ? "Add to Timeline" : "Import"
        panel.message = "Choose the videos, pictures (or music) for your Short"
        guard panel.runModal() == .OK else { return }
        model.importFiles(panel.urls, addToTimeline: addToTimeline)
    }
}

/// The Open panel for B-roll: the videos or pictures go over the clips at the playhead.
enum OverlayImportPanel {
    static func run(model: EditorModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add Over Clips"
        panel.message = "Choose B-roll or pictures to show over your clips, starting at the playhead"
        guard panel.runModal() == .OK else { return }
        model.importFiles(panel.urls, to: .overlay(at: model.currentTime))
    }
}

/// The Open panel for choosing a song. It becomes the music straight away.
enum MusicImportPanel {
    static func run(model: EditorModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use as Music"
        panel.message = "Choose a song to play under your Short"
        guard panel.runModal() == .OK else { return }
        model.importFiles(panel.urls, addToTimeline: true)
    }
}
