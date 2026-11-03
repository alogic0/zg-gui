const std = @import("std");
const Harness = @import("../browser_harness.zig").Harness;

test "browser charts: signed geometry gaps clipping identity focus and rejected-draft recovery" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    const desktop = try guard.session.call("Emulation.setDeviceMetricsOverride", "{\"width\":1440,\"height\":1000,\"deviceScaleFactor\":1,\"mobile\":false}");
    defer guard.alloc.free(desktop);
    try guard.goto("/charts.html");
    try guard.evalCheck(
        \\for (let i=0; !window.chartExample && i<250; i++) await new Promise(r=>setTimeout(r,20));
        \\assert.ok(window.chartExample); await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
        \\const app=window.chartExample, root=document.querySelector('#app'), input=root.querySelector('#chart-data');
        \\const line=root.querySelector('[data-series="line"]'), bar=root.querySelector('[data-series="bar"]');
        \\const path=line.querySelector('.line-series'), first=bar.querySelector('rect[data-sample="1"]'), negative=bar.querySelector('rect[data-sample="4"]');
        \\const axis=bar.querySelector('.y-axis'), label=axis.querySelector('text');
        \\assert.equal(root.querySelectorAll('tbody tr').length,8); assert.equal(bar.querySelectorAll('.chart-bar').length,7);
        \\assert.equal((path.getAttribute('d').match(/M/g)||[]).length,2); assert.ok(path.getTotalLength()>0);
        \\const zero=Number(bar.querySelector('.chart-zero').getAttribute('y1'));
        \\assert.ok(Math.abs(Number(first.getAttribute('y'))+Number(first.getAttribute('height'))-zero)<0.03);
        \\assert.ok(Math.abs(Number(negative.getAttribute('y'))-zero)<0.03);
        \\assert.ok(getComputedStyle(line.querySelector('.chart-marks')).clipPath.endsWith('#line-plot")'));
        \\const set=value=>{input.focus(); input.value=value; input.dispatchEvent(new Event('input',{bubbles:true})); app.dispatch({action:1});};
        \\set('18, 28, , -8, 45, 24, 62, 38');
        \\assert.ok(path===line.querySelector('.line-series') && first===bar.querySelector('rect[data-sample="1"]') && axis===bar.querySelector('.y-axis') && label===axis.querySelector('text'));
        \\assert.ok(document.activeElement===input && input===root.querySelector('#chart-data'));
        \\const accepted=[line.innerHTML,bar.innerHTML];
        \\for(const bad of ['12, NaN, 20','12, Infinity','1001','1,2,3,4,5,6,7,8,9']) { set(bad); assert.deepEqual([line.innerHTML,bar.innerHTML],accepted); assert.equal(input.getAttribute('aria-invalid'),'true'); assert.ok(root.querySelector('#chart-error').textContent.length>0); assert.ok(document.activeElement===input); }
        \\set('12, 120, , -65, 45, 24, 62, 38'); assert.equal(input.getAttribute('aria-invalid'),'false'); assert.equal(root.querySelector('#chart-error').textContent,'');
        \\const box=path.getBBox(), clip=line.querySelector('clipPath rect');
        \\assert.ok(box.x>=48-0.02 && box.x+box.width<=48+Number(clip.getAttribute('width'))+0.02 && box.y>=24-0.02 && box.y+box.height<=272+0.02);
        \\for(const rect of bar.querySelectorAll('.chart-bar')) {const b=rect.getBBox();assert.ok(b.width>=0&&b.height>=0&&b.x>=48-0.02&&b.y>=24-0.02&&b.y+b.height<=272+0.02);}
        \\const beforeX=Number(first.getAttribute('x')); app.dispatch({action:3});
        \\assert.ok(first===bar.querySelector('rect[data-sample="1"]') && Number(first.getAttribute('x'))>beforeX);
        \\assert.deepEqual([...root.querySelectorAll('tbody th')].map(n=>n.textContent),['8','7','6','5','4','3','2','1']);
        \\assert.ok(line===root.querySelector('[data-series="line"]') && axis===bar.querySelector('.y-axis') && document.activeElement===input);
        \\set(''); assert.equal(bar.querySelectorAll('.chart-bar').length,0); assert.equal(path.getAttribute('d'),''); assert.ok(root.querySelector('.chart-empty').getBoundingClientRect().height>0);
        \\set('0'); assert.equal(bar.querySelectorAll('.chart-bar').length,1); assert.equal(bar.querySelector('.chart-bar').getAttribute('height'),'0.00'); assert.equal(line.querySelectorAll('.chart-point').length,1); assert.equal(path.getTotalLength(),0);
        \\app.dispatch({action:2}); assert.equal(bar.querySelectorAll('.chart-bar').length,7); assert.ok(path===line.querySelector('.line-series') && axis===bar.querySelector('.y-axis'));
        \\const ids=[...root.querySelectorAll('[data-node-id]')].map(n=>n.dataset.nodeId); assert.equal(new Set(ids).size,ids.length);
        \\const clipIds=[...root.querySelectorAll('clipPath')].map(n=>n.id);assert.equal(new Set(clipIds).size,2);
        \\assert.ok([...root.querySelectorAll('svg *')].every(n=>n.namespaceURI==='http://www.w3.org/2000/svg'));
        \\scrollTo({top:0,behavior:'instant'}); return true;
    );
    const screenshot = try guard.session.captureScreenshot();
    defer guard.alloc.free(screenshot);
    var file = try std.Io.Dir.cwd().createFile(std.testing.io, "zig-out/chart-desktop.png", .{});
    defer file.close(std.testing.io);
    try file.writeStreamingAll(std.testing.io, screenshot);
}

test "browser charts: responsive axes keyboard theme and bounded update measurements" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/charts.html");
    try guard.evalCheck(
        \\for(let i=0;!window.chartExample&&i<250;i++)await new Promise(r=>setTimeout(r,20));
        \\assert.ok(window.chartExample);await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
        \\window.chartRefs={svg:document.querySelector('[data-series="line"]'),axis:document.querySelector('.x-axis'),input:document.querySelector('#chart-data')};chartRefs.input.focus();
        \\window.chartWideWidth=chartRefs.svg.viewBox.baseVal.width;
        \\return true;
    );
    const emulation = try guard.session.call("Emulation.setDeviceMetricsOverride", "{\"width\":390,\"height\":844,\"deviceScaleFactor\":1,\"mobile\":false}");
    defer guard.alloc.free(emulation);
    try guard.evalCheck(
        \\for(let i=0;chartRefs.svg.viewBox.baseVal.width===chartWideWidth&&i<100;i++)await new Promise(r=>setTimeout(r,20));
        \\assert.ok(chartRefs.svg.viewBox.baseVal.width<chartWideWidth && chartRefs.svg===document.querySelector('[data-series="line"]') && chartRefs.axis===document.querySelector('.x-axis') && document.activeElement===chartRefs.input);
        \\assert.ok(document.documentElement.scrollWidth<=innerWidth);assert.ok(document.querySelectorAll('.chart-panel')[1].getBoundingClientRect().top>=document.querySelector('.chart-panel').getBoundingClientRect().bottom);
        \\const svg=chartRefs.svg, range=svg.viewBox.baseVal;
        \\for(const label of svg.querySelectorAll('.x-axis text,.y-axis text')) {const b=label.getBBox();assert.ok(b.x>=0&&b.y>=0&&b.x+b.width<=range.width+1&&b.y+b.height<=range.height+1);}
        \\assert.ok(getComputedStyle(chartRefs.input).resize==='none');assert.ok(chartRefs.input.labels.length===1);assert.ok(getComputedStyle(document.documentElement).scrollbarColor!=='auto');
        \\const update=document.querySelector('button[data-event=\"1\"]'), top=update.offsetTop;chartExample.setInput({kind:1,value:'not a number'});chartExample.dispatch({action:1});assert.equal(update.offsetTop,top);chartExample.dispatch({action:2});
        \\const theme=document.querySelector('.theme-toggle'), before=getComputedStyle(svg.querySelector('.line-series')).stroke;theme.click();assert.ok(getComputedStyle(svg.querySelector('.line-series')).stroke!==before);theme.click();
        \\const bytes=await(await fetch('./charts.wasm')).arrayBuffer(), module=await WebAssembly.compile(bytes), w=new WebAssembly.Instance(module,{}).exports;
        \\const initialMemoryBytes=w.memory.buffer.byteLength;w.init();const initialHtmlBytes=w.getRenderLength();let peak=initialMemoryBytes,largest=0,firstPatch='';
        \\for(let i=0;i<100;i++){const text=`${12+i%60}, 28, , -8, 45, 24, 62, 38`,encoded=new TextEncoder().encode(text);new Uint8Array(w.memory.buffer,w.getExchangeBuffer(),encoded.length).set(encoded);w.setInput(1,encoded.length);w.dispatch(1,0);const n=w.getRenderLength(),patch=new TextDecoder().decode(new Uint8Array(w.memory.buffer,w.getRenderBuffer(),n));assert.ok(!/^[HJD]\t/m.test(patch));if(i===1)firstPatch=patch;largest=Math.max(largest,n);peak=Math.max(peak,w.memory.buffer.byteLength);}
        \\assert.equal(peak,initialMemoryBytes);
        \\window.chartMeasurements={wasmBytes:bytes.byteLength,initialMemoryBytes,observedPeakMemoryBytes:peak,initialHtmlBytes,updates:100,largestPatchBytes:largest,valueChangePatchBytes:new TextEncoder().encode(firstPatch).length,valueChangeCommands:firstPatch.trim().split('\n').length,workload:'Eight samples, one missing and one negative; 100 retained value updates in an isolated WASM instance. Memory is allocated pages. Mounted browser also verifies clipping, reverse order, keyboard, invalid/empty recovery, themes and 390px resizing.'};
        \\document.querySelector('button[data-event="3"]').focus();return true;
    );
    const activated = try guard.session.call("Page.bringToFront", "{}");
    defer guard.alloc.free(activated);
    const down = try guard.session.call("Input.dispatchKeyEvent", "{\"type\":\"keyDown\",\"key\":\"Enter\",\"code\":\"Enter\",\"text\":\"\\r\"}");
    defer guard.alloc.free(down);
    const up = try guard.session.call("Input.dispatchKeyEvent", "{\"type\":\"keyUp\",\"key\":\"Enter\",\"code\":\"Enter\"}");
    defer guard.alloc.free(up);
    try guard.evalCheck(
        \\assert.equal(document.querySelector('button[data-event="3"]').getAttribute('aria-pressed'),'true');assert.ok(document.activeElement===document.querySelector('button[data-event="3"]'));scrollTo({top:0,behavior:'instant'});return true;
    );
    const report = try guard.session.evaluate("JSON.stringify(window.chartMeasurements)");
    defer guard.alloc.free(report);
    var file = try std.Io.Dir.cwd().createFile(std.testing.io, "zig-out/chart-measurements.json", .{});
    defer file.close(std.testing.io);
    const decoded = try std.json.parseFromSlice(std.json.Value, guard.alloc, report, .{});
    defer decoded.deinit();
    try file.writeStreamingAll(std.testing.io, decoded.value.object.get("result").?.object.get("result").?.object.get("value").?.string);
    const screenshot = try guard.session.captureScreenshot();
    defer guard.alloc.free(screenshot);
    var shot = try std.Io.Dir.cwd().createFile(std.testing.io, "zig-out/chart-mobile.png", .{});
    defer shot.close(std.testing.io);
    try shot.writeStreamingAll(std.testing.io, screenshot);
    try guard.evalCheck("scrollTo({top:document.querySelector('[aria-labelledby=bar-heading]').getBoundingClientRect().top+scrollY-16,behavior:'instant'});return true;");
    const second = try guard.session.captureScreenshot();
    defer guard.alloc.free(second);
    var bar_shot = try std.Io.Dir.cwd().createFile(std.testing.io, "zig-out/chart-mobile-bar.png", .{});
    defer bar_shot.close(std.testing.io);
    try bar_shot.writeStreamingAll(std.testing.io, second);
    try guard.evalCheck("scrollTo({top:document.querySelector('.chart-data').getBoundingClientRect().top+scrollY-16,behavior:'instant'});return true;");
    const data = try guard.session.captureScreenshot();
    defer guard.alloc.free(data);
    var data_shot = try std.Io.Dir.cwd().createFile(std.testing.io, "zig-out/chart-mobile-data.png", .{});
    defer data_shot.close(std.testing.io);
    try data_shot.writeStreamingAll(std.testing.io, data);
}
