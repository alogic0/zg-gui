import assert from 'node:assert/strict';
import { test } from 'node:test';
import { chromium } from 'playwright';
import { serve } from '../tools/server.mjs';

test('DOM host retains controls and validates typed patch commands', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    const result = await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main');
      document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<section data-node-id="1"><input data-node-id="2" value="draft"><span data-node-id="3">one</span><input data-node-id="4" type="checkbox"></section><ul data-node-id="5"><li data-node-id="6"><input data-node-id="7" value="row"></li><li data-node-id="8">other</li></ul>');
      const selectRoot = document.createElement('div'); document.body.append(selectRoot);
      const selects = createDomHost({ root: selectRoot });
      selects.initialize('<select data-node-id="1" data-select-value="b"><option data-node-id="2" value="a">b</option><option data-node-id="3" value="b">B</option></select>');
      const controlled = selectRoot.querySelector('select');
      selects.applyPatchStream('A\t2\tvalue\tb\nD\t3\n');
      if (controlled.value !== 'b') throw new Error('option value update lost controlled selection');
      selects.applyPatchStream('R\t2\tvalue\n');
      if (controlled.value !== 'b') throw new Error('option fallback text lost controlled selection');
      selectRoot.remove();
      const owner = root.firstElementChild;
      const input = root.querySelector('[data-node-id="2"]');
      input.focus(); input.setSelectionRange(1, 3);
      dom.applyPatchStream('T\t3\t"two\\n🧭"\nA\t3\taria-label\tlabel\nC\t4\ttrue\n');
      const retained = owner === root.firstElementChild && input.isConnected && document.activeElement === input && input.selectionStart === 1 && input.selectionEnd === 3;
      dom.applyPatchStream('A\t3\tdraggable\ttrue\n');
      const dragHandle = root.querySelector('[data-node-id="3"]');
      if (!dragHandle.draggable) throw new Error('drag eligibility was not applied');
      dom.applyPatchStream('A\t3\tdraggable\tfalse\n');
      if (dragHandle.draggable || dragHandle.getAttribute('draggable') !== 'false') throw new Error('false drag value was not retained');
      dom.applyPatchStream('R\t3\tdraggable\n');
      if (dragHandle.hasAttribute('draggable') || dragHandle !== root.querySelector('[data-node-id="3"]') || input !== document.activeElement || owner !== root.firstElementChild) throw new Error('drag update changed controls or focus');
      const row = root.querySelector('[data-node-id="6"]');
      const rowInput = row.firstElementChild; rowInput.focus();
      dom.applyPatchStream('J\t5\t"<li data-node-id=\\"9\\">new</li>"\nM\t6\t8\tafter\nD\t9\n');
      const moved = row.isConnected && document.activeElement === rowInput && root.querySelector('[data-node-id="5"]').lastElementChild === row;
      dom.applyPatchStream('V\t2\t"updated"\nA\t3\thidden\t\nR\t3\thidden\nF\t2\tend\n');
      const focused = document.activeElement === input && input.selectionStart === 7;
      let rejected = 0;
      for (const stream of ['T\t999\t"absent"\n', 'A\t3\tonclick\tevil\n', 'C\t3\ttrue\n', 'H\t3\t42\n', 'M\t6\t3\tafter\n', 'A\t3\thref\tjavascript:alert(1)\n']) {
        try { dom.applyPatchStream(stream); } catch { rejected++; }
      }
      dom.applyPatchStream('J\t5\t"<input data-node-id=\\"20\\" type=\\"datetime-local\\" data-value-format=\\"instant-local\\" data-initial-value=\\"2026-09-14T12:00:00Z\\">"\n');
      const dateFormatted = root.querySelector('[data-node-id="20"]').value.length > 0;
      dom.applyPatchStream('H\t3\t"<span data-node-id=\\"2\\">duplicate</span>"\n');
      try { dom.applyPatchStream('T\t2\t"ambiguous"\n'); } catch { rejected++; }
      return { retained, moved, focused, dateFormatted, checked: root.querySelector('[data-node-id="4"]').checked, rejected };
    });
    assert.deepEqual(result, { retained: true, moved: true, focused: true, dateFormatted: true, checked: true, rejected: 7 });
  } finally { await browser?.close(); await server.close(); }
});

test('table section patches retain table header row controls and focus', async () => {
  const server=await serve({directory:new URL('../web',import.meta.url).pathname});
  let browser;
  try {
    browser=await chromium.launch({headless:true});const page=await browser.newPage();
    await page.goto(server.url+'/dom.js');
    const result=await page.evaluate(async()=>{
      const {createDomHost}=await import('/dom.js');
      const root=document.createElement('main');document.body.append(root);
      const dom=createDomHost({root});
      dom.initialize('<button data-node-id="1">Refresh</button><table data-node-id="2"><thead data-node-id="3"><tr><th>Label</th><th>Draft</th></tr></thead><tbody data-node-id="4"><tr data-node-id="5"><td data-node-id="6">One</td><td><input data-node-id="7" value="keep"></td></tr></tbody></table>');
      const table=root.querySelector('table'),head=table.tHead,body=table.tBodies[0],row=body.rows[0],input=root.querySelector('input'),button=root.querySelector('button');
      input.focus();dom.applyPatchStream('T\t6\t"Changed"\n');
      const cell = row.cells[0];
      dom.applyPatchStream('A\t6\tcolspan\t2\nA\t6\trowspan\t3\n');
      const spans = cell === row.cells[0] && cell.colSpan === 2 && cell.rowSpan === 3
        && input === document.activeElement && input.value === 'keep';
      dom.applyPatchStream('R\t6\trowspan\n');
      if (!spans || cell.hasAttribute('rowspan')) throw new Error('cell span patch replaced or blurred peers');
      const scalar=body.rows[0]===row&&input===document.activeElement&&input.value==='keep';
      button.focus();dom.applyPatchStream('H\t4\t'+JSON.stringify('<tr data-node-id="8"><td data-node-id="9">Two</td><td>Read only</td></tr>')+'\n');
      const structure=table===root.querySelector('table')&&head===table.tHead&&body===table.tBodies[0]&&body.rows.length===1&&body.rows[0].cells.length===2&&button===document.activeElement&&!row.isConnected;
      const ids=[...root.querySelectorAll('[data-node-id]')].map(n=>n.dataset.nodeId);
      return {scalar,structure,unique:new Set(ids).size===ids.length};
    });
    assert.deepEqual(result,{scalar:true,structure:true,unique:true});
  } finally {await browser?.close();await server.close();}
});

test('select option replacement retains owner focus and controlled selection', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<section data-node-id="1"><select data-node-id="2" data-select-value="b"><option value="a">A</option><option value="b">B</option></select><input data-node-id="3" value="draft"></section>');
      const panel = root.firstChild, select = panel.querySelector('select'), peer = panel.querySelector('input');
      select.focus();
      dom.applyPatchStream('H\t2\t' + JSON.stringify('<option value="a">A</option>') + '\n');
      if (select.value !== '' || document.activeElement !== select) return false;
      dom.applyPatchStream('H\t2\t' + JSON.stringify('<option value="b">B</option><option value="c">C</option>') + '\n');
      return root.firstChild === panel && select === panel.querySelector('select')
        && document.activeElement === select && select.value === 'b'
        && peer === panel.querySelector('input') && peer.value === 'draft';
    }), true);
  } finally { await browser?.close(); await server.close(); }
});

test('multiple selection retains focus and synchronizes option selected states', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const { declaredInputValue } = await import('/local-datetime.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<section data-node-id="1"><select multiple data-node-id="2" data-select-values="a\x1fc"><option value="a">A</option><option value="b">B</option><option value="c">C</option></select><input data-node-id="3" value="peer"></section>');
      const panel = root.firstChild, select = panel.querySelector('select'), options = select.options;
      select.focus();
      if (!options[0].selected || options[1].selected || !options[2].selected || document.activeElement !== select) return false;
      if (declaredInputValue(select) !== 'a\x1fc') return false;

      // Patch data-select-values to select b and c only
      dom.applyPatchStream('A\t2\tdata-select-values\tb\x1fc\n');
      if (options[0].selected || !options[1].selected || !options[2].selected || document.activeElement !== select) return false;
      if (declaredInputValue(select) !== 'b\x1fc') return false;

      // Option replacement retains multiple selection
      dom.applyPatchStream('H\t2\t' + JSON.stringify('<option value="b">B</option><option value="c">C</option><option value="d">D</option>') + '\n');
      return options[0].selected && options[1].selected && !options[2].selected && document.activeElement === select;
    }), true);
  } finally { await browser?.close(); await server.close(); }
});

test('explicit radio values retain choice payload, identity and focus', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    const result = await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const { declaredInputValue } = await import('/local-datetime.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<fieldset data-node-id="1"><input type="radio" name="range" value="one" data-input-kind="2" data-value-format="value" data-node-id="2" checked><input type="radio" name="range" value="all" data-input-kind="2" data-value-format="value" data-node-id="3"><input type="checkbox" data-value-format="checked" data-node-id="4"></fieldset>');
      const owner = root.firstElementChild, one = root.querySelector('[value="one"]'), all = root.querySelector('[value="all"]');
      const values = [];
      root.addEventListener('change', event => values.push(declaredInputValue(event.target)));
      all.focus(); all.click();
      dom.applyPatchStream('C\t2\tfalse\nC\t3\ttrue\n');
      const retained = all === root.querySelector('[value="all"]') && all.isConnected && all === document.activeElement && owner === root.firstElementChild;
      one.click();
      root.querySelector('[type="checkbox"]').click();
      return { values, retained, oneChecked: one.checked, allChecked: all.checked };
    });
    assert.deepEqual(result, { values: ['all', 'one', 'true'], retained: true, oneChecked: true, allChecked: false });
  } finally { await browser?.close(); await server.close(); }
});

test('numeric style and scroll leaves retain scroller and focused sibling', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const css = document.createElement('style');
      css.textContent = '.viewport{height:100px;overflow:auto}.spacer{height:calc(var(--extent)*1px)}';
      document.head.append(css);
      const dom = createDomHost({ root });
      dom.initialize('<input data-node-id="1" value="draft"><div class="viewport" data-node-id="2" data-scroll-top="0"><div class="spacer" data-node-id="3" data-style-vars="--extent:400;--offset:4px;--opacity:100%"></div></div>');
      const input = root.firstChild, viewport = root.lastChild, spacer = viewport.firstChild;
      input.focus();
      dom.applyPatchStream('A\t3\tdata-style-vars\t--extent:800;--offset:-12px;--opacity:80%\nA\t2\tdata-scroll-top\t500\n');
      return input === document.activeElement && input.value === 'draft' && viewport === root.lastChild && spacer === viewport.firstChild && spacer.getBoundingClientRect().height === 800 && viewport.scrollTop === 500 && spacer.style.getPropertyValue("--offset") === "-12px" && spacer.style.getPropertyValue("--opacity") === "80%";
    }), true);
  } finally { await browser?.close(); await server.close(); }
});

test('clearing optional styles removes only declared properties and retains focus', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    const result = await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<section><input value="draft"><div data-node-id="1" data-style-vars="--gap:12px;--opacity:80%"><span data-style-vars="--gap:3px"></span></div></section>');
      const parent = root.firstElementChild, input = parent.firstElementChild;
      const target = parent.lastElementChild, child = target.firstElementChild;
      target.style.setProperty('--unrelated', '7');
      input.focus(); input.setSelectionRange(1, 3);
      dom.applyPatchStream('R\t1\tdata-style-vars\nR\t1\tdata-style-vars\n');
      const cleared = !target.hasAttribute('data-style-vars')
        && target.style.getPropertyValue('--gap') === ''
        && target.style.getPropertyValue('--opacity') === '';
      dom.applyPatchStream('A\t1\tdata-style-vars\t--gap:4px;--opacity:50%\n');
      return {
        cleared,
        restored: target.style.getPropertyValue('--gap') === '4px'
          && target.style.getPropertyValue('--opacity') === '50%',
        unrelated: target.style.getPropertyValue('--unrelated') === '7'
          && child.style.getPropertyValue('--gap') === '3px',
        retained: root.firstElementChild === parent && parent.lastElementChild === target
          && target.firstElementChild === child && parent.firstElementChild === input
          && document.activeElement === input && input.value === 'draft'
          && input.selectionStart === 1 && input.selectionEnd === 3,
      };
    });
    assert.deepEqual(result, { cleared: true, restored: true, unrelated: true, retained: true });
  } finally { await browser?.close(); await server.close(); }
});

test('image source updates retain image and focused sibling', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.route('**/*.png', route => route.fulfill({status:204}));
    await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<input data-node-id="1" value="draft"><img data-node-id="2" alt="Preview" src="/one.png">');
      const input = root.firstChild, image = root.lastChild;
      input.focus();
      dom.applyPatchStream('A\t2\tsrc\t/two.png\n');
      if (image.getAttribute('src') !== '/two.png') return false;
      dom.applyPatchStream('R\t2\tsrc\n');
      return image === root.lastChild && !image.hasAttribute('src') && input === document.activeElement && input.value === 'draft';
    }), true);
  } finally { await browser?.close(); await server.close(); }
});

test('description value child updates retain semantic owners and sibling focus', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<dl data-node-id="1"><dt data-node-id="2">Value</dt><dd data-node-id="3"><span data-node-id="4">Before</span></dd><dt>Draft</dt><dd><input data-node-id="5" value="keep"></dd></dl>');
      const list = root.firstChild, term = list.firstChild, value = list.querySelector('dd'), text = value.firstChild, peer = list.querySelector('input');
      peer.focus(); peer.setSelectionRange(1, 3);
      dom.applyPatchStream('T\t4\t"After"\n');
      return root.firstChild === list && list.firstChild === term && value.isConnected
        && value.firstChild === text && text.textContent === 'After'
        && peer === document.activeElement && peer.value === 'keep'
        && peer.selectionStart === 1 && peer.selectionEnd === 3;
    }), true);
  } finally { await browser?.close(); await server.close(); }
});

test('option group leaf and membership changes preserve focused select', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const host = createDomHost({ root });
      host.initialize('<select data-node-id="1" data-select-value="b"><optgroup data-node-id="2" label="Choices"><option data-node-id="3" value="b">Before</option></optgroup></select><input>');
      const select = root.firstElementChild, group = select.firstElementChild, option = group.firstElementChild, peer = root.lastElementChild;
      select.focus();
      host.applyPatchStream('T\t3\t"After"\nA\t3\tdisabled\t\n');
      if (group.firstElementChild !== option || select.value !== 'b') return false;
      host.applyPatchStream('H\t2\t' + JSON.stringify('<option value="a">A</option><option value="b">B</option>') + '\n');
      return root.firstElementChild === select && select.firstElementChild === group && root.lastElementChild === peer && select.value === 'b' && document.activeElement === select;
    }), true);
  } finally { await browser?.close(); await server.close(); }
});

test('meter changes retain a focused sibling and reject out-of-range values', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage(); await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const host = createDomHost({ root });
      host.initialize('<section><meter data-node-id="1" min="0" max="100" value="0"></meter><input value="draft"></section>');
      const panel = root.firstElementChild, meter = panel.firstElementChild, peer = panel.lastElementChild;
      peer.focus(); peer.setSelectionRange(1, 3);
      host.applyPatchStream('A\t1\tvalue\t100\n');
      let rejected = 0;
      for (const value of ['-1', '101', 'NaN', 'Infinity']) {
        try { host.applyPatchStream('A\t1\tvalue\t' + value + '\n'); } catch { rejected++; }
      }
      return rejected === 4 && meter.value === 100 && root.firstElementChild === panel && panel.firstElementChild === meter && document.activeElement === peer && peer.selectionStart === 1 && peer.selectionEnd === 3;
    }), true);
  } finally { await browser?.close(); await server.close(); }
});

test('navigation leaves retain the nav, focused button and sibling selection', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<nav aria-label="Sections" data-node-id="1"><button data-node-id="2">Before</button></nav><input value="draft" data-node-id="3">');
      const nav = root.firstChild, button = nav.firstChild, peer = root.lastChild;
      button.focus();
      dom.applyPatchStream('T\t2\t"After"\nA\t2\taria-current\tpage\n');
      const buttonRetained = nav === root.firstChild && button === nav.firstChild && button === document.activeElement && button.textContent === 'After';
      peer.focus(); peer.setSelectionRange(1, 3);
      dom.applyPatchStream('R\t2\taria-current\n');
      return buttonRetained && nav === root.firstChild && button === nav.firstChild && nav.isConnected
        && peer === document.activeElement && peer.value === 'draft'
        && peer.selectionStart === 1 && peer.selectionEnd === 3;
    }), true);
  } finally { await browser?.close(); await server.close(); }
});


test('roving tab index leaves retain both controls and current focus', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<div data-node-id="1"><button data-node-id="2" tabindex="0">First</button><button data-node-id="3" tabindex="-1">Second</button></div>');
      const parent = root.firstChild, first = parent.firstChild, second = parent.lastChild;
      first.focus();
      dom.applyPatchStream('A\t2\ttabindex\t-1\nA\t3\ttabindex\t0\n');
      return parent === root.firstChild && first === parent.firstChild && second === parent.lastChild && first === document.activeElement && first.tabIndex === -1 && second.tabIndex === 0;
    }), true);
  } finally { await browser?.close(); await server.close(); }
});

test('fractional progress changes retain a focused sibling and reject out-of-range values', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage(); await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const host = createDomHost({ root });
      host.initialize('<section><progress data-node-id="1" max="100" value="0.25"></progress><input value="draft"></section>');
      const panel = root.firstElementChild, meter = panel.firstElementChild, peer = panel.lastElementChild;
      peer.focus(); peer.setSelectionRange(1, 3);
      host.applyPatchStream('A\t1\tvalue\t99.75\n');
      let rejected = 0;
      for (const value of ['-1', '101', 'NaN', 'Infinity']) {
        try { host.applyPatchStream('A\t1\tvalue\t' + value + '\n'); } catch { rejected++; }
      }
      host.applyPatchStream('A\t1\tmax\t250.5\nA\t1\tvalue\t200.25\n');
      host.applyPatchStream('A\t1\tmax\t0.75\nA\t1\tvalue\t0.5\n');
      return rejected === 4 && meter.value === 0.5 && meter.max === 0.75 && root.firstElementChild === panel && panel.firstElementChild === meter && document.activeElement === peer && peer.selectionStart === 1 && peer.selectionEnd === 3;
    }), true);
  } finally { await browser?.close(); await server.close(); }
});
test('sandboxed frame sources retain the document owner and sibling focus', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.route('**/frame-*', route => route.fulfill({ contentType: 'text/html', body: '<p>Preview</p>' }));
    await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<input data-node-id="1" value="draft"><iframe data-node-id="2" title="Preview" sandbox="" src="about:blank"></iframe>');
      const input = root.firstChild, frame = root.lastChild;
      input.focus();
      dom.applyPatchStream('A\t2\tsrc\t/frame-one\nA\t2\thidden\t\nR\t2\thidden\n');
      for (const source of ['javascript:alert(1)', 'data:text/html,test', 'https://external.test/frame-one', 'https://name:secret@external.test/frame-one']) {
        let rejected = false;
        try { dom.applyPatchStream(`A\t2\tsrc\t${source}\n`); } catch { rejected = true; }
        if (!rejected) return false;
      }
      frame.setAttribute('data-external-frame', 'true');
      dom.applyPatchStream('A\t2\tsrc\thttps://external.test/frame-two\nA\t2\tsrc\tabout:blank\n');
      return frame === root.lastChild && frame.isConnected && input === document.activeElement && input.value === 'draft' && frame.getAttribute('src') === 'about:blank';
    }), true);
  } finally { await browser?.close(); await server.close(); }
});

test('native constraints preserve a focused input and its draft', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<input data-node-id="1" type="number" value="12" max="20">');
      const input = root.firstChild; input.focus();
      dom.applyPatchStream('A\t1\trequired\t\nA\t1\tmin\t5\nR\t1\tmax\nA\t1\tstep\tany\n');
      return input === root.firstChild && input === document.activeElement && input.value === '12' && input.required && input.min === '5' && input.max === '' && input.step === 'any';
    }), true);
  } finally { await browser?.close(); await server.close(); }
});

test('external link updates retain the link and focused sibling', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage(); await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<a data-node-id="1" data-external-link="true">Open</a><input value="draft">');
      const link = root.firstChild, input = root.lastChild; input.focus();
      dom.applyPatchStream('A\t1\thref\thttps://example.test/?a=1&b=2\n');
      if (link.getAttribute('href') !== 'https://example.test/?a=1&b=2') return false;
      dom.applyPatchStream('A\t1\thref\thttp://example.test/plain\n');
      if (link.getAttribute('href') !== 'http://example.test/plain') return false;
      dom.applyPatchStream('A\t1\thref\t#section-2\n');
      if (link.getAttribute('href') !== '#section-2') return false;
      dom.applyPatchStream('R\t1\thref\n');
      return link === root.firstChild && !link.hasAttribute('href') && input === document.activeElement && input.value === 'draft';
    }), true);
  } finally { await browser?.close(); await server.close(); }
});

test('cell updates retain row, sibling control, focus and valid table structure', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    assert.equal(await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<table data-node-id="1"><tbody data-node-id="2"><tr data-node-id="3"><th data-node-id="4">Label</th><td data-node-id="5"><input data-node-id="6" value="draft"></td></tr></tbody></table>');
      const table = root.querySelector('table'), row = table.rows[0], input = root.querySelector('input');
      input.focus(); input.setSelectionRange(1, 3);
      dom.applyPatchStream('T\t4\t"Changed"\n');
      return table === root.querySelector('table') && row === table.rows[0]
        && row.cells.length === 2 && input === document.activeElement
        && input.isConnected && input.value === 'draft'
        && input.selectionStart === 1 && input.selectionEnd === 3;
    }), true);
  } finally { await browser?.close(); await server.close(); }
});

test('input kind patches retain the input, value, sibling and focus', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<div data-node-id="601"><input data-node-id="602" type="password" value="draft"><input data-node-id="603" value="sibling"></div>');
      const control = root.querySelector('[data-node-id="602"]');
      const sibling = control.nextElementSibling;
      const parent = control.parentElement;
      control.focus(); control.setSelectionRange(1, 3);
      dom.applyPatchStream('A\t601\tdir\trtl\nA\t602\tname\tsecret\nA\t602\tautocomplete\toff\n');
      if (parent.dir !== 'rtl' || control.name !== 'secret' || control.autocomplete !== 'off') throw new Error('metadata patch failed');
      for (const type of ['text', 'password']) {
        dom.applyPatchStream(`A\t602\ttype\t${type}\n`);
        if (control !== document.activeElement || control.parentElement !== parent ||
            control.nextElementSibling !== sibling || control.value !== 'draft' ||
            control.type !== type || control.selectionStart !== 1 || control.selectionEnd !== 3) {
          throw new Error('kind update lost a retained control, selection or value');
        }
      }
    });
  } finally { if (browser) await browser.close(); await server.close(); }
});

test('object image patches require same-origin permission and retain controls', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage(); await page.goto(server.url + '/dom.js');
    await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<img data-node-id="1" data-object-image="true" alt="Preview"><input data-node-id="2" value="draft"><img data-node-id="3" alt="Ordinary">');
      const image = root.querySelector('[data-node-id="1"]');
      const input = root.querySelector('input'); input.focus();
      const url = URL.createObjectURL(new Blob(['<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"><rect width="1" height="1"/></svg>'], { type: 'image/svg+xml' }));
      try {
        const loaded = new Promise((resolve, reject) => { image.onload = resolve; image.onerror = reject; });
        dom.applyPatchStream(`A\t1\tsrc\t${url}\n`); await loaded;
        let rejected = 0;
        for (const [id, source] of [[3, url], [1, 'blob:https://elsewhere.test/id'], [1, 'blob:null/id']]) {
          try { dom.applyPatchStream(`A\t${id}\tsrc\t${source}\n`); } catch { rejected++; }
        }
        if (rejected !== 3 || image !== root.firstElementChild || input !== document.activeElement || input.value !== 'draft' || !image.naturalWidth) throw new Error('object image permission or identity failed');
        dom.applyPatchStream('R\t1\tsrc\n');
        if (image.hasAttribute('src') || input !== document.activeElement) throw new Error('removal changed image or focus');
      } finally { URL.revokeObjectURL(url); }
    });
  } finally { if (browser) await browser.close(); await server.close(); }
});

test('node registry tracks structural ownership, external mutations and resync', async () => {
  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    const result = await page.evaluate(async () => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize('<div data-node-id="1"><input data-node-id="2" value="draft"><span data-node-id="3"><b data-node-id="4">old</b></span></div>');
      const input = root.querySelector('input'); input.focus();
      // A leaf-only stream must never perform another root-wide query.
      const query = root.querySelectorAll.bind(root);
      let scans = 0;
      root.querySelectorAll = (...args) => { scans++; return query(...args); };
      for (let i = 0; i < 100; i++) dom.applyPatchStream(`A\t2\taria-label\t${i}\n`);
      const noRescan = scans === 0;
      const rejects = stream => { try { dom.applyPatchStream(stream); return false; } catch { return true; } };
      dom.applyPatchStream('T\t3\t"text"\n');
      const textRemoved = rejects('T\t4\t"absent"\n');
      dom.applyPatchStream('H\t3\t"<i data-node-id=\\"4\\">new</i>"\nT\t4\t"updated"\n');
      const newOwner = root.querySelector('i');
      dom.applyPatchStream('J\t3\t"<b data-node-id=\\"5\\">second</b>"\nM\t5\t4\tbefore\n');
      const moved = newOwner.isConnected && root.querySelector('[data-node-id="3"]').lastElementChild === newOwner;
      dom.applyPatchStream('D\t4\n');
      const deleted = rejects('T\t4\t"absent"\n');
      root.querySelector('[data-node-id="3"]').insertAdjacentHTML('beforeend', '<i data-node-id="5">duplicate</i>');
      const duplicateSameTask = rejects('T\t5\t"ambiguous"\n');
      root.querySelector('i').remove();
      dom.applyPatchStream('T\t5\t"unique"\n');
      const control = root.querySelector('b');
      control.setAttribute('data-node-id', '6');
      const oldIdGone = rejects('T\t5\t"old"\n');
      dom.applyPatchStream('T\t6\t"new identity"\n');
      await Promise.resolve(); // Observer callback records must also be drained.
      const outside = document.createElement('i'); outside.dataset.nodeId = '6'; root.append(outside);
      await new Promise(resolve => setTimeout(resolve, 0));
      const duplicateLater = rejects('T\t6\t"ambiguous"\n');
      outside.remove();
      const retained = input.isConnected && input === document.activeElement && input.value === 'draft';
      dom.initialize('<span data-node-id="2">reset</span>');
      dom.applyPatchStream('T\t2\t"recovered"\n');
      const recovered = root.textContent === 'recovered' && !input.isConnected;
      dom.dispose();
      return { noRescan, textRemoved, moved, deleted, duplicateSameTask, oldIdGone, duplicateLater, retained, recovered };
    });
    assert.ok(Object.values(result).every(Boolean), JSON.stringify(result));
  } finally { await browser.close(); await server.close(); }
});
