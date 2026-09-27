const fs=require('fs'),vm=require('vm'),assert=require('assert');
const model=vm.createContext({});
vm.runInContext(fs.readFileSync(__dirname+'/../config/omarchy/plugins/gon7187.bar/BarModel.js','utf8'),model);
const panel={namespace:'yoga-input-panel'},bar={namespace:'omarchy-bar'};
assert.equal(model.lowerPanelVisible({}),false);
assert.equal(model.lowerPanelVisible({'eDP-1':{levels:{3:[panel]}}}),false);
assert.equal(model.lowerPanelVisible({'eDP-2':{levels:{2:[bar],3:[]}}}),false);
assert.equal(model.lowerPanelVisible({'eDP-2':{levels:{2:[bar],3:[panel]}}}),true);
for (const screen of ['eDP-1','eDP-2','DP-1']) {
    assert.equal(model.barHiddenOnScreen(false,false,screen),false);
    assert.equal(model.barHiddenOnScreen(false,true,screen),screen==='eDP-2');
    assert.equal(model.barHiddenOnScreen(true,false,screen),true);
    assert.equal(model.barHiddenOnScreen(true,true,screen),true);
}
console.log('PASS: lower panel detection, upper/tablet unaffected, manual hide preserved');
