# Security

## Reporting a vulnerability

Please report security problems privately through
[Report a vulnerability](https://github.com/paulshnurenko/free-meeting-transcription/security/advisories/new)
on GitHub, not in a public issue. Describe what an attacker could do and how to reproduce it. You can expect
a first reply within a week.

## Supported versions

Only the latest release gets fixes. Undertone updates itself, so most people run it.

## How releases are protected

- Every app and DMG is signed with a Developer ID certificate and notarized by Apple.
- Updates are delivered by [Sparkle](https://sparkle-project.org), which installs an update only if it is
  signed with the project's EdDSA key. The key is not stored on GitHub, so a tampered release cannot
  update installed copies.
- Undertone sends no audio or transcripts anywhere. Its only network requests are the one-time model
  download from Hugging Face and the update check against this repository's latest release.
