const {createBrowserHost}=await import('/browser-host.js');
const {createDomHost}=await import('/dom.js');
const {mount}=await import('/runtime.js');
const root=document.createElement('main'); document.body.append(root);
const memory=new WebAssembly.Memory({initial:1});
let length=0;
const wasm={memory,getHostBuffer:()=>0,getHostLength:()=>length};
const encoder=new TextEncoder(), decoder=new TextDecoder();
function batch(value) {const bytes=encoder.encode(JSON.stringify(value));new Uint8Array(memory.buffer).set(bytes);length=bytes.length;}
const events=[],errors=[];
const browser=createBrowserHost({root,wasm,onEvent:event=>events.push({kind:event.kind,value:JSON.parse(event.value)}),onError:e=>errors.push(e)});
const dom=createDomHost({root,onPatch:()=>browser.sync()});
const markup='<button data-node-id="1">Open</button><input data-node-id="2" value="draft"><dialog data-node-id="3"><button data-node-id="4">First</button><button data-node-id="5">Second</button></dialog>';
const dialog=open=>({kind:'dialog',node:3,open,cancel:8,revision:open?1:0});
const focus=(node,revision,guard='always')=>({kind:'focus',owner:1,node,revision,guard,mode:'preserve_scroll'});
const frame=revision=>({kind:'frame',owner:1,revision,event:9});
const scheme={kind:'scheme',value:'dark',key:'test-appearance',revision:1};
const preferences={kind:'preferences',owner:1,event:7,key:'test-appearance'};
batch([dialog(false),scheme,preferences]); dom.initialize(markup);
assert.equal(events.length,0); // No reentrant callback from onPatch.
await Promise.resolve(); assert.equal(events[0].kind,7); assert.equal(events[0].value.stored,'dark');
assert.equal(document.documentElement.dataset.theme,'dark');
const input=root.querySelector('input'), target=root.querySelector('dialog'); input.focus();
batch([dialog(false),focus(1,1,'if_body')]); browser.sync(); assert.equal(document.activeElement,input);
input.blur(); browser.sync(); assert.notEqual(document.activeElement,root.querySelector('button'));
batch([dialog(true),focus(5,2)]); browser.sync();
assert.ok(target.open); assert.equal(document.activeElement,root.querySelector('[data-node-id="5"]'));
target.dispatchEvent(new Event('cancel',{bubbles:false,cancelable:true}));
assert.equal(events.length,1); await Promise.resolve(); assert.equal(events[1].kind,8); assert.equal(events[1].value.revision,1);
batch([dialog(false),focus(1,3)]); browser.sync(); assert.ok(!target.open); assert.equal(document.activeElement,root.querySelector('button'));
assert.equal(root.querySelector('input'),input); assert.equal(input.value,'draft');
batch([dialog(false),frame(11)]); browser.sync(); browser.sync();
await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
assert.equal(events.filter(e=>e.kind===9&&e.value.revision===11).length,1);
browser.sync(); await new Promise(r=>requestAnimationFrame(r));
assert.equal(events.filter(e=>e.kind===9).length,1);
batch([dialog(false),{...frame(11),event:10}]);browser.sync();
await new Promise(r=>requestAnimationFrame(r));assert.ok(!events.some(e=>e.kind===10));
batch([dialog(false),frame(12)]);browser.sync(); batch([dialog(false),frame(13)]);browser.sync();
await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
assert.ok(!events.some(e=>e.kind===9&&e.value.revision===12)); assert.ok(events.some(e=>e.kind===9&&e.value.revision===13));
// Validate the whole batch before applying its first command.
for(const bad of [[{...scheme,value:'light'},focus(999,4)], [{...scheme,value:'invalid'}], [{...focus(1,4),selector:'body'}], [frame(0)], [frame(21),frame(22)], new Array(17).fill(dialog(false)), [{kind:'script',source:'evil'}]]) {
  batch(bad); let refused=false;try{browser.sync();}catch{refused=true;}assert.ok(refused);assert.equal(document.documentElement.dataset.theme,'dark');
}
batch([dialog(false)]);browser.sync();
const getItem=Storage.prototype.getItem;
try {Storage.prototype.getItem=()=>{throw new Error('blocked');};batch([dialog(false),preferences]);browser.sync();}
finally {Storage.prototype.getItem=getItem;}
await Promise.resolve(); assert.equal(events.at(-1).value.storage_error,'unavailable');
// Full projection replaces nodes but reconciles native state without repeating focus.
batch([dialog(true),focus(5,5)]);dom.initialize(markup);assert.ok(root.querySelector('dialog').open);assert.ok(!target.isConnected);
batch([dialog(true),frame(14)]);browser.sync();
const count=events.length;browser.dispose();browser.dispose();
await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
assert.equal(events.length,count);assert.equal(browser.stats().frames,0);assert.equal(browser.stats().listeners,0);assert.equal(browser.stats().dialogs,0);
dom.dispose();root.remove();assert.equal(errors.length,0);

// Optional runtime ABI uses the ordinary bounded exchange and render contract.
const owner=document.createElement('div');document.body.append(owner);
const mem=new WebAssembly.Memory({initial:1});let mode=0,outLength=0,received=null;
function output(text,nextMode){const bytes=encoder.encode(text);new Uint8Array(mem.buffer,0,bytes.length).set(bytes);outLength=bytes.length;mode=nextMode;return outLength;}
const exports={memory:mem,init:()=>output('<p data-node-id="1">Initial</p>',0),resync:()=>output('<p data-node-id="1">Recovered</p>',0),dispatch:()=>output('',1),setInput:()=>output('',1),getRenderBuffer:()=>0,getRenderLength:()=>outLength,getRenderMode:()=>mode,getExchangeBuffer:()=>4096,getExchangeCapacity:()=>128,
 hostEvent:(kind,n)=>{received={kind,value:decoder.decode(new Uint8Array(mem.buffer,4096,n))};return output('T\t1\t"Updated"\n',1);}};
const app=mount({root:owner,wasm:exports});const paragraph=owner.firstElementChild;
app.hostEvent({kind:17,value:'event 🧭'});assert.deepEqual(received,{kind:17,value:'event 🧭'});assert.equal(owner.firstElementChild,paragraph);assert.equal(paragraph.textContent,'Updated');
let refused=false;try{app.hostEvent({kind:0,value:''});}catch{refused=true;}assert.ok(refused);
refused=false;try{app.hostEvent({kind:17,value:'x'.repeat(129)});}catch{refused=true;}assert.ok(refused);
app.dispose();owner.remove();return true;
