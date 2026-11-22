# Security policy

This repository is an early proof of concept. Only the latest release is
supported. Do not use it to handle untrusted input or sensitive data.

Report a vulnerability privately with GitHub's **Security → Report a
vulnerability** for this repository. Do not put credentials, exploit details or
private data in a public issue. Ordinary bugs belong in the issue tracker.

Include the release or commit, the impact, steps to reproduce, and relevant logs with
credentials removed. The maintainer assesses the report and coordinates the
fix and its disclosure through the private report. The aim is to respond
within 14 days.

A fix lands on the default branch. Releases are immutable: a fix ships in a new
release rather than a patch to an old one. Each release's files carry a
build-provenance attestation (`gh attestation verify <file> --repo
lukewilliamboswell/roc-native-macos`) and the bundle carries SBOM documents.
