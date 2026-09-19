const fs=require('fs'),vm=require('vm'),assert=require('assert');
const qml=fs.readFileSync(__dirname+'/shell.qml','utf8');
const ctx=vm.createContext({Theme:{},themeName:'removed-theme',appearance:{current:{name:'light',colors:{background:'#ffffff'}},themes:[{name:'dark',colors:{background:'#000000'}}]}});
vm.runInContext(qml.slice(qml.indexOf('    function applyAppearance()'),qml.indexOf('    onAppearanceChanged:')),ctx);
ctx.applyAppearance();assert.equal(ctx.Theme.name,'light');
ctx.themeName='dark';ctx.applyAppearance();assert.equal(ctx.Theme.palette.background,'#000000');
ctx.themeName='system';ctx.applyAppearance();assert.equal(ctx.Theme.name,'light');
ctx.appearance.current={name:'next',colors:{background:'#123456'}};ctx.applyAppearance();assert.equal(ctx.Theme.name,'next');
console.log('PASS: selected, missing and live system theme selection');
