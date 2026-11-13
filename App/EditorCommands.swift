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
            Button("New Magic Short…") { model.newMagicShort() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("New Short from Storyboard…") { model.choosesStoryboard = true }
            Button("Open…") { model.openProjectPanel() }
                .keyboardShortcut("o")
            Button("All Shorts") { model.showHome() }
                .keyboardShortcut("0", modifiers: [.command, .shift])
                .disabled(model.screen == .home)
            Divider()
            Menu("Style") {
                ForEach([nil] + ShortStyle.allCases.map(Optional.some), id: \.self) { (style: ShortStyle?) in
                    Toggle(style?.displayName ?? "None", isOn: Binding(get: { model.project.style == style }, set: { if $0 { model.setStyle(style) } }))
                }
            }
            .disabled(model.screen == .home || model.styleBeingMade != nil)
            Button("Magic Short…") { model.beginMagic() }
                .disabled(model.screen == .home || model.project.timeline.clips.isEmpty)
            Button(model.project.storyboard == nil ? "Storyboard…" : "Show Storyboard") {
                if model.project.storyboard == nil { model.choosesStoryboard = true } else { model.sidebar = .storyboard }
            }
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
            Button("Save Frame as Picture…") { model.saveFrame() }
            Divider()
            Button("Import Subtitle File (.srt)…") { model.importCaptionsFile() }
                .disabled(model.project.timeline.clips.isEmpty)
            Button("Export Subtitle File (.srt)…") { model.exportCaptionsFile() }
                .disabled(!model.project.hasCaptions)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.project.timeline.clips.isEmpty || model.screen == .home)
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
            let curvable = selectedClips.filter { model.project.timeline.index(of: $0.id) != nil && !model.project.isStill($0) }
            Menu("Speed Curve") {
                Button("None") { model.setSpeedCurve(nil, for: curvable.map(\.id)) }
                Divider()
                ForEach(SpeedCurveShape.allCases) { shape in
                    Button(shape.displayName) { model.setSpeedCurve(shape, for: curvable.map(\.id)) }
                }
            }
            .disabled(curvable.isEmpty)
            let animatable = selectedClips.map(\.id)
            Menu("Comes In") {
                Button("None") { model.setAnimation(nil, entering: true, for: animatable) }
                Divider()
                ForEach(MotionAnimation.allCases) { kind in
                    Button(kind.displayName) { model.setAnimation(kind, entering: true, for: animatable) }
                }
            }
            .disabled(animatable.isEmpty)
            Menu("Goes Out") {
                Button("None") { model.setAnimation(nil, entering: false, for: animatable) }
                Divider()
                ForEach(MotionAnimation.allCases) { kind in
                    Button(kind.displayName) { model.setAnimation(kind, entering: false, for: animatable) }
                }
            }
            .disabled(animatable.isEmpty)
            Menu("Add Effect") {
                ForEach(EffectKind.allCases) { kind in
                    Button(kind.displayName) { model.addEffect(kind, to: selectedClips.map(\.id)) }
                }
            }
            .disabled(selectedClips.isEmpty)
            Menu("Cut to the Beat") {
                ForEach(BeatSpacing.allCases) { spacing in
                    Button(spacing.displayName) { model.cutToBeat(spacing) }
                }
            }
            .disabled(model.project.music == nil || model.project.timeline.clips.isEmpty || model.findingBeats)
            Button("Add Freeze Frame") { model.addFreezeFrame() }
                .keyboardShortcut("f", modifiers: .option)
                .disabled(model.project.timeline.clips.isEmpty)
            Button("Instant Replay") { model.addInstantReplay() }
                .disabled(model.replayRange == nil)
            let turnable = selectedClips.filter { model.project.canReverse($0) }
            Toggle("Play Backwards", isOn: Binding(get: { !turnable.isEmpty && turnable.allSatisfy { model.project.isReversed($0) } },
                                                    set: { _ in model.toggleBackwards(for: turnable.map(\.id)) }))
                .disabled(turnable.isEmpty || !model.reversing.isEmpty)
            Menu("Transition") {
                Button("Add \(model.preferredTransition.kind.displayName) at Nearest Cut") { model.addTransition() }
                    .keyboardShortcut("t", modifiers: .option)
                Divider()
                ForEach(TransitionKind.allCases) { kind in
                    Button(kind.displayName) { model.addTransition(kind) }
                }
                Divider()
                Button("Remove at Nearest Cut") { model.removeTransitionAtPlayhead() }
                    .disabled(model.transitionCut.flatMap { model.project.transition(after: $0) } == nil)
                Button("Same on Every Cut") { model.setTransitionOnEveryCut(model.transitionCut.flatMap { model.project.transition(after: $0) } ?? model.preferredTransition) }
                Button("Remove All Transitions") { model.setTransitionOnEveryCut(nil) }
                    .disabled(model.project.transitionCount == 0)
            }
            .disabled(model.project.timeline.clips.count < 2)
            Divider()
            let lookTargets = model.lookTargets
            Button("Enhance") { model.enhance(lookTargets.map(\.id)) }
                .keyboardShortcut("e", modifiers: .option)
                .disabled(lookTargets.isEmpty)
            Menu("Filter") {
                Button("None") { model.setFilter(nil, for: lookTargets.map(\.id)) }
                Divider()
                ForEach(LookFilter.allCases) { filter in
                    Button(filter.displayName) { model.setFilter(filter, for: lookTargets.map(\.id)) }
                }
            }
            .disabled(lookTargets.isEmpty)
            Toggle("Compare with Original", isOn: Binding(get: { model.showsOriginalLook }, set: { model.showsOriginalLook = $0 }))
                .keyboardShortcut("c", modifiers: .option)
                .disabled(model.project.timeline.clips.isEmpty)
            let steadiable = lookTargets.filter(model.canStabilize)
            Toggle("Steady Shaky Video", isOn: Binding(get: { !steadiable.isEmpty && steadiable.allSatisfy { $0.steadiness > 0 } },
                                                      set: { on in model.setSteadiness(on ? Clip.defaultSteadiness : 0, for: steadiable.map(\.id)) }))
                .disabled(steadiable.isEmpty)
            let cuttable = lookTargets.filter(model.canCutOut)
            Menu("Remove Background") {
                Button("Off") { model.setRemoveBackground(nil, for: cuttable.map(\.id)) }
                Divider()
                ForEach(CutoutSubject.allCases) { subject in
                    Button("Keep \(subject.displayName)") { model.setRemoveBackground(subject, for: cuttable.map(\.id)) }
                }
            }
            .disabled(cuttable.isEmpty)
            Toggle("Green Screen", isOn: Binding(get: { cuttable.count == 1 && cuttable[0].cutout.key != nil },
                                                 set: { on in if let clip = cuttable.first { model.setColorKey(on, for: clip.id) } }))
                .disabled(cuttable.count != 1)
            Divider()
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
            Button(model.trimmerClipID == nil ? "Show Clip Trimmer" : "Hide Clip Trimmer") { model.toggleClipTrimmer() }
                .keyboardShortcut("\\", modifiers: .command)
                .disabled(model.trimmerClipID == nil && model.trimmableClip == nil)
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
            Menu("Add Ready-Made Text") {
                ForEach(TextTemplate.allCases) { template in
                    Button(template.displayName) { model.addTextTemplate(template) }
                }
            }
            .disabled(model.project.timeline.clips.isEmpty)
            Menu("Add Sticker") {
                Menu("Emoji") {
                    ForEach(StickerCatalog.emoji, id: \.self) { emoji in
                        Button(emoji) { model.addSticker(Sticker(.emoji(emoji))) }
                    }
                }
                ForEach(StickerCatalog.groups) { group in
                    Menu(group.name) {
                        ForEach(group.symbols) { symbol in
                            Button(symbol.displayName, systemImage: symbol.name) { model.addSticker(Sticker(.symbol(symbol.name))) }
                        }
                    }
                }
                Divider()
                Button("Show All Stickers…") { model.showsStickerPicker = true }
            }
            .disabled(model.project.timeline.clips.isEmpty)
            Button("Follow Something in the Video") { if let id = model.selectedTitleID { model.followInVideo(id) } }
                .disabled(model.selectedTitleID == nil || model.tracking != nil)
            Divider()
            Button("Speak Text…") { model.beginSpeech(for: model.selectedTitleID) }
                .disabled(model.project.timeline.clips.isEmpty || model.speechRequest != nil)
            Divider()
            Button("Make Captions") { model.makeCaptions() }
                .disabled(model.project.timeline.clips.isEmpty || model.captionJob != nil)
            Toggle("Show Captions", isOn: Binding(
                get: { model.project.captions.isVisible },
                set: { model.setCaptionsVisible($0) }
            ))
            .disabled(!model.project.hasCaptions)
            Picker("Caption Look", selection: Binding(get: { model.project.captions.style }, set: { model.setCaptionStyle($0) })) {
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
            Toggle("Loop Music", isOn: Binding(get: { model.project.music?.loops ?? false }, set: { model.setMusicLoops($0) }))
                .disabled(model.project.music == nil || model.project.music?.mood != nil)
            Button("Start Music at Playhead") { model.setMusicTimelineStart(model.currentTime) }
                .disabled(model.project.music == nil || model.currentTime >= model.duration)
            Toggle("Show Beats", isOn: Binding(get: { model.project.music?.showsBeats == true && model.project.hasBeats }, set: { model.setShowsBeats($0) }))
                .disabled(model.project.music == nil || model.findingBeats)
            Button("Add Beat at Playhead") { model.addBeatAtPlayhead() }
                .disabled(model.project.musicRange.map { !$0.containsTime(model.currentTime) } ?? true)
            Button("Remove Beat at Playhead") { model.removeBeatAtPlayhead() }
                .disabled(!model.beatNearPlayhead)
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
            Button("Add Marker") { model.addMarker() }
                .keyboardShortcut("m", modifiers: [])
                .disabled(model.project.timeline.clips.isEmpty)
            Button("Previous Marker") { model.goToMarker(forward: false) }
                .keyboardShortcut(";", modifiers: .control)
                .disabled(model.project.markers.isEmpty)
            Button("Next Marker") { model.goToMarker(forward: true) }
                .keyboardShortcut("'", modifiers: .control)
                .disabled(model.project.markers.isEmpty)
            Button("Rename Marker at Playhead…") { if let marker = model.markerAtPlayhead { model.markerBeingRenamed = marker.id } }
                .disabled(model.markerAtPlayhead == nil)
            Button("Delete Marker at Playhead") { if let marker = model.markerAtPlayhead { model.deleteMarker(marker.id) } }
                .disabled(model.markerAtPlayhead == nil)
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
