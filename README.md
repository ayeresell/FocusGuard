<p align="center">
  <img src="https://app-eta-seven-61.vercel.app/banner-focusguard.svg" width="900"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=flat&logo=apple&logoColor=white"/>
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat&logo=swift&logoColor=white"/>
  <img src="https://img.shields.io/badge/SwiftUI-blue?style=flat&logo=swift&logoColor=white"/>
  <img src="https://img.shields.io/badge/SwiftData-purple?style=flat&logo=swift&logoColor=white"/>
  <img src="https://img.shields.io/badge/Claude_API-CC785C?style=flat"/>
  <img src="https://img.shields.io/badge/license-MIT%20%2B%20Commons%20Clause-red?style=flat"/>
</p>

<h2 align="center">FocusGuard — трекер продуктивности для macOS</h2>
<p align="center">Приложение в строке меню, которое в реальном времени отслеживает активные приложения и использует ИИ для классификации твоих сессий.</p>

---

## Как это работает

```
NSWorkspace                Accessibility API
     │                           │
     ▼                           ▼
 Активное приложение  +  Заголовок окна
           │
           ▼
     TrackingService
     (каждые N сек)
           │
           ▼
      Claude API  ──▶  Категория (Deep Work / Social / etc.)
           │
           ▼
       SwiftData  ──▶  История сессий
```

## Возможности

- **Автоматический трекинг** — отслеживает приложение и заголовок окна каждые несколько секунд
- **ИИ-категоризация** — Claude API классифицирует активность в реальном времени
- **Минималистичный интерфейс** — живёт в строке меню, не мешает работе
- **Гибкие правила** — создавай свои категории и правила сопоставления по ключевым словам
- **История сессий** — все события хранятся локально через SwiftData
- **Безопасное хранение ключа** — API-ключ хранится в Keychain, не в файлах

## Стек

| Слой | Технология |
|------|-----------|
| UI | SwiftUI + MenuBarExtra |
| Реактивность | `@Observable` (Observation framework) |
| Хранилище | SwiftData |
| Трекинг | NSWorkspace + Accessibility API |
| ИИ | Claude API (Anthropic) |
| Безопасность | Keychain Services |

## Требования

- macOS 14 Sonoma или новее
- Xcode 15+
- API-ключ Anthropic

## Запуск

```bash
git clone https://github.com/ayeresell/FocusGuard.git
open FocusGuard.xcodeproj
```

1. Собери и запусти в Xcode
2. Выдай разрешение **Accessibility** (`Системные настройки → Конфиденциальность → Универсальный доступ`)
3. Вставь Anthropic API-ключ в настройках приложения
