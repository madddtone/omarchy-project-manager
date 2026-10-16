# Changelog

## 0.1.0

Initial release.

- Overlay project launcher with fuzzy search and per-project actions.
- Shared `service` for scanning/state, plus a bar widget that opens the
  overlay.
- Parallel, cached discovery (`discover.sh`) with git branch/dirty/ahead/behind,
  last commit, and stash count.
- Pinned / Recent / All sections; frecency ranking.
- Persistent editor overrides, pins, and last-opened project.
- Type detection for ~25 stacks and auto-generated tasks from
  package.json/Makefile/justfile/tool markers.
- New-project scaffolding with built-in and user templates.
- Configurable terminal and global custom actions.
- `node --test` unit tests for the pure modules.
