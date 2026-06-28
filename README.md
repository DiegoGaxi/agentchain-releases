# AgentChain

> **Local-first AI agent orchestrator.** Run chains, workflows and cron jobs of AI agents on *your* machine with *your* API keys (BYOK) — with a desktop Pet companion, voice control, and a built-in browser the agents can drive.

<p align="center">
  <img src="https://raw.githubusercontent.com/DiegoGaxi/agentchain-releases/main/assets/agentchain-space.png" alt="AgentChain — the Space, with your agent Pet" width="100%">
</p>


This repository hosts the **downloads and the auto-update feed** for the AgentChain desktop app. (The source lives in a separate private repository.)

---

## Install

### One command (recommended)

**Linux / macOS**
```bash
curl -fsSL https://raw.githubusercontent.com/DiegoGaxi/agentchain-releases/main/install.sh | bash
```

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/DiegoGaxi/agentchain-releases/main/install.ps1 | iex
```

The script detects your OS/arch, downloads the latest build, verifies its SHA‑256 checksum, and installs it (Linux → `~/.local/bin` + an app‑menu entry; macOS → `/Applications`; Windows → runs the installer). It also sorts out the Linux FUSE requirement and the macOS Gatekeeper quarantine for you.

### Manual download

Grab the latest from the **[Releases page](https://github.com/DiegoGaxi/agentchain-releases/releases/latest)**:

| OS | File |
|---|---|
| **Linux** | `AgentChain-<version>.AppImage`  •  `agentchain_<version>_amd64.deb` |
| **macOS** (Apple Silicon) | `AgentChain-<version>-arm64.dmg` |
| **Windows** | `AgentChain-Setup-<version>.exe` |

Each release also publishes `SHA256SUMS-<platform>.txt` so you can verify your download.

---

## Platform notes

> Builds are currently **unsigned** (code‑signing certificates are on the roadmap). Everything runs on all three OSes; the notes below cover the first‑launch friction that comes with unsigned apps.

- **macOS** — unsigned, so Gatekeeper may block a manually‑downloaded `.dmg` ("can't be opened" / "unidentified developer"). Right‑click the app → **Open**, or run `xattr -cr /Applications/AgentChain.app`. *The installer clears the quarantine for you.* (Apple Silicon only for now.)
- **Windows** — unsigned, so SmartScreen may warn on first run. Click **More info → Run anyway**.

---

## What it does

- **Agent chains & workflows** — orchestrate multiple AI agents into multi‑step pipelines.
- **Cron jobs** — schedule recurring agent runs.
- **BYOK** — bring your own provider key; your keys are encrypted at rest and never leave your machine.
- **Local‑first** — the backend, database and job queue all run on your device.
- **Desktop Pet + voice** — a companion you can talk to (wake‑word + speech), plus a built‑in browser the agents can control.
- **Telegram** — optionally drive it from your phone.

---

## Updating

- **Windows** — updates in‑app automatically.
- **Linux / macOS** — re‑run the one‑command install above to update. *(Signed auto‑update is on the roadmap.)*


