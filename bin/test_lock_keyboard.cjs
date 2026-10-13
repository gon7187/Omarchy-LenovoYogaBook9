#!/usr/bin/env node
// Run the QML JavaScript bindings with controlled monitor/authentication inputs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../config/omarchy/lock/TouchKeys.qml'), 'utf8');
function keyboard(names, current) {
  const view = {
    inputEnabled: true, authenticatingPassword: false, failureMessage: '', passwordText: '',
    wakeRequested() {}, clearFailureRequested() { this.failureMessage = ''; },
    passwordTextEdited(text) { this.passwordText = text; },
    submitPassword(text) { this.submitted = text; }
  };
  const context = vm.createContext({ view, shift: false, symbols: false,
    Screen: { name: current }, Quickshell: { screens: names.map(name => ({name})) } });
  for (const name of ['letterRows', 'symbolRows', 'keyboardScreen']) {
    const binding = source.match(new RegExp('readonly property (?:var|string) ' + name + ': ([^\\n]+)'));
    if (binding) vm.runInContext('var ' + name + ' = ' + binding[1], context);
  }
  vm.runInContext('var visible = ' + source.match(/^  visible: ([^\n]+)/m)[1], context);
  const press = source.match(/  function press\(k\) \{([\s\S]*?)\n  \}/)[1];
  vm.runInContext('function press(k) {' + press + '\n}', context);
  return context;
}
const normal = keyboard(['eDP-1', 'eDP-2'], 'eDP-2');
assert.equal(normal.visible, true);
assert.equal(keyboard(['eDP-1', 'eDP-2'], 'eDP-1').visible, false);
assert.equal(keyboard(['eDP-1'], 'eDP-1').visible, true, 'tablet lock must have touch keys on the active upper panel');
const available = new Set([...normal.letterRows.flat(), ...normal.symbolRows.flat()]);
for (let code = 33; code <= 126; code++) {
  const char = String.fromCharCode(code);
  assert.ok(available.has(char) || available.has(char.toLowerCase()), 'password character missing: ' + char);
}
normal.press('^'); normal.press('['); normal.press('space'); normal.press('⇧'); normal.press('a');
assert.equal(normal.view.passwordText, '^[ A');
normal.press('↵');
assert.equal(normal.view.submitted, '^[ A');
assert.equal(normal.view.passwordText, '');
normal.view.authenticatingPassword = true;
normal.press('q');
assert.equal(normal.view.passwordText, '', 'authentication in progress must reject key input');
console.log('LOCK_KEYBOARD_OK');
