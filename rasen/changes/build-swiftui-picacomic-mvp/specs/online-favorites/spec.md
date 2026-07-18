## ADDED Requirements

### Requirement: Favorite state visibility
The system SHALL show the service-reported favorite state on comic details.

#### Scenario: Favorite comic details
- **WHEN** comic details report the comic as favorited
- **THEN** the favorite control displays the active state

#### Scenario: Non-favorite comic details
- **WHEN** comic details report the comic as not favorited
- **THEN** the favorite control displays the inactive state

### Requirement: Favorite mutation
The system SHALL allow the authenticated user to favorite or unfavorite a comic using the remote mutation endpoint.

#### Scenario: Successful favorite
- **WHEN** the user activates favorite on a non-favorite comic and the service confirms success
- **THEN** the detail state changes to favorited and the comic becomes eligible to appear in the favorite list

#### Scenario: Successful unfavorite
- **WHEN** the user removes favorite from a favorited comic and the service confirms success
- **THEN** the detail state changes to not favorited and subsequent favorite-list refresh excludes the comic

#### Scenario: Mutation failure
- **WHEN** a favorite mutation fails or its result is ambiguous
- **THEN** the system does not claim a confirmed new state, displays a retryable error, and allows the user to refresh server state

#### Scenario: Repeated tap
- **WHEN** a favorite mutation is in progress
- **THEN** the system prevents another mutation for the same comic until the first operation completes

### Requirement: Paginated favorite list
The system SHALL present the authenticated user's remote favorites using service pagination and selected sort order.

#### Scenario: Initial favorites page
- **WHEN** the user opens favorites
- **THEN** the system loads page one and displays the returned comics

#### Scenario: Additional favorites page
- **WHEN** more favorite pages exist and the user reaches the pagination boundary
- **THEN** the system loads the next page once and appends non-duplicate comics

#### Scenario: No favorites
- **WHEN** the service returns an empty valid favorite page
- **THEN** the system presents an empty favorites state rather than an error

### Requirement: Favorite consistency
The system SHALL reconcile detail and list favorite state with confirmed service responses.

#### Scenario: Return from successful unfavorite
- **WHEN** a comic is unfavorited from details and the user returns to the favorites list
- **THEN** the list refreshes or removes that confirmed item without requiring an application restart

#### Scenario: External state change
- **WHEN** a refresh returns a favorite state different from local cached state
- **THEN** the system adopts the latest confirmed server state
