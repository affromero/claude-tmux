# claude-tmux

A tmux setup for AI-assisted development. 3-line status bar with live system stats, Claude Code rate limits, and Codex rate limits — all visible at a glance while you work.

```
 main │ 1:zsh  2:claude                    Andres's Mac │ macOS 15.4 │ CPU  12% │ RAM 22.7/36.0G │ GPU M3 Max  7% 143mW │ Mar 13 19:30
 Max Claude │ 5h 3% ░░░░░░░░ (4h54m) │ Wk 24% █░░░░░░░ (Mar 20 6d13h)
 Plus Codex │ 5h 20% █░░░░░░░ (2h07m) │ Wk 23% █░░░░░░░ (Mar 20 6d04h)
```

This is a [Claude Code skill](https://docs.anthropic.com/en/docs/claude-code), not a traditional plugin. You install it, Claude sets everything up conversationally, and then you modify it to your taste — change colors, swap out status lines, add a battery indicator, whatever. The config files are yours.

## Install

Clone into your Claude Code skills directory:

```bash
git clone https://github.com/andresromero/claude-tmux.git ~/.claude/skills/setup-tmux
```

Then tell Claude to run it:

```
claude "/setup-tmux"
```

That's it. Claude reads your system, writes the config, installs plugins, deploys the status scripts, configures your terminal's Meta key, and reloads tmux. Run it again anytime to update.

If you already have a skills directory and want to keep things tidy, add it as a submodule of your dotfiles or skills repo instead:

```bash
cd ~/.claude/skills
git submodule add https://github.com/andresromero/claude-tmux.git setup-tmux
```

### What it does

1. Writes `~/.tmux.conf` (shows diff and asks before overwriting)
2. Installs TPM + plugins (tmux-resurrect, tmux-continuum)
3. Deploys 3 status bar scripts to `~/.tmux/scripts/`
4. Configures Option-as-Meta for your terminal (Ghostty/iTerm2/VS Code/Cursor)
5. Enables Claude Code agent teams (tmux teammate mode)
6. Reloads the running tmux server

### Prerequisites

- tmux 3.4+ (for multi-line status bar)
- `python3` and `curl` (for AI limit scripts)
- Claude Code and/or Codex CLI logged in (for rate limit data)

## Features

### 3-Line Status Bar

| Line | Content | Update interval |
|------|---------|-----------------|
| **0** | Session name, window tabs, system stats, date/time | 5s |
| **1** | Claude Code usage: 5h window + weekly, with progress bars | 5min (cached) |
| **2** | Codex usage: 5h window + weekly + credits, with progress bars | 60s (cached) |

### System Stats (Line 0)

Cross-platform script showing live hardware metrics:

| Stat | macOS | Linux | Windows (MSYS) |
|------|-------|-------|----------------|
| CPU usage | `top -l 2` | `/proc/stat` | `wmic` |
| RAM | `vm_stat` | `/proc/meminfo` | PowerShell |
| GPU name | `sysctl` | `nvidia-smi` / sysfs / `lspci` | `nvidia-smi.exe` |
| GPU usage | `powermetrics` | `nvidia-smi` / AMD sysfs / `intel_gpu_top` | `nvidia-smi.exe` |
| GPU power | `powermetrics` (mW) | `nvidia-smi` (W) / AMD hwmon | `nvidia-smi.exe` |

On Apple Silicon, GPU stats require a one-time sudoers entry for `powermetrics` (the skill sets this up). Everything else works unprivileged.

### Claude Code Limits (Line 1)

```
Max Claude │ 5h 3% ░░░░░░░░ (4h54m) │ Wk 24% █░░░░░░░ (Mar 20 6d13h)
```

- **How it works:** Sends a minimal 1-token Haiku request to `/v1/messages` and reads the `anthropic-ratelimit-unified-*` response headers. The `/api/oauth/usage` endpoint is [effectively disabled](https://github.com/anthropics/claude-code/issues/30930) — this is the same technique used by [Claude Usage Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker).
- **Cost:** ~1 input token + 1 output token of Haiku per refresh. Negligible.
- **Cache:** 5 minutes (each refresh is a real API call)
- **Auth:** Reads OAuth token from macOS Keychain (`Claude Code-credentials`) or `~/.claude/.credentials.json`
- **Colors:** Purple (Claude brand) when healthy, amber at 50%+ used, red at 80%+ used
- **Shows:** Subscription tier, 5h used% + bar + time remaining, weekly used% + bar + reset date/countdown

### Codex Limits (Line 2)

```
Plus Codex │ 5h 20% █░░░░░░░ (2h07m) │ Wk 23% █░░░░░░░ (Mar 20 6d04h)
```

- **How it works:** Queries `chatgpt.com/backend-api/wham/usage` with bearer token from `~/.codex/auth.json`
- **Cache:** 60 seconds
- **Auth:** Reads `tokens.access_token` from `~/.codex/auth.json` (created by `codex login`)
- **Colors:** Green (Codex brand) when healthy, amber at 50%+ used, red at 80%+ used
- **Shows:** Plan tier + "Codex" label, 5h used% + bar + time remaining, weekly used% + bar + reset date/countdown, credits (if applicable)

### Keybindings

| Shortcut | Action |
|----------|--------|
| `Ctrl+b \|` | Split horizontal |
| `Ctrl+b -` | Split vertical |
| `Ctrl+b arrow` | Switch panes |
| `Alt+arrow` | Switch panes (no prefix) |
| `Ctrl+b Shift+W/A/S/D` | Resize panes (5 cells, repeatable) |
| `Ctrl+b T` | Rename pane title |
| `Ctrl+b s` | Session tree picker |
| Mouse scroll | Scroll history (2 lines/tick) |
| Mouse drag | Select text (auto-copy) |
| Right-click | Exit copy mode |
| `v` / `y` (copy mode) | Begin selection / yank |

### Pane Naming for AI Agents

Each pane shows a label in its top border (`session:pane command`). You can set custom names with `Ctrl+b T` — this is especially useful when running AI agents that spawn tmux teammates. Named panes let agents reference specific panes directly instead of guessing by index:

```
┌─ dev:1 claude ──────────────────┐┌─ dev:2 tests ──────────────────┐
│ claude> implementing auth flow  ││ npm run test:watch             │
│                                 ││ PASS src/auth.test.ts          │
└─────────────────────────────────┘└─────────────────────────────────┘
┌─ dev:3 server ──────────────────────────────────────────────────────┐
│ [nodemon] watching for changes...                                   │
└─────────────────────────────────────────────────────────────────────┘
```

An agent can say "check the `tests` pane" or "switch to the `server` pane" without needing to know pane numbers. When Claude Code agent teams are enabled, teammates automatically get named panes so the orchestrator can coordinate them.

### Visual Design

- **Dark theme** with amber active pane borders, dim inactive panes
- **Pane labels** in top border showing `session:pane command`
- **Active pane** has bright white text; inactive panes dim to grey
- **Window tabs** with gold highlight on current window
- **SSH detection** — prefixes `[SSH]` to session name and terminal title when remote
- **Ghostty/iTerm2/VS Code** terminal title integration (`session:window`)

### Session Persistence

- **tmux-resurrect** saves pane layouts, working directories, and running commands
- **tmux-continuum** auto-saves every 15 minutes and restores on server start
- Survive reboots, crashes, and SSH disconnects

### Clipboard

- **OSC 52** for remote clipboard (copy from SSH tmux to local clipboard)
- **vi copy mode** with `v` to select, `y` to yank
- **Mouse drag** auto-copies selection
- Works across Ghostty, iTerm2, VS Code, and most modern terminals

### Agent Teams

The skill enables `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` so Claude Code can spawn parallel teammates in tmux panes. Combined with pane naming, this gives you a multi-agent workspace where each teammate has a named, addressable pane.

## How the AI Limit APIs Work

Both APIs are undocumented and reverse-engineered. They may change without notice.

### Claude: Messages API Rate Limit Headers

The dedicated usage endpoint (`/api/oauth/usage`) returns persistent 429 errors. Instead, we send a throwaway Haiku request and read the response headers:

```
anthropic-ratelimit-unified-5h-utilization: 0.03    # 0.0-1.0
anthropic-ratelimit-unified-5h-reset: 1773446400    # Unix timestamp
anthropic-ratelimit-unified-7d-utilization: 0.24
anthropic-ratelimit-unified-7d-reset: 1773997200
```

Required headers for OAuth authentication:
```
Authorization: Bearer <token>
User-Agent: claude-code/2.1.5
anthropic-beta: oauth-2025-04-20
anthropic-version: 2023-06-01
```

### Codex: WHAM Usage API

```bash
curl -H "Authorization: Bearer <token>" \
  "https://chatgpt.com/backend-api/wham/usage"
```

Returns `rate_limit.primary_window` (5h), `rate_limit.secondary_window` (weekly), `credits`, `plan_type`, and `limit_reached`.

Token lives in `~/.codex/auth.json` → `tokens.access_token`.

## Make It Yours

This isn't a rigid plugin you install and forget. It's a skill — a set of config files and scripts that Claude deploys and you own. The files live in `~/.claude/skills/setup-tmux/` (canonical) and get deployed to `~/.tmux.conf` and `~/.tmux/scripts/`.

Want to change something? Just ask Claude:

- *"change the status bar colors to dracula theme"*
- *"add a battery indicator to line 0"*
- *"remove the Codex line, I only use Claude"*
- *"make the pane borders blue instead of amber"*

Or edit the files directly — they're just bash scripts and a tmux config. Edit `~/.tmux/scripts/` for quick tweaks, or edit the canonical sources in `~/.claude/skills/setup-tmux/` so your changes persist across `/setup-tmux` runs.

## Files

```
~/.tmux.conf                          # Main config (deployed from skill)
~/.tmux/scripts/
├── sys-stats.sh                      # System stats (CPU, RAM, GPU)
├── claude-limits.sh                  # Claude Code 5h + weekly limits
└── codex-limits.sh                   # Codex 5h + weekly limits + credits
~/.tmux/plugins/
├── tpm/                              # Plugin manager
├── tmux-resurrect/                   # Session save/restore
└── tmux-continuum/                   # Auto-save + auto-restore
```

## Why a Skill Instead of a Plugin?

Traditional tmux plugins (TPM) can install shell scripts and set options, but they can't:

- Detect your terminal and configure Meta key settings
- Show you a diff before overwriting your config
- Set up macOS sudoers for GPU stats
- Enable Claude Code agent teams
- Adapt to your specific machine (SSH vs local, Ghostty vs iTerm2, Apple Silicon vs NVIDIA)

A Claude Code skill handles all of this conversationally. Run `/setup-tmux` on a fresh EC2 instance or your local Mac — it figures out what's needed and asks when it's unsure.

## Credits

- Rate limit header technique adapted from [Claude Usage Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker) by Hamed Elfayome
- Codex usage API from [CodexBar](https://github.com/steipete/CodexBar) by Peter Steinberger

## License

MIT
