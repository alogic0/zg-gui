# Native field constraint bindings

Status: provider verified; consumer adoption is separate.

Schema-driven forms need required and minimum/maximum/step attributes without
replacing their controls. Accept Boolean required on input/select/textarea and
optional string or integer min/max/step on input. Keep input types static; caller
validation owns the meaning of constraints and browser constraint validation is
supplemental. Reject these dynamic attributes on unrelated elements. Preserve
focused controls, support attribute removal and retry rejected output.

Verification: `npm test` passed, including generated constraint updates/removal,
failed output retry, invalid element rejection and 22 Node/browser tests. The
focused number-input fixture retains its DOM object and draft across updates.
