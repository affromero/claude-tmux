---
name: setup-tmux
description: Install or update tmux configuration, plugins, status bar with system stats, color settings, and Claude Code agent teams on any machine
user_invocable: true
---

# Setup tmux

Install or update the standard tmux configuration with mouse scrolling, session persistence, proper colors, system stats status bar, and Claude Code agent teams.

**Canonical config files** (in this skill directory):
- `~/.claude/skills/setup-tmux/tmux.conf` — the tmux config (install to `~/.tmux.conf`)
- `~/.claude/skills/setup-tmux/sys-stats.sh` — system stats status bar (install to `~/.tmux/scripts/sys-stats.sh`)
- `~/.claude/skills/setup-tmux/claude-limits.sh` — Claude Code rate limits status bar (install to `~/.tmux/scripts/claude-limits.sh`)
- `~/.claude/skills/setup-tmux/codex-limits.sh` — Codex rate limits status bar (install to `~/.tmux/scripts/codex-limits.sh`)

## Steps

### 1. Check prerequisites

```bash
which tmux || echo "MISSING"
```

If tmux is not installed:
- Ubuntu/Debian: `sudo apt update && sudo apt install -y tmux`
- macOS: `brew install tmux`
- If sudo is not available, tell the user to install tmux first and STOP.

### 2. Read the canonical config

Read `~/.claude/skills/setup-tmux/tmux.conf`. This is the single source of truth for the config content.

### 3. Check existing config and write

```bash
cat ~/.tmux.conf 2>/dev/null || echo "NO_CONFIG"
```

- If `NO_CONFIG`: write the config from the reference directly to `~/.tmux.conf`
- If config exists: compare with the reference config. Show the user a diff of what will change and **ask for confirmation** before overwriting.

### 4. Install TPM (tmux plugin manager)

```bash
if [ -d ~/.tmux/plugins/tpm ]; then
    echo "TPM already installed"
    cd ~/.tmux/plugins/tpm && git pull
else
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi
```

### 5. Install plugins

```bash
~/.tmux/plugins/tpm/bin/install_plugins
```

This installs tmux-resurrect and tmux-continuum without needing an active tmux session.

### 6. Install status bar script (`~/.tmux/scripts/sys-stats.sh`)

The tmux config references `~/.tmux/scripts/sys-stats.sh` for the status bar. This is a cross-platform script (macOS/Linux/Windows) that shows hostname, OS, CPU, RAM, and GPU stats with tmux color formatting.

**The canonical source for this script is `~/.claude/skills/setup-tmux/sys-stats.sh`.** Read it and write to `~/.tmux/scripts/sys-stats.sh`. If the target already exists and matches, skip.

```bash
mkdir -p ~/.tmux/scripts
```

Write the sys-stats.sh script to `~/.tmux/scripts/sys-stats.sh` and make it executable:

```bash
chmod +x ~/.tmux/scripts/sys-stats.sh
```

**Platform-specific stats sources:**

| Stat | macOS | Linux | Windows (MSYS/Cygwin) |
|------|-------|-------|-----------------------|
| CPU | `top -l 2` (2nd sample) | `/proc/stat` (2 samples) | `wmic` |
| RAM | `vm_stat` (active+wired+compressed) | `/proc/meminfo` | PowerShell |
| GPU name | `sysctl machdep.cpu.brand_string` | `nvidia-smi` / sysfs / `lspci` | `nvidia-smi.exe` |
| GPU usage | `powermetrics` (HW active residency) | `nvidia-smi` / AMD sysfs / `intel_gpu_top` | `nvidia-smi.exe` |
| GPU power | `powermetrics` (mW) | `nvidia-smi` (W) / AMD hwmon | `nvidia-smi.exe` |

**macOS GPU setup** — Apple Silicon has no unprivileged GPU stats API. Ask user to run:

```bash
echo '%admin ALL=(ALL) NOPASSWD: /usr/bin/powermetrics' | sudo tee /etc/sudoers.d/powermetrics
sudo chmod 0440 /etc/sudoers.d/powermetrics
```

Without this, GPU stats are silently omitted (everything else still works). On Linux with NVIDIA/AMD/Intel GPUs, no extra setup is needed.

**Formatting rules:**
- Labels in gold (`colour214`), values in white (`colour255`), separators in dim grey (`colour238`)
- CPU/GPU usage: right-aligned 2-digit integers (`%2d%%`)
- RAM: 1 decimal for both used and total (`%.1f/%.1fG`)
- GPU power: right-aligned 4-digit mW (`%4dmW`) on macOS, Watts on Linux/Windows

Verify the script runs:

```bash
~/.tmux/scripts/sys-stats.sh
```

Expected output (with tmux color codes): `hostname │ OS │ CPU  25% │ RAM 22.7/36.0G │ GPU Apple M3 Max  7%  143mW`

### 6b. Install AI rate limit scripts

Two additional scripts provide Claude Code and Codex rate limits in tmux status lines 1 and 2.

**`claude-limits.sh`** — reads from `~/.claude/skills/setup-tmux/claude-limits.sh`, installs to `~/.tmux/scripts/claude-limits.sh`
- Reads OAuth token from macOS Keychain (`Claude Code-credentials`) or `~/.claude/.credentials.json`
- Queries `api.anthropic.com/api/oauth/usage` for 5h and weekly limits
- Caches for 60s to avoid hammering the API
- Shows: `Max Claude │ 5h 84% ████░░░░ (120m) │ Wk 77% ███░░░░░ (Mar 20)`
- Color-coded: green (>50%), amber (20-50%), red (<20%)

**`codex-limits.sh`** — reads from `~/.claude/skills/setup-tmux/codex-limits.sh`, installs to `~/.tmux/scripts/codex-limits.sh`
- Reads bearer token from `~/.codex/auth.json`
- Queries `chatgpt.com/backend-api/wham/usage` for 5h and weekly limits
- Caches for 60s
- Shows: `Plus Codex │ 5h 84% ████░░░░ (120m) │ Wk 77% ███░░░░░ (Mar 20) │ Credits ∞`
- Color-coded same as Claude

```bash
cp ~/.claude/skills/setup-tmux/claude-limits.sh ~/.tmux/scripts/claude-limits.sh
cp ~/.claude/skills/setup-tmux/codex-limits.sh ~/.tmux/scripts/codex-limits.sh
chmod +x ~/.tmux/scripts/claude-limits.sh ~/.tmux/scripts/codex-limits.sh
```

Verify both run:

```bash
~/.tmux/scripts/claude-limits.sh
~/.tmux/scripts/codex-limits.sh
```

**Notes:**
- Both scripts require `python3` and `curl`
- Claude script requires macOS Keychain access (or `~/.claude/.credentials.json` fallback)
- Codex script requires `~/.codex/auth.json` (created by `codex login`)
- If either API is unreachable, the script shows a graceful fallback message
- Both APIs are undocumented/reverse-engineered — they may change without notice
- tmux `status 3` requires tmux 3.4+ (check with `tmux -V`)

### 7. Reload config (if tmux is running)

```bash
if tmux list-sessions 2>/dev/null; then
    tmux source-file ~/.tmux.conf
    echo "Config reloaded in active tmux server"
else
    echo "No active tmux server — config will apply on next tmux start"
fi
```

### 8. macOS: Configure Option as Meta key

Alt+arrow pane switching requires the terminal to send Meta escape sequences. On macOS, Option does not do this by default.

**First, detect if running inside Ghostty:**

```bash
echo "TERM=$TERM TERM_PROGRAM=$TERM_PROGRAM"
```

- If `TERM=xterm-ghostty` or `TERM_PROGRAM=ghostty`: **Skip this step entirely.** Ghostty already sends Meta via `macos-option-as-alt = true` in its config. Tell the user this is already handled by Ghostty.

Otherwise, **ask the user which terminal they use** (use AskUserQuestion with these options):

- **Ghostty**: Skip — `macos-option-as-alt = true` is already in the Ghostty config. Suggest running `/setup-ghostty` if they haven't configured it yet.
- **VS Code / Cursor**: Programmatically add `"terminal.integrated.macOptionIsMeta": true` to `~/Library/Application Support/Code/User/settings.json` (or the Cursor equivalent). Read the file, merge the key, write it back. Tell the user to restart their terminal tabs.
- **iTerm2**: Tell the user to go to `Settings → Profiles → Keys → General` and set **Left Option key** to `Esc+`. This cannot be set programmatically.
- **Terminal.app**: Tell the user to go to `Settings → Profiles → Keyboard` and check **Use Option as Meta key**. This cannot be set programmatically.
- **Other / SSH / Linux**: Skip this step — Meta usually works out of the box.

### 9. VS Code / Cursor tab title

If running inside Ghostty (`TERM=xterm-ghostty` or `TERM_PROGRAM=ghostty`), **skip this step** — Ghostty shows tab titles natively via its `title` shell integration feature.

Otherwise, remind the user to set this in their **local** editor settings (not remote):

```json
"terminal.integrated.tabs.title": "${sequence}"
```

This makes terminal tabs show the tmux session name instead of "tmux".

### 10. Ghostty terminfo (remote machines only)

If running inside Ghostty on a remote machine (`TERM=xterm-ghostty` and this is not macOS):

```bash
infocmp xterm-ghostty 2>/dev/null && echo "INSTALLED" || echo "MISSING"
```

If `MISSING`: the terminfo entry is needed for tmux and other tools to work correctly. Run `/setup-ghostty` to install it, or tell the user to enable `shell-integration-features = ssh-terminfo` in their local Ghostty config so it auto-installs on future SSH connections.

If `INSTALLED`: skip — everything is fine.

### 11. Enable Claude Code agent teams

Agent teams let Claude spawn multiple teammates automatically.

Read `~/.claude/settings.json` and ensure the env key is present:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

- If `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is missing from `env`, add it
- If already set, skip this step
- **Do not touch `teammateMode`** — respect whatever the user has set (`in-process`, `tmux`, or `auto`)
- **Do not overwrite other keys** in settings.json — merge only

### 12. Verify

Report what was done:
- Config written/updated: yes/no (and what changed if updated)
- TPM: installed/updated
- Plugins: installed (list which ones)
- tmux version: `tmux -V`
- Config reloaded: yes/no
- Agent teams: enabled/already enabled

Key config features to confirm are present (all defined in the reference):
- Mouse support (scroll, click, resize panes by dragging)
- Vi copy mode with system clipboard integration (`pbcopy` + OSC 52)
- Active pane border highlight (amber) with dim inactive borders
- Inactive pane dimming (grey text + dark background) to focus attention on the active pane
- Arrow key pane switching (`Ctrl+b arrow`) — works on macOS without Meta key config
- Alt+arrow pane switching (Meta key configured in step 7)
- WASD pane resizing (`Ctrl+b Shift+W/A/S/D`) — 5 cells per press, repeatable
- Pane names in borders — each pane shows `index:command` in the top border (dim grey, subtle)
- Rename pane title: `Ctrl+b T` — set a custom name for AI tooling reference
- Easy splits: `Ctrl+b |` (horizontal) and `Ctrl+b -` (vertical)
- Session persistence via tmux-resurrect + tmux-continuum
- 3-line status bar (requires tmux 3.4+):
  - Line 0: System stats (hostname, OS, CPU, RAM, Disk, GPU)
  - Line 1: Claude Code rate limits (5h + weekly, color-coded bars)
  - Line 2: Codex rate limits (5h + weekly, credits, color-coded bars)
- Status bar colors: gold labels (system), purple labels (Claude), green labels (Codex)
- `~/.tmux/scripts/sys-stats.sh` exists and is executable
- `~/.tmux/scripts/claude-limits.sh` exists and is executable
- `~/.tmux/scripts/codex-limits.sh` exists and is executable
- macOS GPU: sudoers entry for powermetrics (or user informed it's needed)
- AI limit scripts cache for 60s (won't hammer APIs)
