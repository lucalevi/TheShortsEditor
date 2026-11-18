# 11. Shared without a Developer ID: ad hoc signed .dmg on GitHub Releases

- Status: accepted
- Date: 2026-11-18

## Context

Opening an app on another Mac without a warning needs a paid Apple Developer ID (99 USD/yr) and notarization. The user doesn't want to pay for it, but wants others to be able to download the app from the GitHub repository.

## Decision

Releases are ad hoc signed (`CODE_SIGN_IDENTITY: "-"`, as today) and packaged as a `.dmg` attached to a GitHub Release, with instructions for the first launch. Since macOS 15, Control-click ▸ Open no longer gets past Gatekeeper: the user opens the app once, then chooses Open Anyway in System Settings ▸ Privacy & Security (or removes the quarantine flag with `xattr -dr com.apple.quarantine`). Updates are announced, not installed: the app checks the GitHub Releases page and links to the new `.dmg`.

## Consequences

No yearly cost and no notarization step. Every person sees the "unknown developer" warning once per downloaded version. Each build has a new ad hoc signature, so macOS may ask again for permissions (microphone, Photos, speech) after an update. Sparkle's automatic install is left out. Buying a Developer ID later changes only signing and adds notarization; nothing else in the release script needs to change.
