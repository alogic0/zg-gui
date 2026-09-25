import { createDomHost, createFrameSyncHost } from '../web/dom.js';
import { chromium } from 'playwright';
import { serve } from '../tools/server.mjs';

export async function runBenchmarks() {
  console.log('=== zg-gui Performance & Binary Patch Benchmark Suite ===\n');

  const server = await serve({ directory: new URL('../web', import.meta.url).pathname });
  let browser;

  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');

    const results = await page.evaluate(async () => {
      const { createDomHost, createFrameSyncHost } = await import('/dom.js');

      // 1. Throughput Benchmark: Leaf Attribute Patches
      const root1 = document.createElement('div');
      document.body.append(root1);
      const dom1 = createDomHost({ root: root1 });
      dom1.initialize('<div data-node-id="1" data-count="0">Benchmark Host</div>');

      const iterations = 10000;
      let batch = '';
      for (let i = 0; i < iterations; i++) {
        batch += `A\t1\tdata-count\t${i}\n`;
      }

      const t0 = performance.now();
      dom1.applyPatchStream(batch);
      const t1 = performance.now();
      const patchDurationMs = t1 - t0;
      const patchOpsPerSec = Math.round((iterations / patchDurationMs) * 1000);

      dom1.dispose();
      root1.remove();

      // 2. Zero-Copy MessagePort Binary Transfer Latency
      const root2 = document.createElement('div');
      document.body.append(root2);
      const channel = new MessageChannel();
      const frameHost = createFrameSyncHost({ root: root2, port: channel.port1 });
      frameHost.dom.initialize('<div data-node-id="1"><span data-node-id="2">Sync</span></div>');

      const transferCount = 1000;
      const payloadSize = 1024; // 1KB per patch frame
      const encoder = new TextEncoder();
      const rawText = 'T\t2\t"Transferred"\n';
      const encoded = encoder.encode(rawText);

      const tTransfer0 = performance.now();
      for (let i = 0; i < transferCount; i++) {
        const buffer = new ArrayBuffer(payloadSize);
        new Uint8Array(buffer).set(encoded);
        channel.port2.postMessage({
          type: 'zg:patch-stream',
          buffer,
        }, [buffer]);
      }

      // Wait for port delivery to drain
      await new Promise(resolve => setTimeout(resolve, 150));
      const tTransfer1 = performance.now();
      const transferDurationMs = tTransfer1 - tTransfer0;
      const latencyPerTransferUs = ((transferDurationMs / transferCount) * 1000).toFixed(2);
      const transferThroughputKbSec = Math.round((transferCount * payloadSize / 1024) / (transferDurationMs / 1000));

      frameHost.dispose();
      channel.port1.close();
      channel.port2.close();
      root2.remove();

      // 3. FLIP Layout Transition Calculation Latency
      const root3 = document.createElement('div');
      document.body.prepend(root3);
      const dom3 = createDomHost({ root: root3 });

      const itemCount = 200;
      let listHtml = '<div data-node-id="1000">';
      for (let i = 0; i < itemCount; i++) {
        listHtml += `<div data-node-id="${i + 1}" data-layout-id="card-${i}" style="height:25px;">Card ${i}</div>`;
      }
      listHtml += '</div>';
      dom3.initialize(listHtml);

      // Reorder: Move first element after last
      const tFlip0 = performance.now();
      dom3.applyPatchStream(`M\t1\t${itemCount}\tafter\n`);
      const tFlip1 = performance.now();
      const flipDurationMs = (tFlip1 - tFlip0).toFixed(3);

      dom3.dispose();
      root3.remove();

      // 4. Memory Retention / GC Stability Probe
      const root4 = document.createElement('div');
      document.body.append(root4);
      const dom4 = createDomHost({ root: root4 });
      dom4.initialize('<div data-node-id="1">Memory Probe</div>');

      const initialMemory = window.performance?.memory?.usedJSHeapSize || 0;
      for (let cycle = 0; cycle < 5; cycle++) {
        let stream = '';
        for (let j = 0; j < 2000; j++) {
          stream += `A\t1\tdata-metric\t${j}\n`;
        }
        dom4.applyPatchStream(stream);
      }
      const finalMemory = window.performance?.memory?.usedJSHeapSize || 0;
      const heapDeltaKb = Math.round((finalMemory - initialMemory) / 1024);

      dom4.dispose();
      root4.remove();

      return {
        iterations,
        patchDurationMs: patchDurationMs.toFixed(2),
        patchOpsPerSec,
        transferCount,
        transferDurationMs: transferDurationMs.toFixed(2),
        latencyPerTransferUs,
        transferThroughputKbSec,
        itemCount,
        flipDurationMs,
        heapDeltaKb: Number.isFinite(heapDeltaKb) ? heapDeltaKb : 0,
      };
    });

    console.log(`1. DOM Mutation Throughput:`);
    console.log(`   - Operations: ${results.iterations.toLocaleString()} patches`);
    console.log(`   - Total Time: ${results.patchDurationMs} ms`);
    console.log(`   - Throughput: ${results.patchOpsPerSec.toLocaleString()} ops/sec\n`);

    console.log(`2. Zero-Copy MessagePort Transfer:`);
    console.log(`   - Frames: ${results.transferCount.toLocaleString()} ArrayBuffer packets`);
    console.log(`   - Average Latency: ${results.latencyPerTransferUs} µs / transfer`);
    console.log(`   - Throughput: ${results.transferThroughputKbSec.toLocaleString()} KB/sec\n`);

    console.log(`3. FLIP Layout Coordinator:`);
    console.log(`   - Tracked Elements: ${results.itemCount} items`);
    console.log(`   - Rect Invert & Transition Time: ${results.flipDurationMs} ms\n`);

    console.log(`4. Memory Retention Probe:`);
    console.log(`   - Heap Delta over 10k mutations: ${results.heapDeltaKb} KB\n`);

    console.log('=== All Benchmarks Completed Successfully ===');
    return results;
  } finally {
    if (browser) await browser.close();
    await server.close();
  }
}

// Execute directly if invoked via node
if (process.argv[1] && process.argv[1].endsWith('benchmark.mjs')) {
  runBenchmarks().catch((err) => {
    console.error('Benchmark failed:', err);
    process.exit(1);
  });
}
