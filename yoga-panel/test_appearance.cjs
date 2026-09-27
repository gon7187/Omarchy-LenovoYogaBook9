const fs=require('fs'),vm=require('vm'),assert=require('assert');
const qml=fs.readFileSync(__dirname+'/shell.qml','utf8');
const ctx=vm.createContext({Theme:{},themeName:'removed-theme',appearance:{current:{name:'light',colors:{background:'#ffffff'}},themes:[{name:'dark',colors:{background:'#000000'}}]}});
vm.runInContext(qml.slice(qml.indexOf('    function applyAppearance()'),qml.indexOf('    onAppearanceChanged:')),ctx);
ctx.applyAppearance();assert.equal(ctx.Theme.name,'light');
ctx.themeName='dark';ctx.applyAppearance();assert.equal(ctx.Theme.palette.background,'#000000');
ctx.themeName='system';ctx.applyAppearance();assert.equal(ctx.Theme.name,'light');
ctx.appearance.current={name:'next',colors:{background:'#123456'}};ctx.applyAppearance();assert.equal(ctx.Theme.name,'next');
console.log('PASS: selected, missing and live system theme selection');

const letters=fs.readFileSync(__dirname+'/LetterKey.qml','utf8');
const colors=[...letters.matchAll(/^        color: (.+)$/gm)].map(m=>m[1]);
const weights=[...letters.matchAll(/font.weight: (.+)$/gm)].map(m=>m[1]);
for (const russianActive of [false,true]) {
    const context={key:{russianActive},Font:{Bold:700,Normal:400,Medium:500},Theme:{letterActive:'active',accent:'accent',text:'text',textDim:'dim',accentDim:'dim'}};
    assert.equal(vm.runInNewContext(colors[russianActive ? 1 : 0],context),'active');
    assert.equal(vm.runInNewContext(colors[russianActive ? 0 : 1],context),'dim');
    assert.ok(vm.runInNewContext(weights[russianActive ? 1 : 0],context)>vm.runInNewContext(weights[russianActive ? 0 : 1],context),'active layout is also distinguished by weight');
}
const theme=fs.readFileSync(__dirname+'/Theme.qml','utf8');
const border=theme.match(/readonly property color keyBorder: (.+)/)[1];
for (const light of [false,true]) {
    const context={light,black:!light,text:1,base:0,accent:.8,mix:(a,b,w)=>a*w+b*(1-w)};
    const first=vm.runInNewContext(border,context);
    assert.ok(first>0 && first<context.accent,'resting border is a muted accent');
    context.accent=.4;
    assert.notEqual(vm.runInNewContext(border,context),first,'border follows theme accent');
}
console.log('PASS: symmetric layout accents and themed resting borders, including OLED');

const statusExpression=qml.match(/readonly property bool statusVisible: (.+)/)[1];
for (const status of ['Готово','Говори…','Распознаю…'])
    assert.equal(vm.runInNewContext(statusExpression,{status}),false);
for (const status of ['Подключение…','Диктовка недоступна или занята','Служба ввода остановлена'])
    assert.equal(vm.runInNewContext(statusExpression,{status}),true);
const rowVisible=qml.match(/id: suggestionRow\s+visible: (.+)/)[1];
for (const statusVisible of [false,true]) for (const predictionEnabled of [false,true]) {
    const root={settingsOpen:false,statusVisible,predictionEnabled,suggestions:['слово']};
    assert.equal(vm.runInNewContext(rowVisible,{root}),statusVisible || predictionEnabled);
    root.settingsOpen=true;
    assert.equal(vm.runInNewContext(rowVisible,{root}),false);
}
assert.ok(qml.includes('color: Theme.key\n                border.color: Theme.keyBorder'));
const padFill=theme.match(/readonly property color key: (.+)/)[1];
const {execFileSync}=require('child_process');
const catalogue=JSON.parse(execFileSync('python3',['-c','import json; from themes import Appearance; print(json.dumps(Appearance().catalogue()))'],{cwd:__dirname,encoding:'utf8'}));
const rgb=value=>Array.isArray(value) ? value : value.slice(1).match(/../g).map(v=>parseInt(v,16)/255);
for (const {name,colors} of catalogue) for (const opacity of [.65,.99,1]) {
    const context={base:colors.background,accent:colors.accent,
        token:(key,fallback)=>colors[key] || fallback,
        mix:(a,b,w)=>rgb(a).map((v,i)=>v*w+rgb(b)[i]*(1-w)),
        alpha:color=>[...rgb(color),opacity]};
    const fill=vm.runInNewContext(padFill,context);
    assert.equal(fill[3],opacity,name+' retains opacity');
    assert.deepEqual(fill.slice(0,3),rgb(colors.lighter_background || '#000000'),name+' matches keys exactly');
}
console.log(`PASS: touchpad fill for ${catalogue.length} installed themes; voice strip hidden, errors and suggestions retained`);
