# Architecture Decision Records

Short records of decisions that shape the code: why, and what follows from them. Add one when a choice would otherwise be re-argued; never rewrite an accepted one, write a new one that replaces it.

- [1. The project is one value; edits replace it and the player is rebuilt](0001-value-type-project.md)
- [2. One custom compositor draws every frame](0002-one-compositor.md)
- [3. Time is CMTime snapped to frames; the canvas is fixed](0003-time-as-cmtime.md)
- [4. Captions and keyframes live in the source file's time](0004-captions-per-source-file.md)
- [5. A library of Shorts in Application Support, not NSDocument](0005-library-not-nsdocument.md)
- [6. Damaged or unknown files refuse to open](0006-strict-decoding.md)
- [7. Slow work makes copies of files; the model stays simple](0007-made-copies-not-model-tricks.md)
- [8. Transitions don't change the Short's length](0008-transitions-keep-length.md)
- [9. Colour is decided in one place](0009-one-colour-pipeline.md)
- [10. Blocking work never runs on Swift's shared threads](0010-no-blocking-on-shared-threads.md)
