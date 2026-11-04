const {createMathHost} = await import('/math-host.js');
const {createDomHost} = await import('/dom.js');
const root = document.createElement('main'); document.body.append(root);
const failures = [];
const math = createMathHost({root, onError: error => failures.push(error), maxBytes: 1024, maxNodes: 64, maxDepth: 16});
let completed = 0;
const dom = createDomHost({root, onPatch(scope) { assert.equal(scope,root); completed++; math.sync(); }});
const first = '<math class="zig-math" display="inline"><mfrac><mi>x</mi><msqrt><mn>2</mn></msqrt></mfrac></math>';
const second = '<math class="zig-math" display="block"><msub><mi>V</mi><mi>x</mi></msub><mo>=</mo><mn>3</mn></math>';
const escape = text => text.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
const markup = payload => `<input data-node-id="1" value="draft"><section data-node-id="2" data-math-surface><span hidden data-node-id="3" data-math-source>${escape(payload)}</span><span data-node-id="4" data-math-output></span></section>`;
const patch = payload => dom.applyPatchStream('T\t3\t'+JSON.stringify(payload)+'\n');
dom.initialize(markup(first));
assert.equal(completed,1);
const surface=root.querySelector('section'), output=root.querySelector('[data-math-output]'), rendered=output.firstElementChild, input=root.querySelector('input'); input.focus();
assert.equal(rendered.namespaceURI,'http://www.w3.org/1998/Math/MathML'); assert.ok(rendered.querySelector('mfrac msqrt'));
dom.hydrate(markup(first)); assert.equal(completed,2);
dom.applyPatchStream('A\t2\tclass\tchanged\n'); patch(first);
assert.equal(completed,4); assert.equal(math.stats().updates,1); assert.equal(output.firstElementChild,rendered); assert.equal(document.activeElement,input);
for(const bad of [
  '<math class="zig-math" display="inline"><mtext><img src="https://outside.test/x"></mtext></math>',
  '<math class="zig-math" display="inline"><mi onclick="evil()">x</mi></math>',
  '<math class="zig-math" display="inline"><mi style="color:red">x</mi></math>',
  '<math class="zig-math" display="inline"><mi href="https://outside.test/">x</mi></math>',
  '<math class="zig-math" display="inline"><mstyle mathsize="200em"><mi>x</mi></mstyle></math>',
  '<math class="zig-math" display="inline"><mstyle displaystyle="true" scriptlevel="2"><mi>x</mi></mstyle></math>',
  '<math class="zig-math" display="inline"><!-- comment --><mi>x</mi></math>',
  '<math class="zig-math" display="inline"><annotation>unknown</annotation></math>',
  first+second,
  '<svg></svg>',
  '<math class="zig-math" display="inline"><mtext>'+('x'.repeat(1024))+'</mtext></math>',
  '<math class="zig-math" display="inline">'+('<mrow>'.repeat(17))+'<mi>x</mi>'+('</mrow>'.repeat(17))+'</math>',
  '<math class="zig-math" display="inline">'+('<mi>x</mi>'.repeat(40))+'</math>'
]) {
  const rejected=math.stats().rejected;
  patch(bad); assert.equal(math.stats().rejected,rejected+1);
  assert.equal(output.firstElementChild,rendered); assert.equal(document.activeElement,input);
  math.sync(); assert.equal(math.stats().rejected,rejected+1);
}
patch(first); assert.equal(output.firstElementChild,rendered); assert.equal(math.stats().updates,1);
patch(second);
assert.equal(root.querySelector('section'),surface); assert.equal(root.querySelector('[data-math-output]'),output);
assert.ok(output.querySelector('msub')); assert.ok(output.firstElementChild!==rendered); assert.equal(document.activeElement,input);
dom.applyPatchStream('A\t2\tdata-math-active\tfalse\n'); assert.equal(math.stats().surfaces,0); assert.equal(output.children.length,0);
dom.applyPatchStream('A\t2\tdata-math-active\ttrue\n'); assert.equal(math.stats().surfaces,1); assert.ok(output.querySelector('msub'));
const removed=output.firstElementChild;
dom.applyPatchStream('D\t2\n'); assert.equal(math.stats().surfaces,0); assert.equal(removed.parentNode,null);
dom.initialize(markup(first)); assert.equal(math.stats().surfaces,1);
math.dispose(); assert.equal(math.stats().surfaces,0); assert.equal(root.querySelectorAll('math').length,0);
math.sync(); assert.equal(math.stats().surfaces,0);
dom.dispose(); root.remove();
assert.equal(failures.length,13);
return true;
