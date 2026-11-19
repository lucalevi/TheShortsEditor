import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// Changing several selected things at once (usability pass 2): each change is one undo step and
/// reaches every selected clip and sound.
@Suite(.serialized)
struct SeveralAtOnceTests {
    @Test func oneVolumeForClipsAndSoundsInOneStep() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2), try await TestMedia.video(seconds: 2)])
        let model = editor.model
        // A recording on top, as a voice-over.
        editor.undo.beginUndoGrouping()
        await model.placeVoiceOver(try await TestMedia.video(seconds: 1), at: .zero)
        editor.undo.endUndoGrouping()
        let clips = model.project.timeline.clips.map(\.id)
        let sound = try #require(model.project.sounds.first?.id)
        editor.step { model.setClipsMuted([clips[0]], true) }

        editor.step { model.setClipsVolume(clips + [sound], 0.5) }
        #expect(model.project.timeline.clips.allSatisfy { $0.volume == 0.5 && !$0.isMuted })
        #expect(model.project.sound(id: sound)?.clip.volume == 0.5)
        #expect(editor.undo.undoActionName == "Change Volume")
        editor.undo.undo()
        #expect(model.project.timeline.clips[0].isMuted && model.project.timeline.clips[1].volume == 1)
    }

    @Test func oneColourSliderForSeveralClips() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2), try await TestMedia.video(seconds: 2)])
        let model = editor.model
        let clips = model.project.timeline.clips.map(\.id)
        editor.step { model.editColor(of: [clips[0]], "Light") { $0.exposure = 0.3 } }

        // While dragging, nothing is changed yet; on letting go, every clip gets the value and
        // keeps its other settings.
        model.previewColor(\.warmth, 0.6, for: clips)
        #expect(model.project.timeline.clips.allSatisfy { $0.look.color.warmth == 0 })
        model.previewColor(\.warmth, nil, for: clips)
        editor.step { model.editColor(of: clips, "Warmth") { $0.warmth = 0.6 } }
        #expect(model.project.timeline.clips.allSatisfy { $0.look.color.warmth == 0.6 })
        #expect(model.project.timeline.clips[0].look.color.exposure == 0.3)
        #expect(editor.undo.undoActionName == "Warmth")
    }
}
