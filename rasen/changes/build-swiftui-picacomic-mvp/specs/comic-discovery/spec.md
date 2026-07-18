## ADDED Requirements

### Requirement: Category discovery
The system SHALL load and present supported comic categories from the remote service.

#### Scenario: Categories loaded
- **WHEN** the authenticated user opens the discovery area
- **THEN** the system presents supported non-web categories returned by the service

#### Scenario: Category loading failure
- **WHEN** categories cannot be loaded
- **THEN** the system presents an error state with an explicit retry action

### Requirement: Paginated comic browsing
The system SHALL allow the user to browse comics by category and sort order using service pagination.

#### Scenario: Initial comic page
- **WHEN** the user opens a category
- **THEN** the system loads page one and presents comic title, author, cover, and available summary metadata

#### Scenario: Next comic page
- **WHEN** the user reaches the pagination boundary and additional pages exist
- **THEN** the system loads the next page once and appends non-duplicate results

#### Scenario: Empty category
- **WHEN** the service returns a valid page with no comics
- **THEN** the system presents an empty state rather than an error

### Requirement: Comic search
The system SHALL allow the user to search comics with a non-empty keyword and browse paginated results.

#### Scenario: Successful search
- **WHEN** the user submits a non-empty keyword
- **THEN** the system sends the verified search request and displays the first result page

#### Scenario: New search replaces old search
- **WHEN** the user submits a new keyword while an earlier search is in flight
- **THEN** the earlier request is cancelled or ignored and only the newest search updates the UI

#### Scenario: No search results
- **WHEN** a valid search returns no comics
- **THEN** the system presents a dedicated no-results state

### Requirement: Comic details and chapters
The system SHALL display comic details and the complete ordered chapter list for a selected comic.

#### Scenario: Details loaded
- **WHEN** the user selects a comic
- **THEN** the system presents its cover, title, author, description, tags, relevant counts, favorite state, and available chapters

#### Scenario: Multi-page chapter list
- **WHEN** the chapter endpoint reports more than one page
- **THEN** the system loads all chapter pages, merges them without duplicates, and preserves verified chapter order

#### Scenario: Partial details failure
- **WHEN** comic details load but chapters fail
- **THEN** the system keeps the visible details and provides a separate chapter retry action

### Requirement: Discovery loading lifecycle
Every discovery screen SHALL expose loading, content, empty, error, and refresh behavior without crashing on missing optional fields.

#### Scenario: User refresh
- **WHEN** the user refreshes visible discovery content
- **THEN** the system requests fresh data while retaining usable existing content until replacement data succeeds

#### Scenario: Optional field missing
- **WHEN** a response omits an optional metadata field
- **THEN** the system displays the remaining content using an intentional fallback and records no decoding crash
