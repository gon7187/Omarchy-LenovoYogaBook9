const assert=require('node:assert/strict');
// Run with NODE_PATH=$HOME/.local/share/agent-browser/node_modules node yoga-panel/test_clipboard.cjs
// Uses an isolated browser; records only test key events and blocks clipboard reads.
const {chromium}=require('playwright');
const path=require('node:path');
const {execFileSync,spawn}=require('node:child_process');
// A browser crash must not turn an unfinished async run into exit status 0.
process.exitCode=1;
const hypr=(...args)=>execFileSync('hyprctl',args,{encoding:'utf8'}).trim();
(async()=>{
 const previous=JSON.parse(hypr('activewindow','-j')).address;
 const layouts=JSON.parse(hypr('devices','-j')).keyboards;
 const keyboards=[];
 const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:false,args:['--ozone-platform=wayland']});
 try {
  const page=await browser.newPage();
  await page.setContent('<title>Yoga clipboard regression</title><h2>Проверка Super+V</h2><textarea></textarea>');
  await page.waitForTimeout(800);
  const own=JSON.parse(hypr('clients','-j')).find(c=>c.title.startsWith('Yoga clipboard regression'));
  assert(own,'Test window did not map');
  hypr('eval',`hl.dispatch(hl.dsp.focus({window='address:${own.address}'}))`);
  await page.waitForTimeout(200);
  await page.locator('textarea').click();
  assert.equal(JSON.parse(hypr('activewindow','-j')).address,own.address,'Test not focused');
  await page.evaluate(()=>{
   window.events=[];
   // Never inspect or insert the owner's clipboard.
   for(const type of ['copy','cut','paste']) document.addEventListener(type,e=>e.preventDefault());
   for(const type of ['keydown','keyup']) document.addEventListener(type,e=>events.push({type,code:e.code,repeat:e.repeat,ctrl:e.ctrlKey,shift:e.shiftKey,meta:e.metaKey}));
  });
  async function keyboard() {
   const p=spawn(path.join(__dirname,'build/yoga-keyboard'),[],{stdio:['pipe','pipe','inherit']});
   keyboards.push(p);
   await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(Error('Keyboard helper did not start')),3000);p.stdout.once('data',()=>{clearTimeout(timeout);resolve();});p.once('error',reject);});
   return p;
  }
  const first=await keyboard();
  const second=await keyboard();
  for(const terminal of [false,true]) {
   hypr('eval',`hl.dispatch(hl.dsp.window.tag({tag='${terminal?'+':'-'}terminal',window='address:${own.address}'}))`);
   for(const group of [0,1]) for(const letter of ['v','c','x']) {
    assert.equal(JSON.parse(hypr('activewindow','-j')).address,own.address,'Test lost focus');
    first.stdin.write(`g ${group}\n`);
    await page.waitForTimeout(60);
    await page.evaluate(()=>{events=[];document.querySelector('textarea').value='';});
    first.stdin.write(`k ${letter} 4\n`);
    await page.waitForTimeout(15);
    second.stdin.write(`g ${1-group}\n`);
    await page.waitForTimeout(600);
    const events=await page.evaluate(()=>events);
    const code=terminal&&letter!=='x'?'Insert':'Key'+letter.toUpperCase();
    const label=`Super+${letter.toUpperCase()} ${group?'RU':'EN'} ${terminal?'terminal':'browser'}`;
    assert.deepEqual(events.map(e=>[e.type,e.code,e.repeat]),[['keydown',code,false],['keyup',code,false]],label+': key release lost or repeated');
    const shift=terminal&&letter==='v';
    assert(events.every(e=>e.shift===shift&&e.ctrl===!shift&&!e.meta),label+': incorrect modifiers');
    assert.equal(await page.locator('textarea').inputValue(),'','Repeated characters reached the field');
    console.log('PASS: '+label);
   }
  }
 } finally {
  for(const k of keyboards) {
   if(k.exitCode!==null) continue;
   const stopped=new Promise(r=>k.once('close',r));
   const timeout=setTimeout(()=>k.kill('SIGKILL'),3000);
   k.stdin.end();await stopped;clearTimeout(timeout);
  }
  await browser.close();
  for(const k of layouts) hypr('switchxkblayout',k.name,String(k.active_layout_index));
  hypr('eval',`hl.dispatch(hl.dsp.focus({window='address:${previous}'}))`);
 }
})().then(()=>{process.exitCode=0;}).catch(e=>{console.error(e);});
