## 1. Project Setup

- [x] 1.1 Confirm the target device supports iOS 17 and record the selected deployment target
- [x] 1.2 Create an independent SwiftUI application and test target with a new bundle identifier
- [x] 1.3 Establish the feature, domain, repository, infrastructure, and shared source directories described by the design
- [x] 1.4 Configure debug-only diagnostics with mandatory redaction for credentials, tokens, signing material, and sensitive payloads

## 2. Protocol Client Foundations

- [x] 2.1 Define API environments, protocol headers, HTTP methods, endpoint descriptions, and image quality values
- [x] 2.2 Implement final path and query construction with deterministic encoding and parameter ordering
- [x] 2.3 Implement the pure HMAC-SHA256 request signer with an injectable timestamp
- [x] 2.4 Produce trusted fixed-timestamp signature fixtures from the reference client and add exact-match Swift tests
- [x] 2.5 Add URL construction tests for empty queries, multiple parameters, Chinese text, spaces, and pre-existing query strings
- [x] 2.6 Implement an injectable URLSession transport that creates isolated headers for every URLRequest
- [x] 2.7 Implement response envelope decoding and typed transport, cancellation, HTTP, service, authentication, and decoding errors
- [x] 2.8 Add protocol-client tests for success, HTTP 400, HTTP 401, malformed responses, cancellation, and bounded idempotent retry
- [x] 2.9 Define Codable request and response models for login, categories, comics, details, chapters, chapter images, actions, and pagination
- [x] 2.10 Add representative JSON fixture tests, including missing optional fields and malformed required fields
- [x] 2.11 Implement and test the centralized image URL builder, including `/static/` insertion and verified API-route domain behavior

## 3. Live Protocol Spike Gate

- [x] 3.1 Add a local-only mechanism for supplying a real test account without committing credentials
- [x] 3.2 Validate live login and token-authenticated session requests against the selected API host
- [x] 3.3 Validate categories, paginated comics, comic details, and multi-page chapter retrieval
- [x] 3.4 Validate multi-page chapter image retrieval and loading of at least one real cover and one real reader image
- [x] 3.5 Validate favorite mutation and confirm the result through favorite-list readback
- [x] 3.6 Validate HTTP 401 handling, offline behavior, timeout behavior, and request cancellation
- [x] 3.7 Record the validation date, environment, selected host, verified header semantics, and any protocol deviations in the change work directory
- [x] 3.8 Mark the protocol gate passed only after tasks 3.2 through 3.7 succeed; do not begin feature UI tasks while this gate remains incomplete

## 4. Account Session

- [x] 4.1 Implement a Keychain-backed token store and tests for save, restore, delete, and unavailable-Keychain errors
- [x] 4.2 Implement the account repository and explicit restoring, unauthenticated, authenticating, authenticated, and failed states
- [x] 4.3 Implement the login screen with validation, duplicate-submission prevention, progress, and retryable errors
- [x] 4.4 Implement startup session restoration without persisting the password
- [x] 4.5 Implement centralized logout and HTTP 401 invalidation with authenticated-request cancellation
- [x] 4.6 Add account-session unit and UI tests for login success, rejection, restart restoration, logout, and repeated 401 events

## 5. Comic Discovery

- [x] 5.1 Implement the category repository and category screen with loading, content, empty, error, retry, and refresh states
- [x] 5.2 Implement paginated comic browsing with selected category, sort order, duplicate prevention, and bounded next-page loading
- [x] 5.3 Implement comic list cells with cover, title, author, metadata fallbacks, image placeholders, and image retry
- [x] 5.4 Implement cancellable paginated search with empty-keyword validation and no-results state
- [x] 5.5 Implement comic details with independent detail and chapter loading states
- [x] 5.6 Implement complete multi-page chapter retrieval with verified ordering and duplicate prevention
- [x] 5.7 Add discovery repository and UI tests covering pagination, refresh retention, cancellation, empty data, partial failure, and missing optional fields

## 6. Online Reader

- [x] 6.1 Implement chapter image pagination with bounded concurrency, deterministic ordering, cancellation, and duplicate prevention
- [x] 6.2 Implement the two-level image pipeline with URLCache, cost-limited decoded-image cache, and per-image retry
- [x] 6.3 Implement the vertically scrolling reader with visible-image prioritization and bounded look-ahead prefetch
- [x] 6.4 Implement previous and next chapter navigation with boundary handling and obsolete-task cancellation
- [x] 6.5 Implement local reading progress keyed by comic with stale chapter and image fallback
- [x] 6.6 Implement reader-level metadata, image-list, empty-chapter, and individual-image failure states
- [x] 6.7 Add reader tests for image ordering, prefetch bounds, cancellation, retry deduplication, chapter boundaries, progress restoration, and stale progress
- [ ] 6.8 Perform real-device memory testing with long high-resolution chapters and tune cache and prefetch limits

## 7. Online Favorites

- [x] 7.1 Implement the favorite repository for detail state, mutation, and paginated favorite-list retrieval
- [x] 7.2 Implement the detail favorite control with in-flight duplicate prevention and confirmed-state error recovery
- [x] 7.3 Implement the favorites screen with sort, pagination, empty, error, retry, and refresh states
- [x] 7.4 Reconcile confirmed favorite changes between comic details and the favorites list
- [ ] 7.5 Add favorite tests for add, remove, ambiguous failure, repeated taps, pagination, external refresh changes, and session expiry

## 8. Integration and Verification

- [ ] 8.1 Wire account, discovery, details, reader, and favorites into the SwiftUI navigation structure
- [ ] 8.2 Verify deep navigation cancellation and ensure dismissed features cannot receive late state updates
- [ ] 8.3 Run all unit, fixture, repository, and UI tests and record the results
- [ ] 8.4 Run a clean iOS build for the selected simulator and physical device targets
- [ ] 8.5 Perform manual end-to-end validation for login, restart, browse, search, read, favorite, unfavorite, logout, offline, and expired-session flows
- [ ] 8.6 Inspect logs and repository changes for credentials, tokens, signing secrets, generated artifacts, debug code, and unrelated modifications
- [ ] 8.7 Update affected project context, architecture, decisions, TODO, and session documentation with only verified outcomes
