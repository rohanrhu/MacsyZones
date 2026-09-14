# Lazy layout lifecycle regression checks

On macOS with the Swift toolchain installed, run from this PR checkout:

```sh
bash scripts/check_lazy_lifecycle.sh
```

The runner extracts `UserLayout`, `startEditing`, `stopEditing`, and
`toggleEditing` from the checked-out production files, including uncommitted
changes. It does not depend on a fork-specific branch or revision. Missing,
duplicate, or out-of-order extraction markers fail the run before Swift starts.
The optional argument selects a separate source root for isolated test fixtures.

The 139 assertions exercise cold zone/grid layouts, nonmaterializing hide and
stop-editing paths, configuration updates, first-show allocation, repeated
show/hide reuse, window cleanup, and independence of unselected layouts.
Window collaborators are lightweight fakes; the production lifecycle code is
not copied into the test fixtures. A temporary combined Swift file is removed
on exit. No application is built or launched, and no preferences are read or
written.

These are source-level model tests, not AppKit integration tests or a memory
benchmark. Real layout editing, dragging, screen changes, snap-resizer behavior,
keyboard interaction, rendering, and process memory still need application-level
validation. Other call sites changed by the PR are outside this harness.
