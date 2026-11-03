# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2026-11-03

### Added
- Configurable word wrapping and measured node/header/note heights.
- Flowchart self-links and separate routes for parallel and opposite links.
- Workflow regression coverage for long labels, cycles and 72-node graphs.

### Fixed
- Emit each logical long-edge label once after dummy insertion.
- Keep sequence notes and self-message labels inside the scene bounds.
- Measure event rows and activation endpoints from one stored timeline.

## [0.8.3] - 2026-11-03

### Fixed
- Close the sender activation for a reply using the inline deactivation modifier.

## [0.8.2] - 2026-11-03

### Fixed
- Preserve original arrow direction and link paint after cycle breaking and dummy insertion.
- Attach bottom-to-top and right-to-left edges to their facing node ports.

## [0.8.1] - 2026-11-03

### Fixed
- Paint sequence activation bars before messages and notes so labels stay visible.

## [0.8.0] - 2026-11-03

### Added
- Shared typed drawing visitors for flowchart and sequence layouts.
- Owned, bounded scenes with copied geometry, labels and semantic identities.
- Scene-to-SVG replay using the same drawing calculations as direct export.
- A circle arrowhead definition for existing circle links.

### Fixed
- Release partially initialized layers and crossing snapshots on allocation failure.

## [0.1.0] - 2026-10-09

### Added
- Initial project architecture and implementation plan.
- Standalone build system and package version tool.
- Initial module root and verification pipeline.
