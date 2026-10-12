import { test, expect, mock } from 'claude-code/testing'

const ON_9ROUTER = JSON.stringify({
  env: { ANTHROPIC_BASE_URL: 'https://9router.example', ANTHROPIC_AUTH_TOKEN: 'k' },
})
const ON_ANTHROPIC = JSON.stringify({ env: {} })

test('/provider status reports 9router when a base URL is set', async ($, on) => {
  mock.env(on, { USERPROFILE: 'C:/fake' })
  on('fs.read', () => ({ value: ON_9ROUTER }))
  const out = await $.command.run({ command: 'provider', args: 'status' })
  expect(out.text).toContain('Provider: 9router')
})

test('bare /provider reports Anthropic when no base URL is set', async ($, on) => {
  mock.env(on, { USERPROFILE: 'C:/fake' })
  on('fs.read', () => ({ value: ON_ANTHROPIC }))
  const out = await $.command.run({ command: 'provider', args: '' })
  expect(out.text).toContain('Anthropic subscription')
})

test('/pv a switches 9router -> anthropic and writes the settings', async ($, on) => {
  mock.env(on, { USERPROFILE: 'C:/fake' })
  on('fs.read', () => ({ value: ON_9ROUTER }))
  const writes: string[] = []
  on('fs.write', (e: { path: string }) => {
    writes.push(e.path)
    return { value: undefined }
  })
  const out = await $.command.run({ command: 'pv', args: 'a' })
  expect(out.text).toContain('Switched to the Anthropic subscription')
  expect(writes.length).toBe(2)
})

test('bare /pv toggles: on 9router it goes to anthropic', async ($, on) => {
  mock.env(on, { USERPROFILE: 'C:/fake' })
  on('fs.read', () => ({ value: ON_9ROUTER }))
  on('fs.write', () => ({ value: undefined }))
  const out = await $.command.run({ command: 'pv', args: '' })
  expect(out.text).toContain('Switched to the Anthropic subscription')
})

test('/pv 9 on anthropic with nothing saved explains itself', async ($, on) => {
  mock.env(on, { USERPROFILE: 'C:/fake' })
  on('fs.read', () => ({ value: ON_ANTHROPIC }))
  on('fs.exists', () => ({ value: false }))
  const out = await $.command.run({ command: 'pv', args: '9' })
  expect(out.text).toContain('No saved 9router settings')
})

test('unknown argument is reported', async ($, on) => {
  mock.env(on, { USERPROFILE: 'C:/fake' })
  on('fs.read', () => ({ value: ON_ANTHROPIC }))
  const out = await $.command.run({ command: 'pv', args: 'zzz' })
  expect(out.text).toContain('Unknown option')
})
