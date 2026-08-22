# Changelog

All notable changes to this project are documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org).

<!-- CHANGELOG:ENTRIES -->

## [0.2.3] - 2026-08-22

### Fixed
- brain installer chmods schema.sql so a restrictive umask cannot silently skip database creation


## [0.2.2] - 2026-08-16

### Fixed
- brain installer waits up to 90s for /healthz on re-run instead of a single shot


## [0.2.1] - 2026-08-16

### Fixed
- installers fall back to tarball/zip when git is missing (fresh VPS, fresh Windows)


## [0.2.0] - 2026-08-16

### Added
- add Class 2 brain stack installer (n8n + Postgres) under brain/


## [0.1.1] - 2026-08-14

### Maintenance
- gitignore local session continuity files


## [0.1.0] - 2026-08-14

### Added
- Initial release. Project established with local-git versioning.




