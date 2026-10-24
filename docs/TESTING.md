# Darkstar Robotics — testing & error handling

## The rule this suite exists to enforce

Every external boundary failure must surface as a **typed error with a
user-readable explanation and a recovery step** — never as a silent no-op
or a vague catch-all state. The 2026-10-24 demo session is the cautionary
tale: the runtime Start button shelled out to a `utmctl` binary that does
not exist in Abel's 2022 UTM build, the result was discarded, and the app
reported "UTM NOT AVAILABLE" forever with no hint why. That failure mode
is now a named test case at every tier.

All shared logic lives in the **DarkstarCore** target
(`Sources/DarkstarCore/DarkstarCore.swift`): `DarkstarError`,
`ProcessCommandRunner`, `RuntimeProbe`, the UTM/Tailscale parsers,
`SemanticVersion`, `UpdateEvaluator`, `ViewerURLPolicy`,
`SSHDestination`, and `PreflightRules`. The SwiftUI app is a thin shell
over it, so the tests exercise the code the app actually ships.

## The suite

| Tier | Location | Command | What it covers |
|---|---|---|---|
| Unit | `Tests/Unit` | `Scripts/run-tests.sh unit` | Error codes/messages/recovery/retryability, version comparison, UTM + Tailscale output parsing, update-response classification (network / 404 / 5xx / malformed / newer / current), viewer URL policy (localhost vs cleartext remote vs bad schemes), SSH destination validation, preflight thresholds incl. boundaries |
| Integration | `Tests/Integration` | `Scripts/run-tests.sh integration` | `RuntimeProbe` composed with a fake command runner (running / stopped / tool-missing / failing utmctl; Tailscale candidate selection), and the update flow through a real `URLSession` stubbed at `URLProtocol` (200 → update available, 404 → no releases, transport error → network failure, malformed payload → decoding failure) |
| End-to-end | `Tests/E2E` | `Scripts/run-tests.sh e2e` or `Scripts/e2e-smoke.sh` | The real `ProcessCommandRunner` against real processes (`echo`, `false`, missing binary, timeout kill), a real fake `utmctl` executable on disk probed end-to-end, and a real local HTTP replay server whose page passes `ViewerURLPolicy` and is actually fetched |

Everything: `Scripts/run-tests.sh` (plain `swift test`).

## Error-handling contract (for future code)

1. Boundaries return `DarkstarError` (or a status enum containing one).
   Do not return `(code, String)` pairs or swallow results with `_ =`.
2. A missing tool, a failed tool, and a timed-out tool are **different**
   errors with different recovery copy.
3. The UI shows `error.userMessage`; when `error.recoverySuggestion`
   exists, it shows that too. Diagnostic detail
   (`error.diagnosticMessage`) is for logs/support.
4. New boundary = new unit tests for its classification branches, an
   integration test for its composition, and an E2E test if it touches
   processes, files, or the network for real.
5. Statuses stay honest: an unselected or unprobed capability is
   UNKNOWN/neutral, never a warning, and never READY from a binary's mere
   presence.

## Manual smoke checklist (per release)

- [ ] Fresh launch: Dashboard renders; runtime chip matches the VM's
      actual state (check against UTM itself).
- [ ] UTM without `utmctl` (or VM stopped): Start produces the typed
      explanation in the runtime card, not silence.
- [ ] Viewer with `http://<tailnet-ip>:8000/demo/`: refused up front with
      the localhost/SSH-tunnel recovery text.
- [ ] Viewer with the replay served on this Mac at
      `http://localhost:8000/demo/`: replay loads; killing the server and
      reloading produces the "not reachable" message.
- [ ] Settings → Check for updates, online and offline: correct
      up-to-date / available / failed message each time.
- [ ] Missions → Watch the replay with no server running: a visible
      error, not a dead click.
- [ ] Installer: payload removed or version-mismatched → fails **before**
      touching an existing install; normal run updates in place.
