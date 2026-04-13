<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=flat&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/SwiftUI-blue?style=flat&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/Claude_API-CC785C?style=flat" />
  <img src="https://img.shields.io/badge/license-MIT%20%2B%20Commons%20Clause-red?style=flat" />
</p>

<h1 align="center">FocusGuard</h1>
<p align="center">macOS menu bar app that tracks your screen activity and uses AI to categorize your focus sessions in real time.</p>

---

## Features

- **Activity tracking** — monitors the active app and window title every few seconds via Accessibility API
- **AI categorization** — sends activity data to Claude API and classifies it (Deep Work, Communication, Social Media, etc.)
- **Menu bar interface** — lives in your menu bar, zero distraction
- **Custom rules** — define your own categories and keyword-based matching rules
- **Session history** — all events persisted locally with SwiftData

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI + MenuBarExtra |
| Data | SwiftData |
| Activity tracking | NSWorkspace + Accessibility API |
| AI | Claude API (Anthropic) |
| Secure storage | Keychain |

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+
- Anthropic API key

## Getting Started

```bash
git clone https://github.com/ayeresell/FocusGuard.git
open FocusGuard.xcodeproj
```

1. Build & run in Xcode
2. Grant **Accessibility** permissions when prompted (`System Settings → Privacy & Security → Accessibility`)
3. Open **Settings** in the menu bar and paste your Anthropic API key
