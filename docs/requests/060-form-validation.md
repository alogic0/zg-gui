# Request 060: Declarative form validation and dirty tracking

Status: implemented; declarative form validation directives (:invalid, :error-id) and DOM dirty/touched state tracking with accessibility synchronization.

## Reusable problem

Forms are the primary vector for user data entry and mutation across business applications.
Currently, coordinating validation states between the client DOM and backend/WASM models requires
repetitive manual boilerplate across components:
1. **Premature Validation Errors**: Showing aggressive error styling or messages on clean, untouched
   inputs before the user has even focused or typed anything frustrates users.
2. **Accessibility Desynchronization**: Missing or out-of-sync `aria-invalid` and `aria-describedby`
   attributes disconnect screen readers from visual error banners.
3. **Pristine / Dirty State Ambiguity**: Applications cannot easily differentiate whether an input holds
   an edited draft (`dirty`) or the original server value (`pristine`), complicating "discard unsaved changes"
   prompts.

This request delivers declarative form validation and interaction tracking in `zg-gui`, providing
automatic dirty/touched state tracking, `aria-invalid` coordination, and declarative error message linking.

## Required contract

1. **Declarative Validation Directives**:
   - Template inputs and form controls admit declarative validation bindings:
     ```html
     <label for="email">Email address</label>
     <input id="email" :input="$email" :invalid="$errors.email" :error-id="email-error">
     <span id="email-error" :text="$errors.email" :visible="$errors.email"></span>
     ```
   - Emits `aria-invalid="true"` when `:invalid` evaluates to true (or non-empty string), and
     automatically attaches `aria-describedby="email-error"`.

2. **Automatic Dirty & Touched State Tracking**:
   - The DOM host (`web/dom.js` / `web/runtime.js`) tracks user interaction lifecycle on all form controls:
     - **Pristine**: Initial mounted state (`data-pristine="true"`).
     - **Dirty**: Once the user emits an `input` or `change` event (`data-dirty="true"`).
     - **Touched**: Once the user triggers a `blur` or focus departure (`data-touched="true"`).
   - These data attributes allow CSS stylesheets to target `:invalid` states only when touched:
     ```css
     input[data-touched="true"][aria-invalid="true"] {
       border-color: var(--color-error);
     }
     ```

3. **Zero Heap Allocation in Zig Engine**:
   - Error messages, validity flags, and error IDs are evaluated as string slices and Booleans
     within existing snapshot slots with zero runtime heap allocation.

4. **Form Submission Interception & Focus Handover**:
   - When a `<button :on-click="$submit">` or form submission occurs with invalid controls,
     the DOM host can focus the first invalid field (`operation === "F"`), ensuring accessibility compliance.

## Acceptance checklist

- [x] Specify compiler grammar and validation for `:invalid` and `:error-id` directives.
- [x] Implement automatic `data-dirty` and `data-touched` tracking on blur/input events in `web/dom.js`.
- [x] Implement `aria-invalid` and `aria-describedby` synchronization on `:invalid` patches.
- [x] Verify zero runtime heap allocation during form validation in Zig models.
- [x] Verify focus preservation and caret stability while typing in validated fields.
- [x] Add browser tests exercising touched/dirty lifecycle and accessibility attributes (Chromium & Firefox).
- [x] Ensure 100% test pass across `zg-gui`.

