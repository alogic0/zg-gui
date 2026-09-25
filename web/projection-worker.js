const requiredExports = [
  'init', 'resync', 'dispatch', 'setInput', 'getRenderBuffer',
  'getRenderLength', 'getRenderMode', 'getExchangeBuffer', 'getExchangeCapacity'
];

export function createProjectionRunner({ postMessage = (msg, transfer) => self.postMessage(msg, transfer) } = {}) {
  const bufferPool = [];
  const maxPoolCapacity = 8;
  const encoder = new TextEncoder();
  let wasm = null;

  function acquireBuffer(minCapacity) {
    for (let i = 0; i < bufferPool.length; i++) {
      if (bufferPool[i].byteLength >= minCapacity) {
        return bufferPool.splice(i, 1)[0];
      }
    }
    return new ArrayBuffer(Math.max(minCapacity, 16384));
  }

  function releaseBuffer(buffer) {
    if (buffer instanceof ArrayBuffer && bufferPool.length < maxPoolCapacity) {
      bufferPool.push(buffer);
    }
  }

  function sendRender(length = wasm.getRenderLength()) {
    const mode = wasm.getRenderMode();
    const ptr = wasm.getRenderBuffer();
    const buffer = acquireBuffer(length);
    new Uint8Array(buffer, 0, length).set(new Uint8Array(wasm.memory.buffer, ptr, length));
    postMessage({ type: 'render', mode, length, buffer }, [buffer]);
  }

  function writeExchange(value) {
    const capacity = wasm.getExchangeCapacity();
    const target = new Uint8Array(wasm.memory.buffer, wasm.getExchangeBuffer(), capacity);
    const { read, written } = encoder.encodeInto(value, target);
    if (read !== value.length) {
      target.fill(0, 0, written);
      throw new RangeError(`WASM exchange payload exceeds ${capacity} bytes`);
    }
    return written;
  }

  async function handleMessage(msg) {
    if (!msg || typeof msg !== 'object') return;
    try {
      switch (msg.type) {
        case 'init': {
          let wasmModule = msg.wasmModule;
          if (!wasmModule && msg.wasmBytes) {
            wasmModule = await WebAssembly.compile(msg.wasmBytes);
          } else if (!wasmModule && msg.wasmUrl) {
            const resp = await fetch(msg.wasmUrl);
            if (!resp.ok) throw new Error(`WASM fetch failed: ${resp.status}`);
            wasmModule = await WebAssembly.compile(await resp.arrayBuffer());
          }
          if (!wasmModule) throw new Error('Worker init requires wasmUrl, wasmBytes, or wasmModule');
          const instance = await WebAssembly.instantiate(wasmModule, msg.imports || {});
          wasm = instance.exports;
          for (const name of requiredExports) {
            if (typeof wasm[name] !== 'function') throw new Error(`Missing WASM export: ${name}`);
          }
          if (!(wasm.memory instanceof WebAssembly.Memory)) throw new Error('Missing WASM memory');
          sendRender(wasm.init());
          postMessage({ type: 'ready' });
          break;
        }
        case 'dispatch': {
          if (!wasm) throw new Error('Worker WASM not initialized');
          const { action, value = 0 } = msg;
          if (!Number.isInteger(action) || action <= 0 || action > 0xffffffff
            || !Number.isInteger(value) || value < -0x80000000 || value > 0x7fffffff) {
            throw new RangeError('Invalid action or signed action value');
          }
          sendRender(wasm.dispatch(action, value));
          break;
        }
        case 'setInput': {
          if (!wasm) throw new Error('Worker WASM not initialized');
          const { kind, value } = msg;
          if (!Number.isInteger(kind) || kind <= 0 || kind > 0xffffffff || typeof value !== 'string') {
            throw new TypeError('Input requires a positive kind and string value');
          }
          const written = writeExchange(value);
          sendRender(wasm.setInput(kind, written));
          break;
        }
        case 'recycle': {
          releaseBuffer(msg.buffer);
          break;
        }
        case 'resync': {
          if (!wasm) throw new Error('Worker WASM not initialized');
          sendRender(wasm.resync());
          break;
        }
        case 'ping': {
          postMessage({
            type: 'pong',
            poolSize: bufferPool.length,
            timestamp: typeof performance !== 'undefined' ? performance.now() : Date.now()
          });
          break;
        }
        case 'dispose': {
          wasm = null;
          bufferPool.length = 0;
          if (typeof self !== 'undefined' && typeof self.close === 'function') {
            self.close();
          }
          break;
        }
        default:
          throw new Error(`Unknown message type: ${msg.type}`);
      }
    } catch (error) {
      postMessage({ type: 'error', message: error.message, stack: error.stack });
    }
  }

  return {
    handleMessage,
    getPoolSize: () => bufferPool.length,
    dispose: () => {
      wasm = null;
      bufferPool.length = 0;
    }
  };
}

if (typeof self !== 'undefined' && typeof self.postMessage === 'function' && typeof window === 'undefined') {
  const runner = createProjectionRunner({
    postMessage: (msg, transfer) => self.postMessage(msg, transfer)
  });
  self.onmessage = (event) => runner.handleMessage(event.data);
}
