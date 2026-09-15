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
      dom.initialize('<input data-node-id="1" value="draft"><div class="viewport" data-node-id="2" data-scroll-top="0"><div class="spacer" data-node-id="3" data-style-vars="--extent:400"></div></div>');
      const input = root.firstChild, viewport = root.lastChild, spacer = viewport.firstChild;
      input.focus();
      dom.applyPatchStream('A\t3\tdata-style-vars\t--extent:800\nA\t2\tdata-scroll-top\t500\n');
      return input === document.activeElement && input.value === 'draft' && viewport === root.lastChild && spacer === viewport.firstChild && spacer.getBoundingClientRect().height === 800 && viewport.scrollTop === 500;
    }), true);
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
