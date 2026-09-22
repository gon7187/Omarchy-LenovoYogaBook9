#!/usr/bin/env node
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const source = fs.readFileSync(path.join(__dirname, '..', 'config/quickshell/yoga-widgets/visibility.js'), 'utf8')
const covers = new Function(source.replace(/^\.pragma library\s*/m, '') + '\nreturn covers')()
const box = { x: 100, y: 40, width: 320, height: 700 }
const client = { monitor: 0, mapped: true, hidden: false, visible: true,
  workspace: { id: 1 }, at: [419, 100], size: [200, 300] }

assert.equal(covers([client], 0, 1, 0, box), true)
assert.equal(covers([{ ...client, at: [420, 100] }], 0, 1, 0, box), false)
assert.equal(covers([{ ...client, monitor: 1 }], 0, 1, 0, box), false)
assert.equal(covers([{ ...client, workspace: { id: 2 } }], 0, 1, 0, box), false)
assert.equal(covers([{ ...client, workspace: { id: -99 } }], 0, 1, -99, box), true)
assert.equal(covers([{ ...client, hidden: true }], 0, 1, 0, box), false)
assert.equal(covers([{ ...client, mapped: false }], 0, 1, 0, box), false)
assert.equal(covers([], 0, 1, 0, box), false)
console.log('widget overlap OK')
