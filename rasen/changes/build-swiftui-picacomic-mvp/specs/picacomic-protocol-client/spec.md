## ADDED Requirements

### Requirement: Canonical request signing
The system MUST generate every authenticated API request signature from the final encoded request target, request timestamp, configured nonce, HTTP method, and configured API identity using the protocol's HMAC-SHA256 algorithm.

#### Scenario: Signed GET request with query parameters
- **WHEN** an endpoint builds a GET request containing multiple query parameters
- **THEN** the system signs the same encoded path and query string that is sent on the wire, preserving the verified encoding and parameter order

#### Scenario: Signed write request
- **WHEN** an endpoint builds a POST, PUT, or DELETE request
- **THEN** the system signs the verified request target and method without incorporating an unverified body representation

#### Scenario: Signature fixture compatibility
- **WHEN** the signer is evaluated with a fixed timestamp and a reference request fixture
- **THEN** the generated signature MUST exactly match the trusted reference signature

### Requirement: Isolated request construction
The system SHALL create an independent URLRequest for every operation with protocol headers, authorization, timeout, body, and image quality scoped to that request.

#### Scenario: Concurrent requests
- **WHEN** two requests with different paths or timestamps execute concurrently
- **THEN** each request retains its own correct signature and headers without shared mutable header state

#### Scenario: Sensitive logging
- **WHEN** request or response diagnostics are recorded
- **THEN** passwords, tokens, authorization headers, signing secrets, and complete sensitive payloads MUST NOT be logged

### Requirement: Typed response and error handling
The system SHALL decode successful envelopes into endpoint-specific models and map transport, cancellation, HTTP, service, authentication, and decoding failures into distinguishable application errors.

#### Scenario: Successful response
- **WHEN** the service returns a successful response matching the expected envelope
- **THEN** the system returns the decoded domain model to the calling repository

#### Scenario: Authentication failure
- **WHEN** the service returns HTTP 401
- **THEN** the system emits a session-expired error and triggers centralized session invalidation

#### Scenario: Malformed response
- **WHEN** a successful HTTP response lacks required envelope or model fields
- **THEN** the system returns a decoding error without crashing or fabricating successful data

### Requirement: Bounded retry and cancellation
The system MUST support cancellation and SHALL retry only verified idempotent operations within a bounded policy.

#### Scenario: Cancelled navigation request
- **WHEN** a feature is dismissed or replaced while its request is in flight
- **THEN** the request is cancelled and its late result does not update the dismissed feature

#### Scenario: Failed write request
- **WHEN** a login or favorite mutation fails due to an ambiguous network error
- **THEN** the system does not automatically repeat the mutation without an explicit verified policy

### Requirement: Protocol validation gate
The system MUST NOT treat the protocol client as implementation-ready until the end-to-end Spike validates every critical MVP operation against the live service.

#### Scenario: Complete Spike
- **WHEN** login, categories, comic list, details, chapters, chapter image pagination, favorite mutation, favorite list readback, 401, offline handling, and cancellation all pass
- **THEN** the protocol gate is marked passed with the validation date and tested environment

#### Scenario: Incomplete Spike
- **WHEN** any critical operation remains failing or unexplained
- **THEN** feature UI implementation remains blocked and the failure is recorded as unresolved
