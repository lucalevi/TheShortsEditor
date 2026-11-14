# Continuous integration

Every check runs through one command, `make check`: formatting (`swift format lint --strict`),
SwiftLint against its baseline, the package tests with warnings as errors, and the Debug and
Release app builds with warnings as errors. It runs in two places.

## 1. Before every push (on now)

`make hooks` points git at `Tools/hooks`, whose `pre-push` runs `make check` and stops the push
when something fails. Run `make hooks` once per clone. `git push --no-verify` skips it in an
emergency; run `make check` straight after.

## 2. On GitHub, with this Mac as the runner (optional)

GitHub's hosted macOS runners only have Xcode 26, which can't build this code (CI was removed on
2026-11-13 for that reason), so the workflow `.github/workflows/check.yml` runs on a
**self-hosted runner**: this Mac, which has Xcode 27.

The workflow is off until the repository variable `SELF_HOSTED_RUNNER` is `true`. To turn it on:

1. GitHub ▸ the repository ▸ Settings ▸ Actions ▸ Runners ▸ **New self-hosted runner**, macOS,
   ARM64. Follow the download and `./config.sh` steps it shows (it gives a one-time token), in a
   folder outside the repository, e.g. `~/actions-runner`.
2. Install it as a background service so it starts with the Mac: `./svc.sh install && ./svc.sh start`.
3. Settings ▸ Secrets and variables ▸ Actions ▸ Variables ▸ New variable:
   `SELF_HOSTED_RUNNER` = `true`.

**Safety (the repository is public):** the workflow runs on pushes to `main` and manual runs
only, never on pull requests, so nobody without write access can run code on this Mac. Keep it
that way: don't add `pull_request` triggers. In Settings ▸ Actions ▸ General, also set "Fork pull
request workflows from outside collaborators" to require approval for all outside collaborators.
