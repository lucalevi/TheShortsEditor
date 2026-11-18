# 8. Transitions don't change the Short's length

- Status: accepted
- Date: 2026-11-10

## Context

In iMovie a transition overlaps clips and shortens the movie, which moves everything after it. For Shorts, timed to music and a 3:00 limit, that surprises.

## Decision

A transition (`Clip.transitionOut`, a `ClipTransition`) plays half before and half after the cut; the other clip is borrowed onto a second video track, or held on its first/last frame. Clips never overlap in the model.

## Consequences

Adding a transition never moves anything else. A short neighbouring clip makes the transition shorter.
