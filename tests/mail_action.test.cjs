const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../src/mail_action.js'), 'utf8'), context);

function setup(count = 1) {
  const calls = [];
  const message = { messageId: () => 'original@example.test', id: () => 42 };
  const draft = {};
  const mail = {
    inbox: { messages: { whose: criteria => {
      assert.equal(criteria.messageId, 'original@example.test');
      return () => Array(count).fill(message);
    } } },
    open: target => { assert.equal(target, message); calls.push('open'); },
    activate: () => calls.push('activate'),
    reply: (target, options) => {
      assert.equal(target, message);
      assert.equal(options.replyToAll, false);
      assert.equal(options.openingWindow, false);
      calls.push('reply'); return draft;
    },
    save: target => { assert.equal(target, draft); calls.push('save'); },
    send: () => { throw new Error('Sending must never be called'); }
  };
  return { mail, calls, draft };
}
const request = { action: 'draft', id: 'original@example.test', localID: '42', body: 'Thanks!\n\n[Fill in details]' };
{
  const { mail, calls, draft } = setup();
  context.handleRequest(mail, request);
  assert.deepEqual(calls, ['reply', 'save', 'activate']);
  assert.equal(draft.content, request.body);
  assert.equal(draft.visible, true);
}
{
  const { mail, calls } = setup();
  context.handleRequest(mail, { ...request, action: 'open' });
  assert.deepEqual(calls, ['open', 'activate']);
}
for (const count of [0, 2]) {
  const { mail, calls } = setup(count);
  assert.throws(() => context.handleRequest(mail, request), /无法唯一定位/);
  assert.deepEqual(calls, []);
}
for (const changed of [{ action: 'send' }, { id: '' }, { body: '  ' }, { localID: 'wrong' }]) {
  const { mail, calls } = setup();
  assert.throws(() => context.handleRequest(mail, { ...request, ...changed }));
  assert.deepEqual(calls, []);
}
console.log('Mail action tests passed: exact target, draft-only save, validation, missing/ambiguous targets.');
