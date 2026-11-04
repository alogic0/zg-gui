const {createFileHost}=await import('/file-host.js');
const root=document.createElement('div');document.body.append(root);
root.innerHTML='<input type="file" data-text-open-kind="1" data-text-error-kind="2" data-text-revision="1" data-text-limit="32"><textarea data-node-id="3"></textarea><button data-text-save="3" data-text-filename="sample.txt" data-text-error-kind="2" data-text-limit="32">Save</button>';
const input=root.querySelector('input'),text=root.querySelector('textarea'),button=root.querySelector('button'),events=[],errors=[];
const host=createFileHost({root,onInput:e=>events.push(e),onError:e=>errors.push(String(e))});host.sync();
const select=bytes=>{const transfer=new DataTransfer();transfer.items.add(new File([bytes],'sample.txt'));input.files=transfer.files;input.dispatchEvent(new Event('change',{bubbles:true}));};
async function awaitEvent(count){for(let i=0;i<100&&events.length<count;i++)await new Promise(r=>setTimeout(r,5));assert.equal(events.length,count);}
select('UTF-8 ✓');await awaitEvent(1);assert.deepEqual(events[0],{kind:1,value:'UTF-8 ✓'});assert.equal(input.value,'');assert.equal(host.stats().readers,0);
select(new Uint8Array([255]));await awaitEvent(2);assert.deepEqual(events[1],{kind:2,value:'invalid_utf8'});
select('x'.repeat(33));assert.deepEqual(events[2],{kind:2,value:'too_large'});
// Whole-sync validation leaves old declarations and active work intact.
button.dataset.textFilename='../invalid';let refused=false;try{host.sync();}catch{refused=true;}assert.ok(refused);button.dataset.textFilename='sample.txt';
select('again');await awaitEvent(4);assert.equal(events[3].kind,1);
for(const [node,attribute,bad] of [[input,'data-text-limit','262145'],[input,'data-text-limit','0'],[input,'data-text-revision','0'],[input,'type','text'],[input,'multiple',''],[input,'data-input-kind','1'],[button,'data-event','1'],[button,'data-text-save','99']]){
  const original=node.getAttribute(attribute);node.setAttribute(attribute,bad);let refused=false;try{host.sync();}catch{refused=true;}assert.ok(refused,attribute);if(original===null)node.removeAttribute(attribute);else node.setAttribute(attribute,original);
}
const clones=[];for(let i=0;i<15;i++){const clone=input.cloneNode();root.append(clone);clones.push(clone);}let bounded=false;try{host.sync();}catch{bounded=true;}assert.ok(bounded);assert.equal(host.stats().controls,2);clones.forEach(n=>n.remove());host.sync();
const FileReader=window.FileReader, readers=[];
class PendingReader {
  constructor(){readers.push(this);this.aborted=false;}
  readAsArrayBuffer(file){this.file=file;}
  abort(){this.aborted=true;this.onabort?.();}
  finish(value){this.result=new TextEncoder().encode(value).buffer;this.onload?.();}
}
try{
  window.FileReader=PendingReader;
  select('old');const old=readers.at(-1);assert.equal(host.stats().readers,1);
  input.dataset.textRevision='2';host.sync();assert.ok(old.aborted);old.finish('late');assert.equal(events.length,4);
  select('first');const first=readers.at(-1);select('second');assert.ok(first.aborted);first.finish('late');assert.equal(events.length,4);readers.at(-1).finish('second');assert.equal(events[4].value,'second');
  select('disabled');input.disabled=true;readers.at(-1).finish('disabled');assert.equal(events.length,5);assert.equal(host.stats().readers,0);input.disabled=false;
  const fieldset=document.createElement('fieldset');root.append(fieldset);fieldset.append(input);select('fieldset');fieldset.disabled=true;readers.at(-1).finish('disabled');assert.equal(events.length,5);assert.equal(host.stats().readers,0);root.prepend(input);fieldset.remove();
  select('removed');const removed=readers.at(-1);input.remove();host.sync();assert.ok(removed.aborted);removed.finish('removed');assert.equal(events.length,5);root.prepend(input);host.sync();
  select('failure');readers.at(-1).onerror();assert.equal(events[5].value,'read_failed');
  window.FileReader=class{constructor(){throw new Error('Unavailable reader');}};select('constructor');assert.equal(events[6].value,'read_failed');window.FileReader=PendingReader;
  select('dispose');const pending=readers.at(-1);host.dispose();host.dispose();assert.ok(pending.aborted);pending.finish('late');assert.equal(events.length,7);
  assert.deepEqual(host.stats(),{disposed:true,controls:0,readers:0,urls:0,listeners:0});
}finally{window.FileReader=FileReader;}
// Inspect exact Blob bytes and ownership before the browser download begins.
const downloads=[],created=[],revoked=[];
const originalClick=HTMLAnchorElement.prototype.click,originalCreate=URL.createObjectURL,originalRevoke=URL.revokeObjectURL;
let downloadHost;
try{
  HTMLAnchorElement.prototype.click=function(){downloads.push({url:this.href,name:this.download});};
  URL.createObjectURL=blob=>{const url=originalCreate.call(URL,blob);created.push({url,blob});return url;};
  URL.revokeObjectURL=url=>{revoked.push(url);originalRevoke.call(URL,url);};
  downloadHost=createFileHost({root,onInput:e=>events.push(e),onError:e=>errors.push(String(e))});downloadHost.sync();
  text.value='Export ✓\n';button.click();assert.equal(downloads[0].name,'sample.txt');assert.equal(await created[0].blob.text(),text.value);assert.equal(root.querySelector('a'),null);
  text.value='✓'.repeat(12);button.click();assert.equal(events.at(-1).value,'too_large');assert.equal(downloads.length,1);
  await new Promise(r=>setTimeout(r,10));text.value='pending';for(let i=0;i<8;i++)button.click();assert.equal(downloadHost.stats().urls,8);button.click();assert.equal(events.at(-1).value,'read_failed');assert.equal(downloadHost.stats().urls,8);downloadHost.dispose();assert.equal(downloadHost.stats().urls,0);assert.ok(revoked.includes(created.at(-1).url));
  await new Promise(r=>setTimeout(r,10));assert.equal(errors.length,0);
}finally{downloadHost?.dispose();HTMLAnchorElement.prototype.click=originalClick;URL.createObjectURL=originalCreate;URL.revokeObjectURL=originalRevoke;root.remove();}
return true;
