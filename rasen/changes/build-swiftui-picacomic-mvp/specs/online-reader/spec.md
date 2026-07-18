## ADDED Requirements

### Requirement: Chapter image loading
The system SHALL load every image page reported for a selected chapter and preserve the service-defined image order.

#### Scenario: Multi-page image response
- **WHEN** the first chapter image response reports additional pages
- **THEN** the system loads the remaining pages with bounded concurrency and merges their images in page and document order

#### Scenario: One image fails
- **WHEN** an individual image cannot be downloaded or decoded
- **THEN** the reader preserves the surrounding images and provides a retry control for the failed image

### Requirement: Basic vertical reader
The system SHALL provide a vertically scrolling reader for remote chapter images.

#### Scenario: Open chapter
- **WHEN** chapter metadata and at least one image are available
- **THEN** the reader displays images in order and allows continuous vertical scrolling

#### Scenario: No chapter images
- **WHEN** the service returns a valid chapter with no images
- **THEN** the reader presents an empty chapter state and allows navigation back or to another chapter

### Requirement: Bounded image prefetch and cache
The system MUST limit concurrent image work and SHALL prefetch only a configured small number of images ahead of the current position.

#### Scenario: Reader advances
- **WHEN** the visible image position changes
- **THEN** the system prioritizes visible images and prefetches only the bounded look-ahead range

#### Scenario: Reader closes
- **WHEN** the user leaves the reader or changes chapter
- **THEN** image tasks no longer needed by the active reader are cancelled

#### Scenario: Memory pressure
- **WHEN** the operating system reports memory pressure
- **THEN** the system may clear decoded image cache without losing persisted reading progress or crashing

### Requirement: Chapter navigation
The system SHALL allow movement to an available previous or next chapter while preventing navigation beyond the chapter list.

#### Scenario: Next chapter
- **WHEN** the user requests the next chapter and one exists
- **THEN** the system cancels obsolete image work, loads the next chapter, and presents its saved or initial position

#### Scenario: Boundary chapter
- **WHEN** the user is at the first or last available chapter
- **THEN** the unavailable navigation direction is disabled or produces a clear boundary indication

### Requirement: Local reading progress
The system SHALL persist the latest chapter order and image index for each comic in the new application's own storage.

#### Scenario: Resume reading
- **WHEN** the user reopens a comic with saved progress
- **THEN** the system offers or performs a resume to the saved chapter and nearest valid image index

#### Scenario: Stale progress
- **WHEN** saved progress references a chapter or image that no longer exists
- **THEN** the system falls back to a valid available position and replaces the stale progress safely

### Requirement: Reader failure recovery
The reader SHALL distinguish chapter metadata failure, image-list failure, and individual image failure and provide recovery appropriate to each level.

#### Scenario: Image-list request fails
- **WHEN** the chapter image-list request fails
- **THEN** the reader presents a full-content retry state without discarding the selected comic and chapter context

#### Scenario: Retry succeeds
- **WHEN** the user retries a previously failed reader operation and the service succeeds
- **THEN** the reader replaces the corresponding error state with content without duplicating images
