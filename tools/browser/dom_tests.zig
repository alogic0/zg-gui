//! Native browser DOM host test suite for zg-gui.
//! Ports tests from tests/dom.test.mjs, tests/datetime.test.mjs, and tests/template-dom.test.mjs.
const std = @import("std");
const harness = @import("../browser_harness.zig");
const Harness = harness.Harness;

test "browser datetime: canonical instants round trip local formatting" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { localDatetime, instantFromLocal, localTimeLabel } = await import('/local-datetime.js');
        \\const instant = '2026-09-14T12:34:56.123Z';
        \\assert.equal(instantFromLocal(localDatetime(instant)), instant);
        \\assert.equal(instantFromLocal('not a date'), 'invalid-local-time');
        \\assert.equal(localTimeLabel('<plain>', { format: 'plain' }), '<plain>');
        \\return true;
    );
}

test "browser dom: DOM host retains controls and validates typed patch commands" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<section data-node-id="1"><input data-node-id="2" value="draft"><span data-node-id="3">one</span><input data-node-id="4" type="checkbox"></section><ul data-node-id="5"><li data-node-id="6"><input data-node-id="7" value="row"></li><li data-node-id="8">other</li></ul>');
        \\const selectRoot = document.createElement('div'); document.body.append(selectRoot);
        \\const selects = createDomHost({ root: selectRoot });
        \\selects.initialize('<select data-node-id="1" data-select-value="b"><option data-node-id="2" value="a">b</option><option data-node-id="3" value="b">B</option></select>');
        \\const controlled = selectRoot.querySelector('select');
        \\selects.applyPatchStream('A\t2\tvalue\tb\nD\t3\n');
        \\if (controlled.value !== 'b') throw new Error('option value update lost controlled selection');
        \\selects.applyPatchStream('R\t2\tvalue\n');
        \\if (controlled.value !== 'b') throw new Error('option fallback text lost controlled selection');
        \\selectRoot.remove();
        \\const owner = root.firstElementChild;
        \\const input = root.querySelector('[data-node-id="2"]');
        \\input.focus(); input.setSelectionRange(1, 3);
        \\dom.applyPatchStream('T\t3\t"two\\n🧭"\nA\t3\taria-label\tlabel\nC\t4\ttrue\n');
        \\const retained = owner === root.firstElementChild && input.isConnected && document.activeElement === input && input.selectionStart === 1 && input.selectionEnd === 3;
        \\dom.applyPatchStream('A\t3\tdraggable\ttrue\n');
        \\const dragHandle = root.querySelector('[data-node-id="3"]');
        \\if (!dragHandle.draggable) throw new Error('drag eligibility was not applied');
        \\dom.applyPatchStream('A\t3\tdraggable\tfalse\n');
        \\if (dragHandle.draggable || dragHandle.getAttribute('draggable') !== 'false') throw new Error('false drag value was not retained');
        \\dom.applyPatchStream('R\t3\tdraggable\n');
        \\if (dragHandle.hasAttribute('draggable') || dragHandle !== root.querySelector('[data-node-id="3"]') || input !== document.activeElement || owner !== root.firstElementChild) throw new Error('drag update changed controls or focus');
        \\const row = root.querySelector('[data-node-id="6"]');
        \\const rowInput = row.firstElementChild; rowInput.focus();
        \\dom.applyPatchStream('J\t5\t"<li data-node-id=\\"9\\">new</li>"\nM\t6\t8\tafter\nD\t9\n');
        \\const moved = row.isConnected && document.activeElement === rowInput && root.querySelector('[data-node-id="5"]').lastElementChild === row;
        \\dom.applyPatchStream('V\t2\t"updated"\nA\t3\thidden\t\nR\t3\thidden\nF\t2\tend\n');
        \\const focused = document.activeElement === input && input.selectionStart === 7;
        \\let rejected = 0;
        \\for (const stream of ['T\t999\t"absent"\n', 'A\t3\tonclick\tevil\n', 'C\t3\ttrue\n', 'H\t3\t42\n', 'M\t6\t3\tafter\n', 'A\t3\thref\tjavascript:alert(1)\n']) {
        \\  try { dom.applyPatchStream(stream); } catch { rejected++; }
        \\}
        \\dom.applyPatchStream('J\t5\t"<input data-node-id=\\"20\\" type=\\"datetime-local\\" data-value-format=\\"instant-local\\" data-initial-value=\\"2026-09-14T12:00:00Z\\">"\n');
        \\const dateFormatted = root.querySelector('[data-node-id="20"]').value.length > 0;
        \\dom.applyPatchStream('H\t3\t"<span data-node-id=\\"2\\">duplicate</span>"\n');
        \\try { dom.applyPatchStream('T\t2\t"ambiguous"\n'); } catch { rejected++; }
        \\assert.deepEqual({ retained, moved, focused, dateFormatted, checked: root.querySelector('[data-node-id="4"]').checked, rejected }, { retained: true, moved: true, focused: true, dateFormatted: true, checked: true, rejected: 7 });
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: table section patches retain table header row controls and focus" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<button data-node-id="1">Refresh</button><table data-node-id="2"><thead data-node-id="3"><tr><th>Label</th><th>Draft</th></tr></thead><tbody data-node-id="4"><tr data-node-id="5"><td data-node-id="6">One</td><td><input data-node-id="7" value="keep"></td></tr></tbody></table>');
        \\const table = root.querySelector('table'), head = table.tHead, body = table.tBodies[0], row = body.rows[0], input = root.querySelector('input'), button = root.querySelector('button');
        \\input.focus(); dom.applyPatchStream('T\t6\t"Changed"\n');
        \\const cell = row.cells[0];
        \\dom.applyPatchStream('A\t6\tcolspan\t2\nA\t6\trowspan\t3\n');
        \\const spans = cell === row.cells[0] && cell.colSpan === 2 && cell.rowSpan === 3 && input === document.activeElement && input.value === 'keep';
        \\dom.applyPatchStream('R\t6\trowspan\n');
        \\if (!spans || cell.hasAttribute('rowspan')) throw new Error('cell span patch replaced or blurred peers');
        \\const scalar = body.rows[0] === row && input === document.activeElement && input.value === 'keep';
        \\button.focus(); dom.applyPatchStream('H\t4\t' + JSON.stringify('<tr data-node-id="8"><td data-node-id="9">Two</td><td>Read only</td></tr>') + '\n');
        \\const structure = table === root.querySelector('table') && head === table.tHead && body === table.tBodies[0] && body.rows.length === 1 && body.rows[0].cells.length === 2 && button === document.activeElement && !row.isConnected;
        \\const ids = [...root.querySelectorAll('[data-node-id]')].map(n => n.dataset.nodeId);
        \\assert.deepEqual({ scalar, structure, unique: new Set(ids).size === ids.length }, { scalar: true, structure: true, unique: true });
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: select option replacement retains owner focus and controlled selection" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<section data-node-id="1"><select data-node-id="2" data-select-value="b"><option value="a">A</option><option value="b">B</option></select><input data-node-id="3" value="draft"></section>');
        \\const panel = root.firstChild, select = panel.querySelector('select'), peer = panel.querySelector('input');
        \\select.focus();
        \\dom.applyPatchStream('H\t2\t' + JSON.stringify('<option value="a">A</option>') + '\n');
        \\if (select.value !== '' || document.activeElement !== select) throw new Error('select focus lost');
        \\dom.applyPatchStream('H\t2\t' + JSON.stringify('<option value="b">B</option><option value="c">C</option>') + '\n');
        \\assert.ok(root.firstChild === panel && select === panel.querySelector('select') && document.activeElement === select && select.value === 'b' && peer === panel.querySelector('input') && peer.value === 'draft');
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: multiple selection retains focus and synchronizes option selected states" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const { declaredInputValue } = await import('/local-datetime.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<section data-node-id="1"><select multiple data-node-id="2" data-select-values="a\x1fc"><option value="a">A</option><option value="b">B</option><option value="c">C</option></select><input data-node-id="3" value="peer"></section>');
        \\const panel = root.firstChild, select = panel.querySelector('select'), options = select.options;
        \\select.focus();
        \\assert.ok(options[0].selected && !options[1].selected && options[2].selected && document.activeElement === select);
        \\assert.equal(declaredInputValue(select), 'a\x1fc');
        \\dom.applyPatchStream('A\t2\tdata-select-values\tb\x1fc\n');
        \\assert.ok(!options[0].selected && options[1].selected && options[2].selected && document.activeElement === select);
        \\assert.equal(declaredInputValue(select), 'b\x1fc');
        \\dom.applyPatchStream('H\t2\t' + JSON.stringify('<option value="b">B</option><option value="c">C</option><option value="d">D</option>') + '\n');
        \\assert.ok(options[0].selected && options[1].selected && !options[2].selected && document.activeElement === select);
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: explicit radio values retain choice payload, identity and focus" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const { declaredInputValue } = await import('/local-datetime.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<fieldset data-node-id="1"><input type="radio" name="range" value="one" data-input-kind="2" data-value-format="value" data-node-id="2" checked><input type="radio" name="range" value="all" data-input-kind="2" data-value-format="value" data-node-id="3"><input type="checkbox" data-value-format="checked" data-node-id="4"></fieldset>');
        \\const owner = root.firstElementChild, one = root.querySelector('[value="one"]'), all = root.querySelector('[value="all"]');
        \\const values = [];
        \\root.addEventListener('change', event => values.push(declaredInputValue(event.target)));
        \\all.focus(); all.click();
        \\dom.applyPatchStream('C\t2\tfalse\nC\t3\ttrue\n');
        \\const retained = all === root.querySelector('[value="all"]') && all.isConnected && all === document.activeElement && owner === root.firstElementChild;
        \\one.click();
        \\root.querySelector('[type="checkbox"]').click();
        \\assert.deepEqual({ values, retained, oneChecked: one.checked, allChecked: all.checked }, { values: ['all', 'one', 'true'], retained: true, oneChecked: true, allChecked: false });
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: numeric style and scroll leaves retain scroller and focused sibling" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const css = document.createElement('style');
        \\css.textContent = '.viewport{height:100px;overflow:auto}.spacer{height:calc(var(--extent)*1px)}';
        \\document.head.append(css);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<input data-node-id="1" value="draft"><div class="viewport" data-node-id="2" data-scroll-top="0"><div class="spacer" data-node-id="3" data-style-vars="--extent:400;--offset:4px;--opacity:100%"></div></div>');
        \\const input = root.firstChild, viewport = root.lastChild, spacer = viewport.firstChild;
        \\input.focus();
        \\dom.applyPatchStream('A\t3\tdata-style-vars\t--extent:800;--offset:-12px;--opacity:80%\nA\t2\tdata-scroll-top\t500\n');
        \\assert.ok(input === document.activeElement && input.value === 'draft' && viewport === root.lastChild && spacer === viewport.firstChild && spacer.getBoundingClientRect().height === 800 && viewport.scrollTop === 500 && spacer.style.getPropertyValue("--offset") === "-12px" && spacer.style.getPropertyValue("--opacity") === "80%");
        \\dom.dispose(); root.remove(); css.remove();
        \\return true;
    );
}

test "browser dom: clearing optional styles removes only declared properties and retains focus" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<section><input value="draft"><div data-node-id="1" data-style-vars="--gap:12px;--opacity:80%"><span data-style-vars="--gap:3px"></span></div></section>');
        \\const parent = root.firstElementChild, input = parent.firstElementChild;
        \\const target = parent.lastElementChild, child = target.firstElementChild;
        \\target.style.setProperty('--unrelated', '7');
        \\input.focus(); input.setSelectionRange(1, 3);
        \\dom.applyPatchStream('R\t1\tdata-style-vars\nR\t1\tdata-style-vars\n');
        \\const cleared = !target.hasAttribute('data-style-vars') && target.style.getPropertyValue('--gap') === '' && target.style.getPropertyValue('--opacity') === '';
        \\dom.applyPatchStream('A\t1\tdata-style-vars\t--gap:4px;--opacity:50%\n');
        \\assert.deepEqual({
        \\  cleared,
        \\  restored: target.style.getPropertyValue('--gap') === '4px' && target.style.getPropertyValue('--opacity') === '50%',
        \\  unrelated: target.style.getPropertyValue('--unrelated') === '7' && child.style.getPropertyValue('--gap') === '3px',
        \\  retained: root.firstElementChild === parent && parent.lastElementChild === target && target.firstElementChild === child && parent.firstElementChild === input && document.activeElement === input && input.value === 'draft' && input.selectionStart === 1 && input.selectionEnd === 3,
        \\}, { cleared: true, restored: true, unrelated: true, retained: true });
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: image source updates retain image and focused sibling" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<input data-node-id="1" value="draft"><img data-node-id="2" alt="Preview" src="/one.png">');
        \\const input = root.firstChild, image = root.lastChild;
        \\input.focus();
        \\dom.applyPatchStream('A\t2\tsrc\t/two.png\n');
        \\assert.equal(image.getAttribute('src'), '/two.png');
        \\dom.applyPatchStream('R\t2\tsrc\n');
        \\assert.ok(image === root.lastChild && !image.hasAttribute('src') && input === document.activeElement && input.value === 'draft');
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: description value child updates retain semantic owners and sibling focus" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<dl data-node-id="1"><dt data-node-id="2">Value</dt><dd data-node-id="3"><span data-node-id="4">Before</span></dd><dt>Draft</dt><dd><input data-node-id="5" value="keep"></dd></dl>');
        \\const list = root.firstChild, term = list.firstChild, value = list.querySelector('dd'), text = value.firstChild, peer = list.querySelector('input');
        \\peer.focus(); peer.setSelectionRange(1, 3);
        \\dom.applyPatchStream('T\t4\t"After"\n');
        \\assert.ok(root.firstChild === list && list.firstChild === term && value.isConnected && value.firstChild === text && text.textContent === 'After' && peer === document.activeElement && peer.value === 'keep' && peer.selectionStart === 1 && peer.selectionEnd === 3);
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: option group leaf and membership changes preserve focused select" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const host = createDomHost({ root });
        \\host.initialize('<select data-node-id="1" data-select-value="b"><optgroup data-node-id="2" label="Choices"><option data-node-id="3" value="b">Before</option></optgroup></select><input>');
        \\const select = root.firstElementChild, group = select.firstElementChild, option = group.firstElementChild, peer = root.lastElementChild;
        \\select.focus();
        \\host.applyPatchStream('T\t3\t"After"\nA\t3\tdisabled\t\n');
        \\assert.ok(group.firstElementChild === option && select.value === 'b');
        \\host.applyPatchStream('H\t2\t' + JSON.stringify('<option value="a">A</option><option value="b">B</option>') + '\n');
        \\assert.ok(root.firstElementChild === select && select.firstElementChild === group && root.lastElementChild === peer && select.value === 'b' && document.activeElement === select);
        \\host.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: meter changes retain a focused sibling and reject out-of-range values" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const host = createDomHost({ root });
        \\host.initialize('<section><meter data-node-id="1" min="0" max="100" value="0"></meter><input value="draft"></section>');
        \\const panel = root.firstElementChild, meter = panel.firstElementChild, peer = panel.lastElementChild;
        \\peer.focus(); peer.setSelectionRange(1, 3);
        \\host.applyPatchStream('A\t1\tvalue\t100\n');
        \\let rejected = 0;
        \\for (const value of ['-1', '101', 'NaN', 'Infinity']) {
        \\  try { host.applyPatchStream('A\t1\tvalue\t' + value + '\n'); } catch { rejected++; }
        \\}
        \\assert.ok(rejected === 4 && meter.value === 100 && root.firstElementChild === panel && panel.firstElementChild === meter && document.activeElement === peer && peer.selectionStart === 1 && peer.selectionEnd === 3);
        \\host.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: navigation leaves retain the nav, focused button and sibling selection" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<nav aria-label="Sections" data-node-id="1"><button data-node-id="2">Before</button></nav><input value="draft" data-node-id="3">');
        \\const nav = root.firstChild, button = nav.firstChild, peer = root.lastChild;
        \\button.focus();
        \\dom.applyPatchStream('T\t2\t"After"\nA\t2\taria-current\tpage\n');
        \\const buttonRetained = nav === root.firstChild && button === nav.firstChild && button === document.activeElement && button.textContent === 'After';
        \\peer.focus(); peer.setSelectionRange(1, 3);
        \\dom.applyPatchStream('R\t2\taria-current\n');
        \\assert.ok(buttonRetained && nav === root.firstChild && button === nav.firstChild && nav.isConnected && peer === document.activeElement && peer.value === 'draft' && peer.selectionStart === 1 && peer.selectionEnd === 3);
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: roving tab index leaves retain both controls and current focus" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<div data-node-id="1"><button data-node-id="2" tabindex="0">First</button><button data-node-id="3" tabindex="-1">Second</button></div>');
        \\const parent = root.firstChild, first = parent.firstChild, second = parent.lastChild;
        \\first.focus();
        \\dom.applyPatchStream('A\t2\ttabindex\t-1\nA\t3\ttabindex\t0\n');
        \\assert.ok(parent === root.firstChild && first === parent.firstChild && second === parent.lastChild && first === document.activeElement && first.tabIndex === -1 && second.tabIndex === 0);
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: fractional progress changes retain a focused sibling and reject out-of-range values" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const host = createDomHost({ root });
        \\host.initialize('<section><progress data-node-id="1" max="100" value="0.25"></progress><input value="draft"></section>');
        \\const panel = root.firstElementChild, meter = panel.firstElementChild, peer = panel.lastElementChild;
        \\peer.focus(); peer.setSelectionRange(1, 3);
        \\host.applyPatchStream('A\t1\tvalue\t99.75\n');
        \\let rejected = 0;
        \\for (const value of ['-1', '101', 'NaN', 'Infinity']) {
        \\  try { host.applyPatchStream('A\t1\tvalue\t' + value + '\n'); } catch { rejected++; }
        \\}
        \\host.applyPatchStream('A\t1\tmax\t250.5\nA\t1\tvalue\t200.25\n');
        \\host.applyPatchStream('A\t1\tmax\t0.75\nA\t1\tvalue\t0.5\n');
        \\assert.ok(rejected === 4 && meter.value === 0.5 && meter.max === 0.75 && root.firstElementChild === panel && panel.firstElementChild === meter && document.activeElement === peer && peer.selectionStart === 1 && peer.selectionEnd === 3);
        \\host.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: sandboxed frame sources retain the document owner and sibling focus" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<input data-node-id="1" value="draft"><iframe data-node-id="2" title="Preview" sandbox="" src="about:blank"></iframe>');
        \\const input = root.firstChild, frame = root.lastChild;
        \\input.focus();
        \\dom.applyPatchStream('A\t2\tsrc\t/frame-one\nA\t2\thidden\t\nR\t2\thidden\n');
        \\for (const source of ['javascript:alert(1)', 'data:text/html,test', 'https://external.test/frame-one', 'https://name:secret@external.test/frame-one']) {
        \\  let rejected = false;
        \\  try { dom.applyPatchStream(`A\t2\tsrc\t${source}\n`); } catch { rejected = true; }
        \\  if (!rejected) throw new Error('insecure frame source was not rejected');
        \\}
        \\frame.setAttribute('data-external-frame', 'true');
        \\dom.applyPatchStream('A\t2\tsrc\thttps://external.test/frame-two\nA\t2\tsrc\tabout:blank\n');
        \\assert.ok(frame === root.lastChild && frame.isConnected && input === document.activeElement && input.value === 'draft' && frame.getAttribute('src') === 'about:blank');
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: native constraints preserve a focused input and its draft" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<input data-node-id="1" type="number" value="12" max="20">');
        \\const input = root.firstChild; input.focus();
        \\dom.applyPatchStream('A\t1\trequired\t\nA\t1\tmin\t5\nR\t1\tmax\nA\t1\tstep\tany\n');
        \\assert.ok(input === root.firstChild && input === document.activeElement && input.value === '12' && input.required && input.min === '5' && input.max === '' && input.step === 'any');
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: external link updates retain the link and focused sibling" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<a data-node-id="1" data-external-link="true">Open</a><input value="draft">');
        \\const link = root.firstChild, input = root.lastChild; input.focus();
        \\dom.applyPatchStream('A\t1\thref\thttps://example.test/?a=1&b=2\n');
        \\assert.equal(link.getAttribute('href'), 'https://example.test/?a=1&b=2');
        \\dom.applyPatchStream('A\t1\thref\thttp://example.test/plain\n');
        \\assert.equal(link.getAttribute('href'), 'http://example.test/plain');
        \\dom.applyPatchStream('A\t1\thref\t#section-2\n');
        \\assert.equal(link.getAttribute('href'), '#section-2');
        \\dom.applyPatchStream('R\t1\thref\n');
        \\assert.ok(link === root.firstChild && !link.hasAttribute('href') && input === document.activeElement && input.value === 'draft');
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: cell updates retain row, sibling control, focus and valid table structure" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<table data-node-id="1"><tbody data-node-id="2"><tr data-node-id="3"><th data-node-id="4">Label</th><td data-node-id="5"><input data-node-id="6" value="draft"></td></tr></tbody></table>');
        \\const table = root.querySelector('table'), row = table.rows[0], input = root.querySelector('input');
        \\input.focus(); input.setSelectionRange(1, 3);
        \\dom.applyPatchStream('T\t4\t"Changed"\n');
        \\assert.ok(table === root.querySelector('table') && row === table.rows[0] && row.cells.length === 2 && input === document.activeElement && input.isConnected && input.value === 'draft' && input.selectionStart === 1 && input.selectionEnd === 3);
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: input kind patches retain the input, value, sibling and focus" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<div data-node-id="601"><input data-node-id="602" type="password" value="draft"><input data-node-id="603" value="sibling"></div>');
        \\const control = root.querySelector('[data-node-id="602"]');
        \\const sibling = control.nextElementSibling;
        \\const parent = control.parentElement;
        \\control.focus(); control.setSelectionRange(1, 3);
        \\dom.applyPatchStream('A\t601\tdir\trtl\nA\t602\tname\tsecret\nA\t602\tautocomplete\toff\n');
        \\if (parent.dir !== 'rtl' || control.name !== 'secret' || control.autocomplete !== 'off') throw new Error('metadata patch failed');
        \\for (const type of ['text', 'password']) {
        \\  dom.applyPatchStream(`A\t602\ttype\t${type}\n`);
        \\  if (control !== document.activeElement || control.parentElement !== parent || control.nextElementSibling !== sibling || control.value !== 'draft' || control.type !== type || control.selectionStart !== 1 || control.selectionEnd !== 3) {
        \\    throw new Error('kind update lost a retained control, selection or value');
        \\  }
        \\}
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: object image patches require same-origin permission and retain controls" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<img data-node-id="1" data-object-image="true" alt="Preview"><input data-node-id="2" value="draft"><img data-node-id="3" alt="Ordinary">');
        \\const image = root.querySelector('[data-node-id="1"]');
        \\const input = root.querySelector('input'); input.focus();
        \\const url = URL.createObjectURL(new Blob(['<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"><rect width="1" height="1"/></svg>'], { type: 'image/svg+xml' }));
        \\try {
        \\  const loaded = new Promise((resolve, reject) => { image.onload = resolve; image.onerror = reject; });
        \\  dom.applyPatchStream(`A\t1\tsrc\t${url}\n`); await loaded;
        \\  let rejected = 0;
        \\  for (const [id, source] of [[3, url], [1, 'blob:https://elsewhere.test/id'], [1, 'blob:null/id']]) {
        \\    try { dom.applyPatchStream(`A\t${id}\tsrc\t${source}\n`); } catch { rejected++; }
        \\  }
        \\  if (rejected !== 3 || image !== root.firstElementChild || input !== document.activeElement || input.value !== 'draft' || !image.naturalWidth) throw new Error('object image permission or identity failed');
        \\  dom.applyPatchStream('R\t1\tsrc\n');
        \\  if (image.hasAttribute('src') || input !== document.activeElement) throw new Error('removal changed image or focus');
        \\} finally { URL.revokeObjectURL(url); }
        \\dom.dispose(); root.remove();
        \\return true;
    );
}

test "browser dom: node registry tracks structural ownership, external mutations and resync" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<div data-node-id="1"><input data-node-id="2" value="draft"><span data-node-id="3"><b data-node-id="4">old</b></span></div>');
        \\const input = root.querySelector('input'); input.focus();
        \\const query = root.querySelectorAll.bind(root);
        \\let scans = 0;
        \\root.querySelectorAll = (...args) => { scans++; return query(...args); };
        \\for (let i = 0; i < 100; i++) dom.applyPatchStream(`A\t2\taria-label\t${i}\n`);
        \\const noRescan = scans === 0;
        \\const rejects = stream => { try { dom.applyPatchStream(stream); return false; } catch { return true; } };
        \\dom.applyPatchStream('T\t3\t"text"\n');
        \\const textRemoved = rejects('T\t4\t"absent"\n');
        \\dom.applyPatchStream('H\t3\t"<i data-node-id=\\"4\\">new</i>"\nT\t4\t"updated"\n');
        \\const newOwner = root.querySelector('i');
        \\dom.applyPatchStream('J\t3\t"<b data-node-id=\\"5\\">second</b>"\nM\t5\t4\tbefore\n');
        \\const moved = newOwner.isConnected && root.querySelector('[data-node-id="3"]').lastElementChild === newOwner;
        \\dom.applyPatchStream('D\t4\n');
        \\const deleted = rejects('T\t4\t"absent"\n');
        \\root.querySelector('[data-node-id="3"]').insertAdjacentHTML('beforeend', '<i data-node-id="5">duplicate</i>');
        \\const duplicateSameTask = rejects('T\t5\t"ambiguous"\n');
        \\root.querySelector('i').remove();
        \\dom.applyPatchStream('T\t5\t"unique"\n');
        \\const control = root.querySelector('b');
        \\control.setAttribute('data-node-id', '6');
        \\const oldIdGone = rejects('T\t5\t"old"\n');
        \\dom.applyPatchStream('T\t6\t"new identity"\n');
        \\await Promise.resolve();
        \\const outside = document.createElement('i'); outside.dataset.nodeId = '6'; root.append(outside);
        \\await new Promise(resolve => setTimeout(resolve, 0));
        \\const duplicateLater = rejects('T\t6\t"ambiguous"\n');
        \\outside.remove();
        \\const retained = input.isConnected && input === document.activeElement && input.value === 'draft';
        \\dom.initialize('<span data-node-id="2">reset</span>');
        \\dom.applyPatchStream('T\t2\t"recovered"\n');
        \\const recovered = root.textContent === 'recovered' && !input.isConnected;
        \\dom.dispose(); root.remove();
        \\assert.ok([noRescan, textRemoved, moved, deleted, duplicateSameTask, oldIdGone, duplicateLater, retained, recovered].every(Boolean));
        \\return true;
    );
}

test "browser dom: DOM host coordinates CSS transitions, exit lifecycles, safety timeout, and re-adoption" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<ul data-node-id="1"><li data-node-id="2" data-exit-transition="fade" data-exit-timeout="100"><span data-node-id="3">Item 1</span></li><li data-node-id="4">Item 2</li></ul>');
        \\const item1 = root.querySelector('[data-node-id="2"]');
        \\dom.applyPatchStream('D\t2\n');
        \\const stillAttached = item1.isConnected;
        \\const hasExitClass = item1.classList.contains('zg-exit') && item1.classList.contains('zg-exit-active');
        \\const hasCustomExitClass = item1.classList.contains('fade-exit') && item1.classList.contains('fade-exit-active');
        \\const isInert = item1.style.pointerEvents === 'none' && item1.getAttribute('aria-hidden') === 'true';
        \\dom.applyPatchStream('J\t1\t"<li data-node-id=\\"2\\" data-exit-transition=\\"fade\\" data-exit-timeout=\\"100\\"><span data-node-id=\\"3\\">Item 1</span></li>"\n');
        \\const reAdopted = root.querySelector('[data-node-id="2"]') === item1;
        \\const notInert = item1.style.pointerEvents === '' && !item1.hasAttribute('aria-hidden');
        \\const hasEnterClass = item1.classList.contains('zg-enter') && item1.classList.contains('zg-enter-active');
        \\const exitClassCleared = !item1.classList.contains('zg-exit') && !item1.classList.contains('zg-exit-active');
        \\dom.applyPatchStream('D\t2\n');
        \\const secondExitAttached = item1.isConnected;
        \\item1.dispatchEvent(new Event('transitionend', { bubbles: true }));
        \\const detachedOnTransitionEnd = !item1.isConnected;
        \\dom.applyPatchStream('J\t1\t"<li data-node-id=\\"5\\" data-exit-transition=\\"collapse\\" data-exit-timeout=\\"50\\">Item 3</li>"\n');
        \\const item3 = root.querySelector('[data-node-id="5"]');
        \\dom.applyPatchStream('D\t5\n');
        \\const item3InitiallyAttached = item3.isConnected;
        \\await new Promise(resolve => setTimeout(resolve, 80));
        \\const item3DetachedAfterTimeout = !item3.isConnected;
        \\dom.dispose(); root.remove();
        \\assert.ok([stillAttached, hasExitClass, hasCustomExitClass, isInert, reAdopted, notInert, hasEnterClass, exitClassCleared, secondExitAttached, detachedOnTransitionEnd, item3InitiallyAttached, item3DetachedAfterTimeout].every(Boolean));
        \\return true;
    );
}

test "browser dom: DOM host hydrates existing SSR markup preserving node identities, focus and draft state" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\root.innerHTML = '<section data-node-id="1"><h1 data-node-id="2">Pre-rendered Title</h1><input data-node-id="3" id="task-name" value="Initial"><select data-node-id="4" data-select-value="b"><option value="a">A</option><option value="b">B</option></select><div data-node-id="5" data-style-vars="--padding:16px">Content</div></section>';
        \\const existingSection = root.querySelector('section');
        \\const existingH1 = root.querySelector('h1');
        \\const existingInput = root.querySelector('#task-name');
        \\const existingSelect = root.querySelector('select');
        \\const existingDiv = root.querySelector('div');
        \\existingInput.focus(); existingInput.value = 'User Draft While Downloading WASM'; existingInput.setSelectionRange(5, 10);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<section data-node-id="1"><h1 data-node-id="2">Pre-rendered Title</h1><input data-node-id="3" id="task-name" value="Initial"><select data-node-id="4" data-select-value="b"><option value="a">A</option><option value="b">B</option></select><div data-node-id="5" data-style-vars="--padding:16px">Content</div></section>', { hydrate: true });
        \\const nodesIdentical = (root.querySelector('section') === existingSection) && (root.querySelector('h1') === existingH1) && (root.querySelector('#task-name') === existingInput) && (root.querySelector('select') === existingSelect) && (root.querySelector('div') === existingDiv);
        \\const focusPreserved = (document.activeElement === existingInput);
        \\const draftPreserved = (existingInput.value === 'User Draft While Downloading WASM');
        \\const selectionPreserved = (existingInput.selectionStart === 5 && existingInput.selectionEnd === 10);
        \\const selectVal = existingSelect.value;
        \\const styleApplied = existingDiv.style.getPropertyValue('--padding') === '16px';
        \\dom.applyPatchStream('T\t2\t"Updated After Hydration"\n');
        \\const patchApplied = (existingH1.textContent === 'Updated After Hydration') && (root.querySelector('h1') === existingH1);
        \\dom.dispose(); root.remove();
        \\assert.ok([nodesIdentical, focusPreserved, draftPreserved, selectionPreserved, selectVal === 'b', styleApplied, patchApplied].every(Boolean));
        \\return true;
    );
}

test "browser dom: DOM host hydration gracefully falls back to clean initialization when root is empty" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<p data-node-id="1">Fallback render</p>', { hydrate: true });
        \\const rendered = root.querySelector('p')?.textContent === 'Fallback render';
        \\dom.dispose(); root.remove();
        \\assert.ok(rendered);
        \\return true;
    );
}

test "browser dom: virtual scrolling window calculation and container styling" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost, calculateWindowSlice } = await import('/dom.js');
        \\const topSlice = calculateWindowSlice({ scrollTop: 0, viewportHeight: 800, itemHeight: 40, totalItems: 10000, overscan: 5 });
        \\const midSlice = calculateWindowSlice({ scrollTop: 4000, viewportHeight: 800, itemHeight: 40, totalItems: 10000, overscan: 5 });
        \\const botSlice = calculateWindowSlice({ scrollTop: 399500, viewportHeight: 800, itemHeight: 40, totalItems: 10000, overscan: 5 });
        \\const topValid = (topSlice.startIndex === 0) && (topSlice.endIndex === 25) && (topSlice.topSpacer === 0) && (topSlice.totalHeight === 400000) && (topSlice.topSpacer + (topSlice.endIndex - topSlice.startIndex) * 40 + topSlice.bottomSpacer === topSlice.totalHeight);
        \\const midValid = (midSlice.startIndex === 95) && (midSlice.endIndex === 125) && (midSlice.topSpacer === 95 * 40) && (midSlice.topSpacer + (midSlice.endIndex - midSlice.startIndex) * 40 + midSlice.bottomSpacer === midSlice.totalHeight);
        \\const botValid = (botSlice.endIndex === 10000) && (botSlice.bottomSpacer === 0) && (botSlice.topSpacer + (botSlice.endIndex - botSlice.startIndex) * 40 + botSlice.bottomSpacer === botSlice.totalHeight);
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<div data-node-id="1" class="scroller" data-window-item-height="40" data-window-overscan="5"><ul data-node-id="2"><li data-node-id="3">Row 1</li></ul></div>');
        \\const scroller = root.querySelector('.scroller');
        \\const itemHeightVar = scroller.style.getPropertyValue('--window-item-height');
        \\const overscanVar = scroller.style.getPropertyValue('--window-overscan');
        \\dom.dispose(); root.remove();
        \\assert.ok(topValid && midValid && botValid && itemHeightVar === '40px' && overscanVar === '5');
        \\return true;
    );
}

test "browser dom: form validation interaction tracking, dirty/touched lifecycle, and accessibility attribute synchronization" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize(`
        \\  <form data-node-id="1">
        \\    <input data-node-id="2" id="email" type="text">
        \\    <span data-node-id="3" id="email-error" hidden></span>
        \\    <textarea data-node-id="4" id="bio"></textarea>
        \\    <select data-node-id="5" id="role"><option value="admin">Admin</option></select>
        \\    <button data-node-id="6" id="submit" type="submit">Submit</button>
        \\  </form>
        \\`);
        \\const email = root.querySelector('#email'), bio = root.querySelector('#bio'), role = root.querySelector('#role'), btn = root.querySelector('#submit');
        \\const emailPristineInitial = email.getAttribute('data-pristine') === 'true' && !email.hasAttribute('data-dirty') && !email.hasAttribute('data-touched');
        \\const bioPristineInitial = bio.getAttribute('data-pristine') === 'true';
        \\const rolePristineInitial = role.getAttribute('data-pristine') === 'true';
        \\const btnNotPristine = !btn.hasAttribute('data-pristine');
        \\email.focus(); email.blur();
        \\if (!email.hasAttribute('data-touched')) email.dispatchEvent(new Event('blur'));
        \\const touchedOnly = email.getAttribute('data-touched') === 'true' && email.getAttribute('data-pristine') === 'true' && !email.hasAttribute('data-dirty');
        \\email.focus(); email.value = 'invalid-email'; email.dispatchEvent(new Event('input', { bubbles: true }));
        \\const dirtyAfterInput = email.getAttribute('data-dirty') === 'true' && !email.hasAttribute('data-pristine');
        \\dom.applyPatchStream('A\t2\taria-invalid\ttrue\nA\t2\taria-describedby\temail-error\n');
        \\const ariaInvalidSet = email.getAttribute('aria-invalid') === 'true';
        \\const ariaDescribedbySet = email.getAttribute('aria-describedby') === 'email-error';
        \\dom.applyPatchStream('R\t2\taria-invalid\nR\t2\taria-describedby\n');
        \\const ariaInvalidCleared = !email.hasAttribute('aria-invalid');
        \\const ariaDescribedbyCleared = !email.hasAttribute('aria-describedby');
        \\email.focus(); email.setSelectionRange(4, 4);
        \\dom.applyPatchStream('A\t2\taria-invalid\ttrue\n');
        \\const focusPreserved = document.activeElement === email;
        \\const caretPreserved = email.selectionStart === 4 && email.selectionEnd === 4;
        \\dom.dispose(); root.remove();
        \\const checks = { emailPristineInitial, bioPristineInitial, rolePristineInitial, btnNotPristine, touchedOnly, dirtyAfterInput, ariaInvalidSet, ariaDescribedbySet, ariaInvalidCleared, ariaDescribedbyCleared, focusPreserved, caretPreserved };
        \\for (const [k, v] of Object.entries(checks)) {
        \\  if (!v) throw new Error('Check failed: ' + k + ' is ' + v);
        \\}
        \\return true;
    );
}

test "browser dom: modal focus trapping, hotkeys, and roving tabindex" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize(`
        \\  <div data-node-id="1">
        \\    <button id="open-btn" data-node-id="2">Open Modal</button>
        \\    <button id="search-btn" data-node-id="3" data-hotkey="ctrl+k">Search</button>
        \\    <nav id="toolbar" data-node-id="4" data-roving-tabindex="horizontal">
        \\      <button id="tab-1" data-node-id="5" tabindex="0">Tab 1</button>
        \\      <button id="tab-2" data-node-id="6" tabindex="-1">Tab 2</button>
        \\      <button id="tab-3" data-node-id="7" tabindex="-1">Tab 3</button>
        \\    </nav>
        \\    <div id="live-region" data-node-id="8" aria-live="polite" aria-atomic="true">Status: Ready</div>
        \\    <div id="modal" data-node-id="10" role="dialog" aria-modal="true" data-trap-focus="false" hidden>
        \\      <h2>Modal Dialog</h2>
        \\      <input id="modal-input" data-node-id="11" type="text" value="first">
        \\      <button id="modal-confirm" data-node-id="12">Confirm</button>
        \\      <button id="modal-close" data-node-id="13" data-close-dialog aria-label="Close">Close</button>
        \\    </div>
        \\  </div>
        \\`);
        \\const openBtn = document.getElementById('open-btn');
        \\const searchBtn = document.getElementById('search-btn');
        \\const tab1 = document.getElementById('tab-1');
        \\const tab2 = document.getElementById('tab-2');
        \\const tab3 = document.getElementById('tab-3');
        \\const liveRegion = document.getElementById('live-region');
        \\const modal = document.getElementById('modal');
        \\const modalInput = document.getElementById('modal-input');
        \\const modalConfirm = document.getElementById('modal-confirm');
        \\const modalClose = document.getElementById('modal-close');
        \\let searchClicked = false; searchBtn.addEventListener('click', () => { searchClicked = true; });
        \\root.dispatchEvent(new KeyboardEvent('keydown', { key: 'k', ctrlKey: true, bubbles: true }));
        \\const hotkeyTriggered = searchClicked;
        \\tab1.focus();
        \\document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
        \\const tab2Focused = document.activeElement === tab2 && tab2.getAttribute('tabindex') === '0' && tab1.getAttribute('tabindex') === '-1';
        \\document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
        \\const tab3Focused = document.activeElement === tab3 && tab3.getAttribute('tabindex') === '0' && tab2.getAttribute('tabindex') === '-1';
        \\document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }));
        \\const tab2Refocused = document.activeElement === tab2;
        \\document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'Home', bubbles: true }));
        \\const tab1HomeFocused = document.activeElement === tab1 && tab1.getAttribute('tabindex') === '0';
        \\openBtn.focus();
        \\dom.applyPatchStream('R\t10\thidden\nA\t10\tdata-trap-focus\ttrue\n');
        \\modal.hidden = false;
        \\const modalInputAutoFocused = document.activeElement === modalInput;
        \\modalConfirm.focus(); root.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true }));
        \\modalClose.focus(); root.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true }));
        \\const tabWrappedToFirst = document.activeElement === modalInput;
        \\root.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', shiftKey: true, bubbles: true }));
        \\const shiftTabWrappedToLast = document.activeElement === modalClose;
        \\let closeClicked = false; modalClose.addEventListener('click', () => { closeClicked = true; });
        \\root.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        \\const escapeTriggeredClose = closeClicked;
        \\dom.applyPatchStream('A\t10\thidden\t\nR\t10\tdata-trap-focus\n');
        \\modal.hidden = true;
        \\const focusRestoredToTrigger = document.activeElement === openBtn;
        \\dom.applyPatchStream('T\t8\t"Status: Updated successfully"\n');
        \\const liveRegionUpdated = liveRegion.textContent === 'Status: Updated successfully' && liveRegion.getAttribute('aria-live') === 'polite';
        \\dom.dispose(); root.remove();
        \\assert.ok([hotkeyTriggered, tab2Focused, tab3Focused, tab2Refocused, tab1HomeFocused, modalInputAutoFocused, tabWrappedToFirst, shiftTabWrappedToLast, escapeTriggeredClose, focusRestoredToTrigger, liveRegionUpdated].every(Boolean));
        \\return true;
    );
}

test "browser dom: web components, frame sync host, and container queries" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost, createFrameSyncHost } = await import('/dom.js');
        \\const zgView = document.createElement('zg-view');
        \\zgView.setAttribute('shadow', 'open'); document.body.append(zgView);
        \\zgView.initialize('<section data-node-id="1"><span data-node-id="2">Initial Shadow</span></section>');
        \\const shadowSpan = zgView.shadowRoot?.querySelector('[data-node-id="2"]');
        \\const customElementShadowMounted = shadowSpan?.textContent === 'Initial Shadow';
        \\zgView.applyPatchStream('T\t2\t"Updated Shadow"\n');
        \\const customElementShadowPatched = shadowSpan?.textContent === 'Updated Shadow';
        \\zgView.remove();
        \\const customElementDisposed = zgView._dom === null;
        \\const lightView = document.createElement('zg-view'); document.body.append(lightView);
        \\lightView.initialize('<section data-node-id="1"><span data-node-id="2">Light DOM</span></section>');
        \\const lightSpan = lightView.querySelector('[data-node-id="2"]');
        \\const lightDomMounted = lightSpan?.textContent === 'Light DOM';
        \\lightView.remove();
        \\const frameRoot = document.createElement('div'); document.body.append(frameRoot);
        \\const channel = new MessageChannel();
        \\const frameHost = createFrameSyncHost({ root: frameRoot, port: channel.port1 });
        \\await new Promise(resolve => {
        \\  channel.port2.postMessage({ type: 'zg:initialize', html: '<div data-node-id="1"><span data-node-id="2">Frame Init</span></div>' });
        \\  setTimeout(resolve, 50);
        \\});
        \\const frameSpan = frameRoot.querySelector('[data-node-id="2"]');
        \\const frameHostInitialized = frameSpan?.textContent === 'Frame Init';
        \\const patchText = 'T\t2\t"Frame Synced"\n';
        \\const buffer = new TextEncoder().encode(patchText).buffer;
        \\await new Promise(resolve => {
        \\  channel.port2.postMessage({ type: 'zg:patch-stream', buffer }, [buffer]);
        \\  setTimeout(resolve, 50);
        \\});
        \\const frameHostPatched = frameSpan?.textContent === 'Frame Synced';
        \\const zeroCopyTransferred = buffer.byteLength === 0;
        \\frameHost.dispose(); frameRoot.remove();
        \\const observeRoot = document.createElement('div'); document.body.append(observeRoot);
        \\const dom = createDomHost({ root: observeRoot });
        \\dom.initialize('<div id="card" data-node-id="1" data-observe-size="compact:400,expanded:800" style="width:300px;height:50px;">Card</div>');
        \\const card = observeRoot.querySelector('#card');
        \\await new Promise(resolve => setTimeout(resolve, 100));
        \\const compactObserved = card.getAttribute('data-size') === 'compact';
        \\card.style.width = '900px';
        \\await new Promise(resolve => setTimeout(resolve, 100));
        \\const expandedObserved = card.getAttribute('data-size') === 'expanded';
        \\dom.dispose(); observeRoot.remove();
        \\assert.ok([customElementShadowMounted, customElementShadowPatched, customElementDisposed, lightDomMounted, frameHostInitialized, frameHostPatched, zeroCopyTransferred, compactObserved, expandedObserved].every(Boolean));
        \\return true;
    );
}

test "browser dom: FLIP layout transitions, island hydration, and optimistic rollback" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const flipRoot = document.createElement('div'); document.body.append(flipRoot);
        \\const dom1 = createDomHost({ root: flipRoot });
        \\dom1.initialize(`
        \\  <div data-node-id="1">
        \\    <div data-node-id="2" data-layout-id="item-a" style="height:30px;">Item A</div>
        \\    <div data-node-id="3" data-layout-id="item-b" style="height:30px;">Item B</div>
        \\  </div>
        \\`);
        \\const itemA = flipRoot.querySelector('[data-layout-id="item-a"]');
        \\const itemB = flipRoot.querySelector('[data-layout-id="item-b"]');
        \\const initialBefore = itemA.nextElementSibling === itemB;
        \\dom1.applyPatchStream('M\t3\t2\tbefore\n');
        \\const reordered = itemB.nextElementSibling === itemA;
        \\dom1.dispose(); flipRoot.remove();
        \\const islandRoot = document.createElement('div'); document.body.prepend(islandRoot);
        \\const dom2 = createDomHost({ root: islandRoot });
        \\let hydratedCount = 0; islandRoot.addEventListener('zg:hydrate', () => { hydratedCount++; });
        \\dom2.initialize(`
        \\  <div data-node-id="1">
        \\    <div data-node-id="2" data-hydrate="visible" style="height:40px;">Visible Island</div>
        \\    <div data-node-id="3" data-hydrate="idle" style="height:40px;">Idle Island</div>
        \\  </div>
        \\`);
        \\await new Promise(resolve => window.requestAnimationFrame(() => setTimeout(resolve, 150)));
        \\const visibleIsland = islandRoot.querySelector('[data-hydrate="visible"]');
        \\const idleIsland = islandRoot.querySelector('[data-hydrate="idle"]');
        \\const visibleHydrated = visibleIsland?.getAttribute('data-hydrated') === 'true';
        \\const idleHydrated = idleIsland?.getAttribute('data-hydrated') === 'true';
        \\dom2.dispose(); islandRoot.remove();
        \\const optRoot = document.createElement('div'); document.body.append(optRoot);
        \\const dom3 = createDomHost({ root: optRoot });
        \\dom3.initialize('<div data-node-id="1"><button data-node-id="2" data-optimistic="bookmark" class="btn">Save</button></div>');
        \\const btn = optRoot.querySelector('button');
        \\dom3.applyOptimistic(btn, { actionId: 'action-101', updates: { className: 'btn btn-active', textContent: 'Saving...', attributes: { 'aria-busy': 'true' } } });
        \\const pendingState = btn.getAttribute('data-optimistic-state') === 'pending' && btn.textContent === 'Saving...' && btn.className.includes('btn-active') && btn.getAttribute('aria-busy') === 'true';
        \\dom3.rollbackOptimistic('action-101');
        \\const revertedState = btn.getAttribute('data-optimistic-state') === 'reverted' && btn.textContent === 'Save' && btn.className === 'btn' && !btn.hasAttribute('aria-busy');
        \\dom3.applyOptimistic(btn, { actionId: 'action-102', updates: { textContent: 'Confirmed!' } });
        \\dom3.confirmOptimistic('action-102');
        \\const confirmedState = btn.getAttribute('data-optimistic-state') === 'confirmed' && btn.textContent === 'Confirmed!';
        \\dom3.dispose(); optRoot.remove();
        \\assert.ok([initialBefore, reordered, visibleHydrated, idleHydrated, hydratedCount >= 1, pendingState, revertedState, confirmedState].every(Boolean));
        \\return true;
    );
}

test "browser dom: generated input kind changes precede controlled values in either attribute order" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<section data-node-id="1"><input data-node-id="2" type="number" value="123"><input data-node-id="3" value="draft"></section>');
        \\const parent = root.firstElementChild, input = parent.firstElementChild, sibling = parent.lastElementChild;
        \\input.focus();
        \\dom.applyPatchStream('A\t2\ttype\ttext\nV\t2\t"abc"\n');
        \\const text = input.type === 'text' && input.value === 'abc' && document.activeElement === input;
        \\sibling.focus(); sibling.setSelectionRange(1, 3);
        \\dom.applyPatchStream('A\t2\ttype\tnumber\nV\t2\t"456"\n');
        \\const retained = root.firstElementChild === parent && parent.firstElementChild === input && parent.lastElementChild === sibling && document.activeElement === sibling && sibling.value === 'draft' && sibling.selectionStart === 1 && sibling.selectionEnd === 3 && input.type === 'number' && input.value === '456';
        \\dom.dispose(); root.remove();
        \\assert.ok(text && retained);
        \\return true;
    );
}

test "browser dom: generated textarea values preserve leading newlines in HTML and patches" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<textarea data-node-id="1">\n\n\n&lt;&amp;&gt;</textarea>');
        \\const initial = root.firstElementChild.value;
        \\dom.applyPatchStream('V\t1\t"\\nchanged"\n');
        \\const updated = root.firstElementChild.value;
        \\dom.initialize('<section data-node-id="1"><input data-node-id="2" value="draft"><div data-node-id="99"></div></section>');
        \\const parent = root.firstElementChild, input = parent.firstElementChild, owner = parent.lastElementChild;
        \\input.focus(); input.setSelectionRange(1, 3);
        \\dom.applyPatchStream('H\t99\t' + JSON.stringify('<textarea data-node-id="100">\n\n\n&lt;&amp;&gt;</textarea>') + '\n');
        \\const replaced = owner.firstElementChild.value;
        \\dom.dispose(); root.remove();
        \\assert.ok(initial === '\n\n<&>' && updated === '\nchanged' && replaced === '\n\n<&>');
        \\return true;
    );
}

test "browser dom: generated option text patches restore declared selection without a value patch" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({ root });
        \\dom.initialize('<section><select data-select-value="a"><option data-node-id="1">a</option><option data-node-id="2">c</option></select><input value="draft"></section>');
        \\const parent = root.firstElementChild, select = parent.firstElementChild, input = parent.lastElementChild;
        \\select.focus();
        \\dom.applyPatchStream('T\t1\t"b"\nT\t2\t"a"\n');
        \\const swapped = select.value === 'a' && select.selectedIndex === 1;
        \\dom.applyPatchStream('T\t2\t"c"\n');
        \\const absent = select.value === '' && select.selectedIndex === -1;
        \\dom.dispose(); root.remove();
        \\assert.ok(swapped && absent);
        \\return true;
    );
}

test "browser dom: focus mode preserves clipped ancestor position and node identity" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/dom.js");
    try guard.evalCheck(
        \\const { createDomHost } = await import('/dom.js');
        \\const root = document.createElement('main'); document.body.append(root);
        \\const dom = createDomHost({root});
        \\dom.initialize('<section data-node-id="1" style="width:200px;height:100px;overflow:hidden"><h2 data-node-id="2" tabindex="-1" style="width:400px;margin-left:25px">Wide heading</h2><input data-node-id="3" value="draft"></section>');
        \\const owner=root.firstElementChild, heading=owner.firstElementChild, control=owner.lastElementChild;
        \\owner.scrollLeft=10;
        \\dom.applyPatchStream('F\t2\n');
        \\assert.equal(document.activeElement,heading); assert.equal(owner.scrollLeft,10);
        \\assert.equal(root.firstElementChild,owner); assert.equal(owner.lastElementChild,control);
        \\dom.applyPatchStream('F\t2\tnearest\n');
        \\assert.equal(document.activeElement,heading); assert.ok(owner.scrollLeft>10);
        \\assert.equal(root.firstElementChild,owner); assert.equal(owner.lastElementChild,control);
        \\dom.dispose(); root.remove(); return true;
    );
}
