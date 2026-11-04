const {mount}=await import('/runtime.js');
const root=document.createElement('main');document.body.append(root);
const memory=new WebAssembly.Memory({initial:1});let mode=0,length=0,calls=0;
const write=(text,nextMode)=>{const bytes=new TextEncoder().encode(text);new Uint8Array(memory.buffer,0,bytes.length).set(bytes);length=bytes.length;mode=nextMode;return length;};
const wasm={memory,init:()=>write('<section data-node-id="1"><input data-node-id="2" value="steady"><button data-node-id="3" data-event="1">Action</button></section>',0),getRenderBuffer:()=>0,getRenderLength:()=>length,getRenderMode:()=>mode,
dispatch:action=>{if(action===1){calls++;return write('R\t3\tdata-event\n',1);}return write('A\t3\tdata-event\t1\n',1);}};
wasm.resync=wasm.init;wasm.setInput=()=>write('',1);wasm.getExchangeBuffer=()=>8192;wasm.getExchangeCapacity=()=>256;
const app=mount({root,wasm}),parent=root.firstElementChild,input=root.querySelector('input'),button=root.querySelector('button');
input.focus();input.setSelectionRange(1,3);button.click();assert.equal(calls,1);assert.ok(!button.hasAttribute('data-event'));button.click();assert.equal(calls,1);
assert.equal(document.activeElement,input);assert.equal(input.selectionStart,1);assert.equal(root.firstElementChild,parent);assert.equal(root.querySelector('button'),button);
button.focus();app.dispatch({action:2});assert.equal(document.activeElement,button);assert.equal(root.querySelector('button'),button);button.click();assert.equal(calls,2);
app.dispose();root.remove();return true;
