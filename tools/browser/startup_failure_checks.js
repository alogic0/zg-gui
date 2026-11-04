const {start,getApp,startDeclaredApps}=await import('/startup.js');
const encoder=new TextEncoder(),decoder=new TextDecoder();
const makeRoot=()=>{const root=document.createElement('div');document.body.append(root);return root;};
async function refused(options){let error;try{await start({...options,onError:()=>{}});}catch(e){error=e;}assert.ok(error,'Expected startup refusal');return error;}
const originalFetch=window.fetch;
try{
  const cases=[
    {version:2,wasm:'/demo.wasm',browser:false,math:false},
    {version:1,wasm:'/demo.wasm',browser:'yes',math:false},
    {version:1,wasm:'/demo.wasm',browser:false,math:false,files:false},
    {version:2,wasm:'/demo.wasm',browser:false,math:false,files:'yes'},
    {version:3,wasm:'/demo.wasm',browser:false,math:false,files:false},
    {version:1,wasm:'/demo.wasm',browser:false,math:false,script:'code'},
    {version:1,wasm:'javascript:code',browser:false,math:false},
    {version:1,wasm:'https://other.invalid/app.wasm',browser:false,math:false},
    {version:1,wasm:'/demo.wasm',browser:false},
    'x'.repeat(4097),new Uint8Array([255]),
  ];
  for(const value of cases){
    let requests=0;window.fetch=async()=>{requests++;return new Response(typeof value==='string'||value instanceof Uint8Array?value:JSON.stringify(value));};
    const root=makeRoot();await refused({root,manifest:'/app.json'});
    assert.equal(requests,1);assert.equal(getApp(root),undefined);assert.equal(root.dataset.zgStatus,'error');assert.ok(!root.hasAttribute('aria-busy'));root.remove();
  }
  let requests=0;window.fetch=async()=>{requests++;throw new Error('Should not fetch');};
  const root=makeRoot();await refused({root,manifest:'https://other.invalid/app.json'});assert.equal(requests,0);root.remove();
}finally{window.fetch=originalFetch;}

function nativeFixture(){
  const memory=new WebAssembly.Memory({initial:1}),events=[];
  let length=0,mode=0,hostLength=0,released=0;
  const markup='<p data-node-id="1">Ready</p><dialog data-node-id="3"><button data-event="1" data-node-id="4">Action</button><div data-math-surface><span hidden data-math-source>&lt;math class="zig-math" display="block"&gt;&lt;mi&gt;x&lt;/mi&gt;&lt;/math&gt;</span><span data-math-output></span></div></dialog><input type="file" data-text-open-kind="20" data-text-error-kind="21" data-text-revision="1" data-text-limit="32"><textarea data-node-id="5"></textarea>';
  function output(value,nextMode){const bytes=encoder.encode(value);new Uint8Array(memory.buffer,0,bytes.length).set(bytes);length=bytes.length;mode=nextMode;return length;}
  const wasm={memory,init:()=>output(markup,0),resync:()=>output(markup,0),dispatch:()=>output('',1),setInput:(kind,n)=>{events.push({kind,value:decoder.decode(new Uint8Array(memory.buffer,12288,n))});return output('',1);},getRenderBuffer:()=>0,getRenderLength:()=>length,getRenderMode:()=>mode,getExchangeBuffer:()=>12288,getExchangeCapacity:()=>1024,
    getHostBuffer:()=>8192,getHostLength:()=>hostLength,hostEvent:(kind,n)=>{events.push({kind,value:decoder.decode(new Uint8Array(memory.buffer,12288,n))});return output('',1);},deinit:()=>{released++;}};
  function batch(commands){const bytes=encoder.encode(JSON.stringify(commands));new Uint8Array(memory.buffer,8192,bytes.length).set(bytes);hostLength=bytes.length;}
  return {wasm,events,batch,released:()=>released};
}
const commands=[{kind:'dialog',node:3,open:true,cancel:7,revision:1},{kind:'focus',owner:1,node:4,revision:1,mode:'preserve_scroll',guard:'always'},
  {kind:'frame',owner:1,revision:1,event:8},{kind:'preferences',owner:1,event:9,key:'startup-test'}];
const root=makeRoot(),native=nativeFixture();native.batch(commands);
root.dataset.zgApp='/unused-manifest.json';
const pending=start({root,wasm:native.wasm,browser:true,math:true,files:true,onError:()=>{}});
const scan=startDeclaredApps();
await refused({root,wasm:native.wasm});const app=await pending;
assert.ok((await scan).includes(app));
assert.equal(getApp(root),app);assert.ok(root.querySelector('dialog').open);assert.equal(document.activeElement,root.querySelector('button'));
assert.equal(root.querySelector('math').namespaceURI,'http://www.w3.org/1998/Math/MathML');assert.equal(app.resources().math.surfaces,1);
assert.ok(native.events.some(e=>e.kind===9));
assert.equal(app.features.files,true);assert.equal(app.resources().files.controls,1);

native.wasm.dispatch=()=>{throw new Error('Rejected dispatch');};
for(let i=0;i<40;i++)root.querySelector('button').click();
assert.equal(app.resources().errors,40);assert.equal(app.diagnostics().length,32);
app.dispose();app.dispose();
await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
assert.ok(!native.events.some(e=>e.kind===8));assert.equal(native.released(),1);assert.equal(root.querySelector('math'),null);
assert.deepEqual(app.resources().browser,{disposed:true,frames:0,dialogs:0,preferences:0,revisions:0,listeners:0});
assert.deepEqual(app.resources().files,{disposed:true,controls:0,readers:0,urls:0,listeners:0});
assert.equal(app.resources().math.surfaces,0);assert.ok(!root.querySelector('dialog').open);assert.equal(getApp(root),undefined);
let rejected=false;try{app.dispatch({action:1});}catch{rejected=true;}assert.ok(rejected);root.remove();

// Fail after owning a frame and queuing one preference callback.
const failed=makeRoot(),broken=nativeFixture();broken.batch([...commands,{kind:'preferences',owner:2,event:10,key:'startup-second'}]);
const originalMedia=window.matchMedia;let calls=0;
try{window.matchMedia=(...args)=>{if(++calls===2)throw new Error('Unavailable media');return originalMedia.apply(window,args);};await refused({root:failed,wasm:broken.wasm,browser:true,math:true});}
finally{window.matchMedia=originalMedia;}
await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
assert.equal(broken.events.length,0);assert.equal(broken.released(),1);assert.equal(getApp(failed),undefined);assert.equal(failed.querySelector('math'),null);assert.ok(!failed.querySelector('dialog').open);
const retry=nativeFixture();const recovered=await start({root:failed,wasm:retry.wasm});recovered.dispose();assert.equal(retry.released(),1);failed.remove();
const initRoot=makeRoot(),initFailure=nativeFixture();initFailure.wasm.init=()=>{throw new Error('Native admission failure');};
await refused({root:initRoot,wasm:initFailure.wasm,browser:true});assert.equal(initFailure.released(),1);assert.equal(getApp(initRoot),undefined);initRoot.remove();
const missingEventRoot=makeRoot(),missingEvent=nativeFixture();delete missingEvent.wasm.hostEvent;
await refused({root:missingEventRoot,wasm:missingEvent.wasm,browser:true});assert.equal(missingEvent.released(),1);assert.equal(getApp(missingEventRoot),undefined);missingEventRoot.remove();
const cleanupRoot=makeRoot(),cleanupFailure=nativeFixture(),cleanupErrors=[];
cleanupFailure.wasm.deinit=()=>{throw new Error('Native cleanup failure');};
const cleanupApp=await start({root:cleanupRoot,wasm:cleanupFailure.wasm,onError:e=>cleanupErrors.push(e)});cleanupApp.dispose();
assert.equal(cleanupErrors.length,1);assert.equal(getApp(cleanupRoot),undefined);
const afterCleanup=await start({root:cleanupRoot,wasm:nativeFixture().wasm});afterCleanup.dispose();cleanupRoot.remove();
const fileEventRoot=makeRoot(),fileNative=nativeFixture(),fileEventApp=await start({root:fileEventRoot,wasm:fileNative.wasm,files:true});
const transfer=new DataTransfer();transfer.items.add(new File(['opened text'],'sample.txt'));fileEventRoot.querySelector('input').files=transfer.files;fileEventRoot.querySelector('input').dispatchEvent(new Event('change',{bubbles:true}));
for(let i=0;i<100&&!fileNative.events.some(e=>e.kind===20);i++)await new Promise(r=>setTimeout(r,5));
assert.equal(fileNative.events.find(e=>e.kind===20)?.value,'opened text');
fileEventApp.dispose();fileEventRoot.remove();
// Version 2 files capability through a real generated-ABI module.
try{
  window.fetch=(url,options)=>String(url).endsWith('/files.json') ? Promise.resolve(new Response(JSON.stringify({version:2,wasm:'/demo.wasm',browser:false,math:false,files:true}))) : originalFetch(url,options);
  const filesRoot=makeRoot(),filesApp=await start({root:filesRoot,manifest:'/files.json'});
  assert.deepEqual(filesApp.features,{browser:false,math:false,files:true});assert.equal(filesApp.resources().files.listeners,2);filesApp.dispose();assert.equal(filesApp.resources().files.listeners,0);filesRoot.remove();
}finally{window.fetch=originalFetch;}
// A file declaration failure occurs after optional browser/math owners exist.
const fileRoot=makeRoot(),badFile=nativeFixture();badFile.batch(commands);
const oldInit=badFile.wasm.init;badFile.wasm.init=()=>{oldInit();const n=badFile.wasm.getRenderLength();const markup=decoder.decode(new Uint8Array(badFile.wasm.memory.buffer,0,n)).replace('data-text-limit="32"','data-text-limit="00"');const bytes=encoder.encode(markup);new Uint8Array(badFile.wasm.memory.buffer,0,bytes.length).set(bytes);badFile.wasm.getRenderLength=()=>bytes.length;return bytes.length;};
await refused({root:fileRoot,wasm:badFile.wasm,browser:true,math:true,files:true});assert.equal(badFile.released(),1);assert.equal(getApp(fileRoot),undefined);await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));assert.equal(badFile.events.length,0);assert.equal(fileRoot.querySelector('math'),null);assert.ok(!fileRoot.querySelector('dialog').open);fileRoot.remove();
return true;
