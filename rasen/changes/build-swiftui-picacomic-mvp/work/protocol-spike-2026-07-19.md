# Live Protocol Spike — 2026-07-19

## Environment

- Device: iPhone Air
- OS: iOS 27
- Build: Debug, iOS deployment target 17
- Selected API host: proxy (`picaapi.go2778.com`)
- Credential handling: temporary XCTest environment only; no project file or persistent app storage

## Verified Live Flows

- Login returned a non-empty token and authenticated requests succeeded.
- Categories returned non-empty content.
- Comic list, comic details, all chapter pages, and all chapter-image pages decoded successfully.
- A real reader image downloaded with HTTP 200 and non-empty data.
- Favorite state changed, matched favorite-list readback, and was restored to its original state.

## Verified Client Semantics

- `time`, `signature`, `authorization`, and `image-quality` are isolated per request.
- HMAC-SHA256 signing matches independently generated fixed GET and POST fixtures.
- HTTP 401 invalidates the in-memory session.
- Offline, timeout, and cancellation errors map to their typed client errors.
- Read requests use bounded retry; write requests do not retry ambiguous network failures.

## Protocol Deviation / Compatibility Finding

- Category `_id` is not safe to require. The Swift DTO treats it as optional and derives a local fallback identity from the category title so one incomplete category cannot reject the whole response.
- Debug decoding diagnostics report only the failed coding path and expected type; raw payloads and sensitive values remain excluded.

## Evidence

- Read-only live test: passed in 9.046 seconds.
- Reversible favorite mutation test: passed in 3.881 seconds.
- Offline suite: 18 tests passed; the two credential-gated live tests skip during ordinary credential-free runs.
