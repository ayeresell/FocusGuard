# FocusGuard

A macOS menu bar app that tracks your productivity by monitoring active applications and windows, then uses AI to analyze and categorize your focus sessions.

## Features

- **Automatic activity tracking** — monitors active app and window title in real time
- **AI-powered categorization** — uses Claude API to classify activities (work, social, entertainment, etc.)
- **Menu bar interface** — always accessible, minimal footprint
- **Custom categories and rules** — define your own productivity categories and matching rules
- **Focus session history** — persistent storage of all activity events via SwiftData

## Tech Stack

- Swift + SwiftUI
- SwiftData (local persistence)
- Accessibility API (app/window tracking)
- Claude API (AI categorization)
- macOS MenuBarExtra

## Requirements

- macOS 14 (Sonoma) or later
- Accessibility permissions (for window title tracking)
- Anthropic API key (for AI features)

## Setup

1. Clone the repo and open `FocusGuard.xcodeproj` in Xcode
2. Build and run
3. Grant Accessibility permissions when prompted
4. Add your Anthropic API key in Settings

## Screenshots

_Coming soon_
