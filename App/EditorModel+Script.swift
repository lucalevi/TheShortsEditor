import EditorCore
import SwiftUI

/// Editing the Short by its text: cutting words, removing filler words.
extension EditorModel {

    /// Cuts the words (and the pause after each) out of the Short.
    func cutWords(_ words: Set<WordRef>) {
        guard !words.isEmpty else { return }
        let plan = project.cutPlan(removing: words)
        guard !plan.isEmpty else { return }
        playback.player.pause()
        apply(words.count == 1 ? "Cut Word" : "Cut \(words.count) Words") { $0.apply(plan) }
        scriptSelection = []
    }

    /// The filler sounds and repeated words in the Short, and the fillers Apple Intelligence found.
    var fillerWords: [WordRef] { project.fillerAndRepeatedWords(also: captioning.modelFillers) }

    func removeFillerWords() {
        let words = Set(fillerWords)
        guard !words.isEmpty else { return }
        playback.player.pause()
        let plan = project.cutPlan(removing: words)
        apply("Remove Filler Words") { $0.apply(plan) }
        scriptSelection = []
    }
}
