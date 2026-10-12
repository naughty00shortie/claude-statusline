import type { Register } from 'claude-code'

// The env keys that make up the 9router setup. `anthropic` moves them out of
// settings.json into a saved copy, so Claude Code falls back to the normal
// subscription login; `9router` moves them back.
const KEYS = [
  'ANTHROPIC_BASE_URL',
  'ANTHROPIC_AUTH_TOKEN',
  'ANTHROPIC_DEFAULT_OPUS_MODEL',
  'ANTHROPIC_DEFAULT_SONNET_MODEL',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL',
  'ANTHROPIC_DEFAULT_FABLE_MODEL',
  'ANTHROPIC_CUSTOM_MODEL_OPTION',
  'ANTHROPIC_CUSTOM_MODEL_OPTION_NAME',
  'ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION',
  'CLAUDE_CODE_MAX_CONTEXT_TOKENS',
]

type Env = Record<string, string>
type Settings = { env?: Env } & Record<string, unknown>
type Choice = 'anthropic' | '9router' | 'status' | 'toggle'

const RESTART = 'Restart Claude Code for it to take effect.'

// /provider is the full name; /pv is the shortcut. They share one handler.
// Bare /pv flips to the other provider; bare /provider shows where you are.
const COMMANDS = ['provider', 'pv']

// Accepts any prefix, so /pv a, /pv an and /pv anthropic all work; "9" or "r"
// is enough for 9router.
function resolve(word: string, bare: Choice): Choice | undefined {
  if (word === '') return bare
  if ('anthropic'.startsWith(word)) return 'anthropic'
  if ('9router'.startsWith(word) || 'router'.startsWith(word)) return '9router'
  if ('status'.startsWith(word)) return 'status'
  if ('toggle'.startsWith(word)) return 'toggle'
  return undefined
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'provider',
      description: 'Switch provider: /provider anthropic | 9router | status',
      argumentHint: '[anthropic|9router|status]',
    })
    await $.command.register({
      name: 'pv',
      description: 'Shortcut: /pv toggles provider, /pv a = anthropic, /pv 9 = 9router',
      argumentHint: '[a|9|status]',
    })
    return next(e)
  })

  on('command.run', async ($, e, next) => {
    if (!COMMANDS.includes(e.command)) return next(e)

    const home = (await $.env.get('USERPROFILE')) ?? (await $.env.get('HOME'))
    if (!home) return { text: 'provider: neither USERPROFILE nor HOME is set.' }
    const settingsPath = `${home}/.claude/settings.json`
    const savedPath = `${home}/.claude/provider-9router-env.json`

    const settings = JSON.parse(await $.fs.read(settingsPath)) as Settings
    const env: Env = settings.env ?? {}
    const via9router = Boolean(env.ANTHROPIC_BASE_URL)

    const word = e.args.trim().toLowerCase()
    let want = resolve(word, e.command === 'pv' ? 'toggle' : 'status')
    if (want === 'toggle') want = via9router ? 'anthropic' : '9router'

    if (want === 'status') {
      return {
        text: `Provider: ${via9router ? '9router' : 'Anthropic subscription'}. Use /pv to toggle, or /provider anthropic | 9router.`,
      }
    }

    if (want === 'anthropic') {
      if (!via9router) return { text: 'Already on the Anthropic subscription.' }
      const saved: Env = {}
      for (const k of KEYS) {
        if (env[k] !== undefined) saved[k] = env[k]
        delete env[k]
      }
      await $.fs.write(savedPath, JSON.stringify(saved, null, 2))
      settings.env = env
      await $.fs.write(settingsPath, JSON.stringify(settings, null, 2))
      return {
        text: `Switched to the Anthropic subscription (9router settings saved to ${savedPath}). ${RESTART} Log in with /login if needed.`,
      }
    }

    if (want === '9router') {
      if (via9router) return { text: 'Already on 9router.' }
      if (!(await $.fs.exists(savedPath))) {
        return { text: `No saved 9router settings at ${savedPath}.` }
      }
      const saved = JSON.parse(await $.fs.read(savedPath)) as Env
      settings.env = { ...saved, ...env }
      await $.fs.write(settingsPath, JSON.stringify(settings, null, 2))
      return { text: `Switched to 9router. ${RESTART}` }
    }

    return { text: `Unknown option "${word}". Use: anthropic | 9router | status (or a | 9 | s).` }
  }).catch(($, e, next) =>
    COMMANDS.includes(e.command) ? { text: 'provider: could not read or write settings.json.' } : next(e),
  )
}
