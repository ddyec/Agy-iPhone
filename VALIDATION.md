# AGY iPhone 1.0.0 / build 1

## Verified

- Source archived in IPA: `728335c45c56a9637c1c595426bc10d2abe39d83`.
- [GitHub Actions run 40451643292](https://github.com/ddyec/Agy-iPhone/actions/runs/40451643292): gateway tests, native SSE/message/Markdown regression checks, Xcode project generation, Release iPhoneOS archive, ad-hoc signature and IPA structural verification all passed.
- Downloaded IPA was independently rechecked on the development server: arm64, physical iPhoneOS platform, iPhone-only device family, portrait orientation, `AGYNativeRendering`, compiled assets and no legacy webpage JavaScript.
- Real installed CLI: `agy 1.1.27`. Real authenticated model listing returned 10 entries. No account tokens or gateway keys were committed or included in the IPA.
- Live CLI smoke request returned `AGY_NATIVE_OK` without tools.
- Live deployed gateway, accessed only over server loopback: status/models returned 200. Two text-only turns returned the marker `AGY_NATIVE_20261027` and preserved the same AGY conversation ID. The second turn was asked to retrieve the marker from previous context. Initial authoritative SSE snapshots arrived after 13 ms and 9 ms; completed turns took 17.442 s and 7.220 s in this server-local probe. These timings are not mobile-network latency measurements.
- Sending each request twice with the same idempotency key admitted one user message. The isolated probe's gateway session was deleted afterwards; AGY retains its own raw conversation.
- Gateway regression tests cover authenticated HTTP/SSE, Unicode, final response reconciliation, tool transition deduplication, request idempotency/conflict, concurrent admission rejection, stop-before-launch/process stop, restart without resubmission, workspace escape/symlinks, invalid model selection, and gateway deletion. Five test scenarios passed locally and in CI using a fake CLI fixture; the separate two-turn smoke above used the real CLI.
- A dedicated systemd user service runs the gateway on `127.0.0.1:8766`. Its separate connection key is held in a restricted server-local file. Existing Pi services and the official AGY Remote Control daemon remain available.

## Not verified / not included

- No iPhone device was attached. Keyboard geometry, scrolling, VoiceOver, app switching, signing/install and real mobile-network recovery still need physical-device acceptance. No simulator was run, consistent with the existing Pi project convention.
- The binary requires personal re-signing. No Apple distribution certificate, App Store upload or TestFlight delivery was configured.
- No public HTTPS ingress has been created. Automatic approval review rejected creating a public Cloudflare tunnel pending explicit user authorization because it exposes authenticated AGY execution capability. Loopback-only tests and packaging proceeded independently.
- App-managed session history does not import the official Remote Control history. Native interactive tool approvals, attachments, file browser/download and push notifications are not implemented in this first release. CLI permissions remain in effect; the adapter never sets `--dangerously-skip-permissions`.

## Device acceptance

1. Re-sign and install with Bundle ID `com.ddyec.agy-iphone`, leaving Pi installed.
2. Once an HTTPS ingress is authorized and configured, enter its address and the separate gateway key. Restart the App and confirm keychain restoration.
3. Send a short message, check incremental text, then ask a follow-up that depends on the first answer. Close/reopen while a response runs and compare the reconciled history.
4. Test Chinese keyboard, multiline composer, large text, light/dark appearances, long code/table horizontal scrolling, copy/share and history selection.
5. Drop the network during send. Verify the App shows an uncertain send state, preserves its request ID and reconciles or retries that same ID without duplicate execution.
6. Stop a running task and verify it stays stopped. In a disposable project, separately validate plan mode and accept-edits behavior under AGY's existing permission rules.
