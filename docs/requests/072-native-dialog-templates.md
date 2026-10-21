# Native dialog elements in compiled templates

Status: verified (native compiler and runtime contracts).

## Contract

Applications need to author accessible native dialogs in the same compiled
templates as their other controls. Admit the standard `dialog` flow element with
ordinary static attributes, refs, text/attribute bindings and child components.
Keep existing HTML nesting, escaping, source limits and event-handler rejection.

The consumer owns the open/closed state, accessible title and description,
confirmation policy, initial/return focus, cancellation and errors. A consumer
host may call `showModal()`/`close()` in response to an ordinary `data-*` binding.
Compilation must not add modal behavior, automatically focus a control or manage
the browser top layer. This capability changes no DOM protocol or runtime API.

## Acceptance

- [x] A dialog with named refs, an escaped text binding and data-state binding
  compiles with generated stable references and the existing projection bindings.
- [x] Inline event handlers and malformed table nesting remain rejected.
- [x] Native compiler and generated-template checks pass.

Application accessibility and modal lifecycle acceptance remain consumer-owned.

Verification: `zig build test-templates test` passes. No browser-host behavior
changed. Modal lifecycle, keyboard and focus acceptance must be checked by each
consumer when adopting this element.
