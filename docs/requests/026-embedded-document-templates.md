# Embedded document templates

Status: provider verified; consumer adoption is separate.

Compile empty iframe elements with a required title and static sandbox policy,
optional visibility and a bound source. Reject child content, text/slot bindings,
inline documents and source bindings on unrelated elements. The frame owns its
external document; local labels and visibility must retain its DOM object.

The default host accepts same-origin HTTP(S) documents and about:blank. External
HTTPS documents require explicit data-external-frame="true" on a sandboxed
frame. Reject credentials and other protocols. Embedding destinations and sandbox
tokens remain application policy. Do not add a document parser or access frame
contents. Verify compiler acceptance/rejection, generated source/visibility leaf
updates, failed output retry and browser frame/sibling identity and focus.

Verification: `npm test` passed (native/compiler/generated tests and 21 Node/
browser tests). The generated retry check covers source and visibility changes;
the browser check retains the frame object and focused sibling input and rejects
unapproved sources. No external document behavior is claimed.
