## ADDED Requirements

### Requirement: Account login
The system SHALL allow the user to authenticate with an email address and password and establish a session from the returned token.

#### Scenario: Successful login
- **WHEN** the user submits valid credentials and the service returns a token
- **THEN** the system securely stores the token, establishes the authenticated session, and opens the main application

#### Scenario: Rejected login
- **WHEN** the service rejects the submitted credentials
- **THEN** the system remains on the login screen, displays a comprehensible error, and does not retain the password

#### Scenario: Duplicate submission
- **WHEN** a login attempt is already in progress
- **THEN** the system prevents an additional concurrent login submission

### Requirement: Secure session persistence
The system MUST store the session token in Keychain and MUST NOT persist the account password.

#### Scenario: Application restart
- **WHEN** the application starts and a token exists in Keychain
- **THEN** the system restores an authenticated session without requesting the password again

#### Scenario: No stored token
- **WHEN** the application starts without a token in Keychain
- **THEN** the system presents the login flow

### Requirement: Session invalidation
The system SHALL centrally invalidate the session after logout or an authenticated request returns HTTP 401.

#### Scenario: Explicit logout
- **WHEN** the user confirms logout
- **THEN** the system clears the Keychain token, cancels authenticated requests, clears in-memory account state, and returns to login

#### Scenario: Expired token
- **WHEN** an authenticated request returns HTTP 401
- **THEN** the system clears the stored token once and presents the login flow without repeated navigation or alerts

### Requirement: Authentication states
The system SHALL expose explicit restoring, unauthenticated, authenticating, authenticated, and failed states to the UI.

#### Scenario: Restoring session
- **WHEN** the application is checking stored session state
- **THEN** it displays a non-interactive restoration state instead of briefly showing protected content or the login form

#### Scenario: Recoverable network failure
- **WHEN** login fails because the network is unavailable or times out
- **THEN** the system displays a retryable error while preserving only the non-sensitive email input
