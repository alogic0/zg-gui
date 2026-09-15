# Local navigation link bindings

Compile `<a href="$path">` to a checked local-link leaf. Accept root-relative
paths beginning with one slash and ASCII URI path/query/fragment characters.
Reject protocols, network-path references, backslashes, whitespace and raw
markup. Consumers encode other characters, own routes and handle navigation.
SVG `use` references retain their existing fragment validation.

Invalid values fail the candidate writer before publishing the href attribute.
Callers publish neither HTML nor command buffers marked failed. Updates must
retain the anchor and focused siblings. Provider verification: `npm test` passed native/generated/compiler checks and
17 Node tests (including DOM identity/focus regressions);
consumer adoption is independent.
