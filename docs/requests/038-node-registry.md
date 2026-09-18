# Indexed DOM target resolution

Provide a public browser node registry for an owned root. Resolve typed numeric
IDs without a document-wide selector for each command. Index full initialization,
inserted and removed subtrees, text replacement, moves, and resynchronization.
Reject missing, duplicate and disconnected targets. Observe external structural
or identity changes and drain pending observations synchronously before lookup,
so same-task mutations cannot bypass validation. Observation maintains identity
only and must not infer product state or choose patches.

The root owns the registry and observer lifetime. Disposal disconnects observers
and releases strong references. Existing DOM host initialize/patch operations
must use the registry; preserve typed validation, focus and unaffected owners.
Test native DOM behavior, including duplicate recovery and removal/reuse of IDs.

Provider verification: 19 real-browser DOM tests passed, including structural
replacement, text descendant removal, ID reuse, same-task and later duplicates,
external identity changes, focus retention and full resync. A 100-command leaf
stream performs no root-wide lookup after initialization. Consumer integration
and application acceptance remain separate.
