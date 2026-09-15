# Aside child slots

Allow an empty semantic `aside` to delegate its children to a typed slot while
retaining its own visibility, attributes and identity. This avoids inserting a
layout wrapper merely to compose independent projections. Consumers own child
markup validity, membership, capacity, lifetime and patch selection.

Apply existing slot rules: reject text, static children, conditional/loop owners
or competing child bindings. No host or protocol change is required.

Provider verification passed (`npm test`): generated escaping/leaf/retry coverage, compiler
rejection/output preservation and the complete provider test suite (18 Node tests plus native/generated tests). Consumer
adoption remains a separate status.
