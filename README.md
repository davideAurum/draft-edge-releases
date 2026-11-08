# Draft Edge releases

Published builds of **Draft Edge**, a local-first fantasy football draft
workspace for Windows. The source is private; this repository carries the
releases and the update feed only.

- **Install or update:** download the latest setup from
  [Releases](https://github.com/davideAurum/draft-edge-releases/releases).
  An installed copy also updates itself from Help > Check for updates.
- **Alpha:** every release so far is a pre-release. Expect gaps, and keep the
  browser version for a real draft until a release says otherwise.
- **License:** [LICENSE.txt](LICENSE.txt). Free to download, install and use,
  for personal use and for work, on any number of computers.

## latest.json

`latest.json` is the update feed the app reads. It names one release with its
version, notes link, setup and zips, each with a byte count and SHA-256. The
app accepts downloads only from this repository's releases and only when the
size and hash match. It appears with the first published release.
