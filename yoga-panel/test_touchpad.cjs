// Exercise the actual production QML JavaScript with recorded-shape touch
// sequences, including the extra stationary contact seen on this machine.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const qml = fs.readFileSync(process.argv[2] || `${__dirname}/shell.qml`, 'utf8');
const start = qml.indexOf('function sample(currentPoints)');
const end = qml.indexOf('onPressed:', start);
assert(start >= 0 && end > start);
const source = qml.slice(start, end);
function harness() {
    const sent = [];
    let now=1000;
    const c = vm.createContext({samples:0, histogram:[0,0,0,0,0,0],
        scrollVX:0,scrollVY:0,lastScrollTime:0,velocitySamples:0,scrollDistance:0,momentumStarted:0,momentumLast:0,
        momentum:{running:false,restart(){this.running=true},stop(){this.running=false}},
        previousCount:0, positions:{}, began:0, travel:0, peakCount:0,
        lastX:0,lastY:0,moveEvents:0,scrollEvents:0,
        lastSampleTime:0,lastTapTime:-1000,lastTapX:0,lastTapY:0,tapDragging:false,dragPointId:-1,
        workspaceGesture:false,swipeX:0,swipeY:0,scrolling:false,scrollDirections:{x:0,y:0},scrollReversals:{x:0,y:0},
        Date:{now:()=>now},
        root:{clearWord:()=>{},drag:false,pointerSpeed:1.5,pointerAccel:0,scrollSpeed:0.6,send:e=>sent.push({...e}),click:b=>sent.push({click:b})}});
    vm.runInContext(source, c);
    return {sample:p=>{now+=16;c.sample(p)},sent,c,advance:t=>now+=t};
}
const p = (pointId,x,y) => ({pointId,x,y,pressed:true});
let h = harness();
h.sample([p(0,100,100)]);
h.sample([p(0,120,100)]);
h.sample([]);
assert.deepEqual(h.sent,[{type:'move',x:30,y:0}]);
h = harness();
h.sample([p(0,100,100),p(1,400,300)]);
h.sample([p(0,120,100),p(1,400,300)]);
assert.deepEqual(h.sent,[{type:'move',x:30,y:0}]);
h = harness();
h.sample([p(0,100,100),p(1,200,100)]);
h.sample([p(0,100,120),p(1,200,120)]);
assert.equal(h.sent[0].type,'scroll');
assert.equal(h.sent[0].y,-12);
h = harness();
h.sample([p(0,100,100)]);
h.sample([p(0,100,100),p(1,400,400)]);
h.sample([p(0,100,100)]);
assert.deepEqual(h.sent,[],'Adding/lifting a stationary finger must not jump');
h = harness();
h.sample([p(0,100,100)]); h.sample([]);
h.sample([p(1,100,100)]); h.sample([p(1,120,100)]); h.sample([]);
assert.deepEqual(h.sent,[{click:272},{type:'button',button:272,state:1},{type:'move',x:30,y:0},{type:'button',button:272,state:0}],'Double tap holds button during motion, releases without an extra click');
h = harness();
h.sample([p(0,100,100)]); h.sample([]);
h.advance(400); h.sample([p(1,100,100)]); h.sample([p(1,120,100)]);
assert.deepEqual(h.sent,[{click:272},{type:'move',x:30,y:0}],'Old tap must not start a drag');
h = harness();
h.sample([p(0,100,100)]); h.sample([]); h.sample([p(1,100,100)]);
h.c.resetGesture();
assert.equal(h.sent.at(-1).state,0,'Cancel releases held button');
assert.equal(h.c.tapDragging,false);
h = harness(); h.c.root.pointerAccel=1;
h.sample([p(0,100,100)]); h.sample([p(0,101,100)]); h.sample([p(0,121,100)]);
assert(h.sent[1].x/20 > h.sent[0].x,'Faster movement gets more gain');
h = harness(); h.c.root.scrollSpeed=0.18;
h.sample([p(0,100,100),p(1,200,100)]); h.sample([p(0,100,120),p(1,200,120)]);
assert(Math.abs(h.sent[0].y+3.6)<1e-9);
console.log('PASS: movement, extra stationary contact, scroll, no jumps, tap-drag, timeout, cancel, acceleration, scroll speed');
h=harness();
h.sample([p(0,100,100)]); h.sample([p(0,100,100),p(1,200,100)]);
h.sample([p(0,100,100)]); h.sample([]);
assert.deepEqual(h.sent,[{click:273}],'Staggered two-finger tap produces only right click');
const three=(x,y=100)=>[p(0,x,y),p(1,x+100,y),p(2,x+200,y)];
for(const [delta,direction] of [[-140,'next'],[140,'previous']]) {
 h=harness();h.sample(three(300));h.sample(three(300+delta));
 h.sample([p(0,300+delta,100),p(1,400+delta,100)]);h.sample([]);
 assert.deepEqual(h.sent,[{type:'workspace',direction}],'Swipe emits once with no pointer movement, scroll or click');
}
for(const [x,y] of [[20,0],[0,150],[130,140]]) {
 h=harness();h.sample(three(300));h.sample(three(300+x,100+y));h.sample([]);
 assert.deepEqual(h.sent,[],'Short, vertical or diagonal gestures do not switch');
}
h=harness();h.sample(three(300));h.sample(three(150));h.c.resetGesture();h.sample([]);
assert.deepEqual(h.sent,[],'Cancel cannot switch workspace');
const keys=vm.createContext({pad:{stopMomentum(){}},predictionEnabled:true,autocorrectEnabled:true,russian:true,lastTypedAt:0,logo:true,shift:true,control:false,alt:false,wordPrefix:"",clearWord:()=>{},updateWord:()=>{},send:e=>keys.last=e});
vm.runInContext(qml.slice(qml.indexOf('function typeKey(key)'),qml.indexOf('function click(button)')),keys);
keys.typeKey('Tab');
assert.deepEqual(Array.from(keys.last.mods),['logo','shift']);
assert.equal(keys.logo,false);assert.equal(keys.shift,false);
keys.logo=true;keys.typeText('3');
assert.equal(keys.last.text,'3');assert.deepEqual(Array.from(keys.last.mods),['logo']);
keys.typeText('4');assert.equal(keys.last.mods.length,0,'Super is one-shot');
console.log('PASS: right click, horizontal swipes, staggered release, rejected gestures, cancel, Super combinations');

h=harness();h.sample([p(0,100,100),p(1,200,100)]);
h.sample([p(0,100,120),p(1,200,120)]);
h.sample([p(0,100,125),p(1,200,120)]);
h.sample([p(0,100,125),p(1,200,125)]);
assert(h.sent.every(e=>e.type==='scroll'),'Scroll remains stable with asynchronous finger updates');
h=harness();h.sample([p(0,100,100)]);h.sample([]);h.sample([p(0,100,100)]);
h.sample([p(0,100,100),p(1,200,100)]);h.sample([p(0,100,120),p(1,200,120)]);
assert.equal(h.c.tapDragging,false);assert.equal(h.sent.at(-1).type,'scroll');
console.log('PASS: stable scrolling and two-finger priority over tap-drag');

h=harness();h.sample([p(0,100,100),p(1,200,100)]);
h.sample([p(0,100,120),p(1,200,120)]);
h.sample([p(0,100,119),p(1,200,119)]);
assert.equal(h.sent.length,1,'Small reverse release jitter is suppressed');
h.sample([p(0,100,115),p(1,200,115)]);
assert(h.sent.at(-1).y>0,'Intentional reverse scrolling still works');
h.sample([p(0,100,110)]);h.sample([]);
assert.equal(h.sent.at(-1).type,'scrollEnd');
assert(!h.sent.some(e=>e.type==='move'),'Lifting scroll fingers never moves pointer');
console.log('PASS: reverse jitter, deliberate reversal, scroll end, no lift-off cursor jump');

h=harness();h.sample([p(0,100,100),p(1,200,100)]);
h.sample([p(0,100,102),p(1,200,102)]);h.sample([]);
assert(!h.sent.some(e=>e.click),'A small scroll must not also right-click');

function flick(h) {
 h.c.root.inertiaEnabled=true;h.c.root.opened=true;h.c.root.scrollSpeed=.09;
 h.sample([p(0,100,100),p(1,200,100)]);
 for(let y=120;y<=180;y+=20)h.sample([p(0,100,y),p(1,200,y)]);
 h.sample([]);
}
h=harness();flick(h);assert.equal(h.c.momentum.running,true);
let distances=[];
while(h.c.momentum.running){h.advance(16);let before=h.sent.length;h.c.tickMomentum();if(h.sent.length>before&&h.sent.at(-1).type==='scroll')distances.push(-h.sent.at(-1).y);}
assert(distances.length>2&&distances.length<20);
assert(distances.every((v,i)=>v>0&&(!i||v<distances[i-1])),'Tail decays without reversal');
assert.equal(h.sent.at(-1).type,'scrollEnd');
h=harness();flick(h);let before=h.sent.length;h.sample([p(0,200,200)]);
assert.equal(h.c.momentum.running,false);assert.equal(h.sent[before].type,'scrollEnd');
h=harness();flick(h);h.c.resetGesture();assert.equal(h.c.momentum.running,false);
h=harness();h.c.root.inertiaEnabled=true;h.c.root.opened=true;
h.sample([p(0,100,100),p(1,200,100)]);h.sample([p(0,100,120),p(1,200,120)]);h.sample([p(0,100,140),p(1,200,140)]);h.advance(100);h.sample([]);
assert.equal(h.c.momentum.running,false,'Pause before release prevents coasting');
h=harness();flick(h);h.advance(200);h.c.tickMomentum();assert.equal(h.c.momentum.running,false,'A stalled UI cannot emit a jump');
h=harness();h.c.root.scrollSpeed=.09;
h.sample([p(0,100,100),p(1,200,100)]);h.sample([p(0,100,120),p(1,200,120)]);
let first=h.sent.at(-1).y;h.c.root.scrollSpeed=.18;h.sample([p(0,100,140),p(1,200,140)]);
assert(Math.abs(h.sent.at(-1).y-2*first)<1e-9,'Speed changes affect the very next motion');
console.log('PASS: short decaying inertia, immediate touch/cancel stop, paused lift, stalled timer, live sensitivity');
