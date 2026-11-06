## 1.4.1 local save correction (same delivery)

The user reported choosing an export destination but finding no file. The former export picker had no delegate/completion/error handling, and downloads only lived in a temporary preview folder. Downloads now keep a verified persistent copy in Documents/下载, exposed via Files using UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace. Credentials and account caches remain outside Documents.

“存储到文件” now selects a folder, retains security-scoped access during an NSFileCoordinator write, copies through a staging file, verifies the written size/existence, and reports success only after the move completes. Failure is visible; cancellation is not success. Existing names receive numeric suffixes without overwriting. The Files page has a local-download list and previews remain backed by persistent files. Added native regressions for source-temp removal, binary/Unicode preservation, chosen-folder export, collisions and missing-source failure. Actual third-party File Provider behavior still requires iPhone verification. The selected-folder flow follows [Apple directory access requirements](https://developer.apple.com/documentation/uikit/providing-access-to-directories).

## AGY 1.4.1 layout and ordered process correction

Replaced separate expanded-island center/trailing regions with one aligned card containing mark/status/timer/title. Compact mode now shows elapsed time or approval/sync text, with no sparkle symbol. Device-specific rendering still needs iPhone verification.

The default non-raw conversation presentation now interleaves the provider's actual public progress summaries with collapsed groups of consecutive tool operations, preserving step indexes. Completion folds the entire process once, leaving only a final answer expanded; a user can reopen details. No per-token scroll calls or expanded-state resets were added. The native-output default migrates once to this timeline; the explicit original/raw mode remains available.

Added a separate optional `finalText` field to distinguish actual terminal output from progress text. New turns initialize this field as empty and result events fill it; interrupted or final-less tasks cannot promote a summary to a final answer. Older records have a conservative compatibility path, and earlier text matching a final is retained when a tool intervenes.

Linux backend regressions: 24 passed (3.900 s before the final empty-field initialization change; final run recorded by CI). Added native tests for summary/tool alternation, interrupted turns, final-message separation, duplicate-final handling and repeated summary text. Syntax scan: 42 Swift files parsed. Xcode/IPA checks are delegated to the current Actions run. Background push remains unsupported as documented for 1.4.0.

## AGY 1.4.0 local Live Activities

Added an ActivityKit manager, shared Codable state/attributes, and a WidgetKit extension embedded in the app. Lock Screen and Dynamic Island use the official logo, bounded progress text, task phase, approval indication and timer. Deep links carry a scoped session ID, never a gateway key; wrong-account links are refused. Task content is hidden by default. Updates are serialized/coalesced, old-account activities are cleared, finished tasks end with a short dismissal delay, and user-dismissed tasks are suppressed.

This is a **local-only** implementation (`pushType: nil`). Going to the background pauses the existing SSE stream and marks the activity stale/pending sync. A 45-second stale date also prevents a disconnected activity claiming fresh progress indefinitely. The app resumes the tracked conversation on reconnect. There is no APNs registration/provider, background completion notification or unlimited background execution. See [Apple's ActivityKit update documentation](https://developer.apple.com/documentation/ActivityKit/starting-and-updating-live-activities-with-activitykit-push-notifications).

Version 1.4.0 / build 7. Added executable Swift policy tests for phase transitions, privacy, bounded payload and cross-account deep links. Packaging signs the extension before the host and validates its presence, bundle/version match, architecture and assets. Linux syntax scan passed for 42 Swift files; actual Mac build results are recorded by the Actions run. Device rendering, system permissions, re-signing preservation and lifecycle behavior still require iPhone verification. Backend code and production service are unchanged.

## 2026-11-02 Actions build attempt

User authorized pushing the current source and trying an iPhone workflow. The current GitHub OAuth credential lacks workflow-edit scope, so the existing push-triggered workflow is preserved. `scripts/package.sh` runs the additional configuration-memory, file-label, history, presentation and scroll tests before the IPA archive. No second manual dispatch is issued. Python regressions rechecked locally: **23 passed** (3.947 s), including the current project-snapshot filtering regression. Prior source-only validation records below describe their original delivery dates; they are not statements about this newly authorized run. Actual macOS/IPA results are reported by the Actions run.

## AGY 1.3.1 configuration memory correction

- Fixed a client bug: connection initialization always replaced the selected model/workspace, and task preferences were only in memory. A Codable snapshot is now persisted with UserDefaults under a server+account-scoped key, outside the transient conversation cache. Model variant IDs retain the selected thinking effort. New conversations restore the saved snapshot; selecting existing history does not rewrite it; explicit successful changes update it. Failed server configuration requests do not write preferences.
- Account switching never imports another account's permission or workspace defaults. Unavailable models and out-of-root workspaces are validated against the current server catalog/roots. The saved project directory is checked against the server on reconnect. Existing sessions continue to use their own server-saved configuration.
- Swift syntax validation: **30 source files and 7 test files (37 total)** parse successfully with tree-sitter-swift. Xcode project regenerated as **1.3.1 / build 6** and includes every source file.
- Added `AGYConfigurationMemoryTests.swift` covering reloaded preferences, origin/account isolation, model fallback, workspace boundary checks, invalid enum values and corrupted data. It is wired into `scripts/check-local.sh`. These executable Swift tests and native typechecking were **not run** because this Linux environment has no Swift compiler or Xcode. Syntax checks do not establish an iOS build or device pass.
- Backend code is unchanged in this client-only fix. The preceding 22 passing Python gateway tests remain the latest backend validation; they were not rerun for this change. No production service restart or account change, no push, no GitHub Actions and no IPA build occurred.

## AGY 1.3.0 file browser and directory mentions

- Linux Python 3.10: `python3 -W error::ResourceWarning -m unittest discover -s Server -v` — **22 tests passed**, 3.840 seconds, including six new file-workflow tests. Existing macOS root-alias regression remains passing.
- New coverage: authenticated HTTP browsing/upload/binary download/folder-reference admission; UTF-8 and space/newline names; original upload names; upload without a model turn; empty and own-conversation artifact scopes; reference-only requests; folder and file paths delivered as escaped context without preloading contents; request-ID conflict detection with changed references; forbidden links, traversal, missing files and credential-directory refusal.
- Swift tree-sitter syntax scan: **29 Sources + 6 Tests = 35 files parsed**. Xcode project regenerated with the new sources, version **1.3.0 / build 5**. Added `AGYFilePresentationTests.swift` and wired it into `scripts/check-local.sh` for execution on a Mac.
- This environment has no Swift compiler or Xcode. Swift typechecking, native executable tests, iPhone archive/IPA, file-provider behavior, mention sheet and Quick Look interaction are **not verified here**. A syntactic parse is not a successful native build.
- No push, GitHub Actions dispatch, production gateway restart, account switch or real-account model task was performed for this change. Python integration tests use a temporary fake CLI and temporary files; this change does not claim a real CLI end-to-end run.
- File-manager limits: regular-file upload/download at most 25 MiB each, 8 selections per upload batch, 8 distinct references per message, 5000 listed entries per directory. Whole-folder `@` is supported; folder ZIP download, delete/rename/move and recursive global search are not implemented. Chat attachment sends retain their 50 MiB total limit.

# AGY iPhone validation

## macOS path normalization correction

- Canonicalized temporary fixture roots in both Python test suites and compared HOME against `a.resolve()`.
- `open_file()` now recognizes equivalent spellings of the permitted root, including macOS `/var` versus `/private/var`, while preserving every child component for `O_NOFOLLOW`. It does not resolve the requested file or its in-workspace directories. A root alias cannot be manufactured by following a link after entering an allowed subdirectory.
- Parent traversal is rejected before `abspath` can erase the `..` component. Internal and external directory links and final file links remain rejected.
- Added portable alias regressions that reproduce the original 403 on Linux before the fix, plus link/traversal regressions. All 16 Python tests pass locally with ResourceWarnings promoted to errors.
- This correction has not been run on a macOS runner here. Swift and IPA stages were not run or claimed successful. No push, Actions invocation, production restart or account switch was performed.

## 1.2.0 / build 4 — 2026-10-30 local source delivery

- No repository push or GitHub Actions run was performed for this delivery. Both packaged workflows are manual-dispatch only. No new IPA, Xcode archive, simulator run or device acceptance is claimed.
- Local Python regression: 14 tests pass across legacy streaming/idempotency/upload recovery and new model/effort resolution, invalid combinations, profile isolation, missing approval-backend rejection, private socket approval authentication, wrong-session rejection, single-use decisions, expiration, stop/cancel and artifact path confinement/byte preservation.
- Real CLI 1.4.10 integration used a temporary independent profile and a copy of the existing server login solely for a harmless `printf NATIVE_REVIEW_OK` probe. Restriction + Deny surfaced one native request and the tool was blocked; Restriction + Allow surfaced one request and printed the marker; Turbo surfaced zero native requests and printed the marker. Temporary copied credentials were removed with the isolated directory. This was NOT a new Google account login or a change to the shared production account.
- Official session settings schema was checked for separate `toolPermission`, `artifactReviewPolicy`, execution mode and sandbox fields. The bridge uses actual official hook output, not unsupported stream-json control_response messages. Artifact waiting is disabled per turn because the native bridge reviews tools before execution; the desktop artifact-review interface is not replicated.
- Swift syntax parsing passed for all 63 top-level Swift sources across AGY and PI. This is not a Swift type check or iOS SDK compile. A local Mac check script is included for native protocol, output presentation, history, imports and the new scroll policy.
- Pi comparison baseline is the latest local `7bd64df`, newer than the repository default branch. Output display modes, wrapped code/tables, Unicode links, authenticated file previews/downloads, SVG/image rendering, date grouping and cache/draft behavior are adapted with AGY-specific transport.
- PI 2.0.7 source contains the shared gesture-aware scroll follower. Removed lazy bottom-preference default inference, per-revision scrollTo, focus-triggered scrollTo and default bottom anchoring. Code-block expansion is initialized once instead of resetting onAppear. Source regression cases cover paused follow during idle updates, geometry changes, invalid distances, explicit return and conversation reset; executable Swift tests and actual phone scrolling remain unverified here.
- The new server/client must be deployed together. The running production gateway was not restarted or moved to this release. Account switching remains for the user to complete later through ACCOUNT_LOGIN.md; old credentials were not logged out or overwritten.

## 1.1.0 / build 3

- [GitHub Actions run 40459949881](https://github.com/ddyec/Agy-iPhone/actions/runs/40459949881) passed gateway, native protocol, coordinated-document/photo-import tests and the physical iPhone archive. Downloaded IPA was rechecked as version 1.1.0 / build 3, arm64 iPhoneOS, native rendering, source commit `11bd09a628f27b2458c73f22465d51e229445d41`.

- The gateway-only runtime is now official CLI 1.4.8, verified against the release manifest SHA-512. Existing Pi container binaries and the original Remote Control binary were left unchanged.
- Real model discovery returns 13 canonical variants, including `gemini-4-argon-low`, `gemini-4-argon-medium` and `gemini-4-argon-high`. The prior 1.1.27 runtime omitted Gemini 4 from its own `models` output; the native client did not filter it out.
- `/v1/limits` reads the structured `command.data` from `agy -p /usage --output-format json`. Public HTTPS verification returned Gemini Models, Claude and GPT models, and Gemini 4 Argon quota groups with actual remaining fractions and reset timestamps. The CLI command itself reported zero inference turns/tokens. No absolute token allowance was inferred.
- Public HTTPS integration uploaded a synthetic quadrant-color PNG and a text file as raw bytes. Gemini 4 Argon Medium correctly reported red in the top-left, yellow in the bottom-right and the marker `ATTACHMENT_READ_6384`. The returned source paths pointed to uploaded copies under the session's `.agy-uploads` directory. Switching that same session to Gemini 3.8 Flash Low preserved the AGY conversation ID and recalled the exact marker without re-uploading or re-reading tools.
- Eight gateway scenarios passed locally: HTTP authentication/SSE, uploads with exact bytes, per-session ownership, attachment-only prompts, duplicate request admission, payload conflicts, traversal and symlink rejection, oversized-file rejection, truncated-transfer cleanup, quota parsing, model switching with preserved history, process stop and restart recovery.
- Native import routines are reused from Pi: coordinated iCloud/document reads and orientation-aware JPEG downsampling. CI now runs their real-file/EXIF/oversize tests without a simulator.
- iPhone picker presentation, keyboard behavior, large uploads over a mobile network and native quota/model screens still require physical-device acceptance. No simulator was run.

## 1.0.1 / build 2

- [GitHub Actions run 40456747196](https://github.com/ddyec/Agy-iPhone/actions/runs/40456747196) passed all protocol/gateway tests and the physical iPhone archive. IPA source commit: `ad115f0e17380a95de3d59417247c4f55d026454`. Downloaded IPA revalidation confirmed version 1.0.1, build 2, arm64 iPhoneOS and the native rendering marker. The exported official app icon was visually inspected and checked as an opaque 1024×1024 RGB PNG.

- Dedicated remotely managed Cloudflare tunnel `agy-iphone` serves `https://agy.yectech.uk` and is installed as an enabled systemd user service. The earlier temporary tunnel process has been replaced. Tunnel state was verified healthy via the Cloudflare API.
- Public requests with no gateway key or an incorrect key returned 401; an authorized request returned 200. The zone’s existing Browser Integrity Check is preserved. Native requests now identify their actual iOS version and the AGY iPhone client in the mobile User-Agent, matching the existing Pi compatibility approach.
- A real two-turn probe through the public HTTPS hostname preserved the same AGY conversation ID and recovered the marker from the previous turn. Initial running-state SSE snapshots arrived after 347 ms and 309 ms, before the turns completed at 12.365 s and 6.915 s. The probe session was removed from the gateway afterwards. These are server-to-public-ingress measurements, not physical iPhone results.
- Official full-color PNG/SVG were downloaded unchanged from Google Press Assets. The App’s mark image is byte-identical to the official PNG. SHA-256: `e0cd08ccd10cd8d08ccf0ba449823ee88495825c0841619618100d3ab089f51e`. The device icon uses the same mark composited on white at 1024×1024; the custom A icon has been removed.
- Native login now prefills the fixed HTTPS hostname. Gateway and Cloudflare credentials remain outside source control and public build artifacts.
- Device acceptance and unsupported features below remain unchanged.

## 1.0.0 / build 1 archive

### Verified

- Source archived in IPA: `728335c45c56a9637c1c595426bc10d2abe39d83`.
- [GitHub Actions run 40451643292](https://github.com/ddyec/Agy-iPhone/actions/runs/40451643292): gateway tests, native SSE/message/Markdown regression checks, Xcode project generation, Release iPhoneOS archive, ad-hoc signature and IPA structural verification all passed.
- Downloaded IPA was independently rechecked on the development server: arm64, physical iPhoneOS platform, iPhone-only device family, portrait orientation, `AGYNativeRendering`, compiled assets and no legacy webpage JavaScript.
- Real installed CLI: `agy 1.1.27`. Real authenticated model listing returned 10 entries. No account tokens or gateway keys were committed or included in the IPA.
- Live CLI smoke request returned `AGY_NATIVE_OK` without tools.
- Live deployed gateway, accessed only over server loopback: status/models returned 200. Two text-only turns returned the marker `AGY_NATIVE_20261027` and preserved the same AGY conversation ID. The second turn was asked to retrieve the marker from previous context. Initial authoritative SSE snapshots arrived after 13 ms and 9 ms; completed turns took 17.442 s and 7.220 s in this server-local probe. These timings are not mobile-network latency measurements.
- Sending each request twice with the same idempotency key admitted one user message. The isolated probe's gateway session was deleted afterwards; AGY retains its own raw conversation.
- Gateway regression tests cover authenticated HTTP/SSE, Unicode, final response reconciliation, tool transition deduplication, request idempotency/conflict, concurrent admission rejection, stop-before-launch/process stop, restart without resubmission, workspace escape/symlinks, invalid model selection, and gateway deletion. Five test scenarios passed locally and in CI using a fake CLI fixture; the separate two-turn smoke above used the real CLI.
- A dedicated systemd user service runs the gateway on `127.0.0.1:8766`. Its separate connection key is held in a restricted server-local file. Existing Pi services and the official AGY Remote Control daemon remain available.

### Not verified / not included

- No iPhone device was attached. Keyboard geometry, scrolling, VoiceOver, app switching, signing/install and real mobile-network recovery still need physical-device acceptance. No simulator was run, consistent with the existing Pi project convention.
- The binary requires personal re-signing. No Apple distribution certificate, App Store upload or TestFlight delivery was configured.
- The original 1.0.0 package preceded public-ingress authorization. The user subsequently authorized the public endpoint; current deployment and request verification are recorded in the 1.0.1 section above.
- App-managed session history does not import the official Remote Control history. Native interactive tool approvals, attachments, file browser/download and push notifications are not implemented in this first release. CLI permissions remain in effect; the adapter never sets `--dangerously-skip-permissions`.

### Device acceptance

1. Re-sign and install with Bundle ID `com.ddyec.agy-iphone`, leaving Pi installed.
2. Enter `https://agy.yectech.uk` and the separately delivered gateway key. Restart the App and confirm keychain restoration.
3. Send a short message, check incremental text, then ask a follow-up that depends on the first answer. Close/reopen while a response runs and compare the reconciled history.
4. Test Chinese keyboard, multiline composer, large text, light/dark appearances, long code/table horizontal scrolling, copy/share and history selection.
5. Drop the network during send. Verify the App shows an uncertain send state, preserves its request ID and reconciles or retries that same ID without duplicate execution.
6. Stop a running task and verify it stays stopped. In a disposable project, separately validate plan mode and accept-edits behavior under AGY's existing permission rules.
