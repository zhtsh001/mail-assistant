const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'mail-task-tests-'));
try {
  const fake = path.join(temp, 'codex');
  const capture = path.join(temp, 'prompt.txt');
  const draft = path.join(temp, 'edited-draft.txt');
  fs.writeFileSync(draft, 'Manual edit: I am available Friday at 3 PM.');
  fs.writeFileSync(fake, `#!${process.execPath}
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.writeFileSync(process.env.TEST_CAPTURE, fs.readFileSync(0, 'utf8'));
const schema = args[args.indexOf('--output-schema') + 1] || '';
let output = 'Plain text response';
if (schema.endsWith('analysis_schema.json')) output = JSON.stringify({cards:[]});
if (schema.endsWith('followup_schema.json')) output = JSON.stringify({kind:'draft',text:'Updated draft'});
fs.writeFileSync(args[args.indexOf('--output-last-message') + 1], output);
`, { mode: 0o700 });
  function run(task, extra = [], fixture = 'test-reply.json') {
    const env = { ...process.env, MAIL_ASSISTANT_CODEX_BIN: fake, TEST_CAPTURE: capture };
    delete env.MAIL_ASSISTANT_INPUT_FILE;
    if (fixture) env.MAIL_ASSISTANT_INPUT_FILE = path.join(__dirname, fixture);
    return spawnSync('/bin/zsh', [path.join(root, 'src/run_local.sh'), `--task=${task}`, ...extra], { env, encoding: 'utf8' });
  }
  let result = run('triage', ['--context=OLD_CONTEXT', '--instruction=OLD_TASK'], 'test-fixture.json');
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), { cards: [] });
  let prompt = fs.readFileSync(capture, 'utf8');
  assert(prompt.includes('只生成逐封邮件卡片'));
  assert(!prompt.includes('OLD_CONTEXT') && !prompt.includes('OLD_TASK'));
  assert(!prompt.includes('完整中文简报'));
  for (const task of ['draft', 'revise', 'question', 'assist']) {
    result = run(task, ['--instruction=Shorter please', '--context=Only this mail history', `--draft-file=${draft}`]);
    assert.equal(result.status, 0, result.stderr);
    prompt = fs.readFileSync(capture, 'utf8');
    assert(prompt.includes('Shorter please'));
    assert(prompt.includes('Only this mail history'));
    assert(prompt.includes('Manual edit: I am available Friday at 3 PM.'));
    assert(!prompt.includes('只生成逐封邮件卡片'));
    if (task === 'assist') assert.equal(JSON.parse(result.stdout).kind, 'draft');
  }
  assert.notEqual(run('question', [], null).status, 0, 'Follow-ups must not read live inbox');
  assert.notEqual(run('draft', [], 'test-fixture.json').status, 0, 'Reject multiple targets');
  assert.notEqual(run('revise').status, 0, 'Revision requires current draft');
  const schema = JSON.parse(fs.readFileSync(path.join(root, 'src/analysis_schema.json'), 'utf8'));
  assert(!('analysis' in schema.properties), 'Long briefing must not be generated');
  console.log('Task prompt tests passed: card-only output, isolated tasks, snapshot-only follow-ups, current draft forwarding.');
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
