# Request 062: ARIA Live Regions

Status: implemented; declarative ARIA live region directive (:live) coordinating screen-reader announcement updates with DOM patch streams.

## Reusable Problem

Single-page applications frequently perform asynchronous background operations (e.g. saving drafts, receiving notifications, updating status indicators, streaming toasts).
Without managed announcement channels:
1. **Silent Updates**: Screen readers do not announce status changes that occur outside the active focus area.
2. **Announcement Truncation**: High-frequency DOM mutations can cancel in-flight announcements or cause screen readers to speak stale fragments.
3. **Manual Boilerplate**: Developers must repeatedly hand-code `aria-live`, `aria-atomic`, and `role="status"` attributes across templates.

This request introduces declarative live region management into `zg-gui`.

## Required Contract

1. **Declarative Directive**:
   - Elements declare their announcement urgency via `:live="polite|assertive"`:
     ```html
     <div :live="polite" :text="$status"></div>
     <div role="alert" :live="assertive" :text="$error_alert"></div>
     ```
   - Emits `aria-live="polite"` (or `assertive`) and `aria-atomic="true"`.
   - The compiler rejects unsupported values at compile time.

2. **Stream Synchronization**:
   - When text patches (`T` or `H` operations) update the content of an active live region, the DOM host ensures the element's text update is reliably picked up by accessibility APIs without stuttering.

3. **Zero Heap Allocation**:
   - The live region mode is compiled into static attributes or typed bindings with zero dynamic runtime allocation.

## Acceptance Checklist

- [x] Specify compiler grammar and code generation for `:live="polite|assertive"`.
- [x] Emit `aria-live` and `aria-atomic="true"` on matching template elements.
- [x] Validate reject cases for invalid live levels (e.g. `:live="loud"`).
- [x] Verify multi-engine browser compliance across Chromium and Firefox.
