# Demo interaction and preference continuity

Status: implemented and provider verified.

## Capability contract

Synthetic examples should provide a consistent selectable task row, proportional
control graphics, and a shared appearance preference across their static pages.
A primary unmodified click anywhere on a task row selects it and opens its
existing editor. The nested completion control changes completion only. The
native title button remains the keyboard entry point; rows retain table semantics.
Selection must continue after edits, filtering, sorting, reordering and reset.

Theme preference belongs to the example browser layer. Store only `light` or
`dark` in a namespaced localStorage key. Apply it before page rendering and
synchronize the Zig examples through the public runtime dispatch API; task data
remains in Zig and is never persisted. Source has the same theme control.
Unavailable storage must not prevent loading or changing themes. Invalid saved
values fall back to light. Dispose example observers and listeners with the app.
The framework runtime and public ABI do not change.

Control icons use consistent SVG geometry, scale with text, and keep sufficient
space inside their hit targets. Select arrows have explicit trailing padding.
Check desktop, narrow layouts and enlarged text in both themes.

## Acceptance

- Repeated row clicks, nested completion and keyboard selection work with real
  WASM while unaffected DOM nodes and editor focus are retained.
- Navigation and reload retain both theme choices across all three pages;
  blocked storage and invalid values remain usable.
- Inspect screenshots and verify graphic bounds, touch targets, select padding,
  and absence of page overflow at 320, 390, 768 and 1440 pixels with 80–140% text.
- Record checks and any changed artifact sizes after implementation.

## Verification

`zig build test-workspace` passes, including maximal full recovery. All 35 checks
in `npm run test:browser` pass. After refining theme observer ownership, all five
focused usability checks also pass. JavaScript syntax and `git diff --check`
pass. No Zig source or framework runtime changes were needed.

Real-WASM tests cover clicks on status, priority SVG, owner and empty row padding;
keyboard entry; independent completion; selection after edits, filtering, sorting,
reordering and reset; DOM retention and mobile focus return. Theme checks cover
all pages beneath a static subpath, both preferences, reload, backward/forward
navigation, tab synchronization, disposal, invalid preferences and denied storage.
Graphics checks cover square icon bounds, panel clearance, centered 16–28 px
arrows in targets of at least 44 px, select padding and overflow at 320, 390, 768
and 1440 px with 80%, 100% and 140% text. Text contrast checks include Source in
both themes. Fresh screenshots were inspected for desktop, mobile detail editing,
enlarged dark controls, Basics components, and Source.

Workspace WASM is 157,878 bytes (+505); initial HTML is 28,630 bytes (+492).
Initial and observed linear memory remain 917,504 bytes. Reordering emits the
same eight commands / 174 bytes, retaining existing rows. Basics WASM remains
50,849 bytes. Peak stack/heap memory was not profiled. Verification uses desktop
Chromium with emulated viewports; real device keyboards and screen readers were
not assessed. Saved themes require available localStorage; when denied, local
controls still work but preferences cannot survive navigation.
