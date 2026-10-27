# AGY iPhone gateway API

Base URL: `https://agy.yectech.uk`. All routes require `Authorization: Bearer <gateway-key>`. This is the separately delivered App gateway key, not a Google OAuth or Cloudflare token. No credentials appear in this repository.

The current zone retains Browser Integrity Check. The native App sends a mobile User-Agent identifying its iOS version and `AGY-iPhone`. External API integrations should use a compatible mobile client User-Agent too; Python's default User-Agent is rejected by the existing zone before reaching the gateway.

## Read account limits

`GET /v1/limits` returns actual structured account quota from the authenticated CLI command `agy -p /usage --output-format json`. This is a read-only CLI command, not a model prompt. Responses are cached for 30 seconds; `GET /v1/limits?refresh=1` forces a refresh.

Response shape (illustrative values):

```json
{
  "fetchedAt": 1793080000.0,
  "source": "agy /usage",
  "description": "Provider explanation of quota grouping",
  "groups": [
    {
      "name": "Gemini 4 Argon",
      "buckets": [
        {
          "id": "gemini-argon-wtu-weekly",
          "name": "Gemini 4 Argon Weekly Limit",
          "window": "weekly",
          "remaining_fraction": 0.75,
          "reset_time": "2026-11-03T06:03:08Z"
        }
      ]
    }
  ]
}
```

All groups/buckets come from AGY. `remaining_fraction` is the fraction remaining, not used: `0.75` means 75% remains. `reset_time` is the provider's UTC reset timestamp. Do not infer absolute token/request allowances from a percentage. Missing fields mean the provider did not return that value. Accounts may return shared Gemini, shared Claude/GPT and separate Gemini 4 Argon buckets depending on plan. A failed query returns 502 rather than fabricated remaining quota.

## Models and model changes

- `GET /v1/models` returns every canonical CLI model ID and name, including effort variants. `?refresh=1` bypasses the 5-minute cache.
- `PATCH /v1/sessions/{id}` with `{"model":"gemini-4-argon-high"}` switches the model for the next turn without discarding conversation ID or history. A running task returns 409.
- `PATCH /v1/sessions/{id}` with `{"name":"New name"}` renames the gateway history entry.

## Upload and send attachments

1. Create a session with `POST /v1/sessions`, or use an existing session ID.
2. `POST /v1/sessions/{id}/attachments?name=<URL-encoded-filename>` with the raw file bytes, its MIME `Content-Type`, and `Content-Length`. Do not wrap the body in JSON or multipart. Response: `{"id":"uuid","name":"photo.jpg","mime":"image/jpeg","size":12345}`.
3. `POST /v1/sessions/{id}/messages` with `{"text":"Read these files","requestID":"client-generated-uuid","attachments":["attachment-id"]}`. Empty text with one or more attachments is allowed. The upload IDs must belong to this session. Maximum 8 files, 25 MiB each and 50 MiB total per message.

The gateway stores files under the session workspace's `.agy-uploads/{session}/` directory with generated names. It checks real workspace boundaries and opens directories/files without following symlinks. A name cannot overwrite source files or inject a workspace instruction file. Actual paths are attached to the CLI turn so AGY reads the files with its existing image/file tools. The iPhone photo picker normalizes orientation and downsamples to 2048 pixels; arbitrary document bytes are preserved.

Reusing a message request ID with the same text and upload IDs returns the originally admitted message without re-executing it. A different payload under that ID returns 409. Uploads by themselves never invoke a model. Gateway history deletion preserves AGY's own original conversation and its referenced files.

Existing session GET, SSE events, stop and delete endpoints remain compatible with 1.0.x clients. File browsing/download and interactive native tool approvals are separate features and are not included in this upload API.
