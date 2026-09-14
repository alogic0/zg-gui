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
      const owner = root.firstElementChild;
      const input = root.querySelector('[data-node-id="2"]');
      input.focus(); input.setSelectionRange(1, 3);
      dom.applyPatchStream('T\t3\t"two\\n🧭"\nA\t3\taria-label\tlabel\nC\t4\ttrue\n');
      const retained = owner === root.firstElementChild && input.isConnected && document.activeElement === input && input.selectionStart === 1 && input.selectionEnd === 3;
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
