# AGY iPhone validation

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
