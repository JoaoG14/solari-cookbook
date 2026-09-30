# Dony

**The to-do list that does itself.**

Give Dony a task and let its AI agents work on it from a native iPhone app.

## How we use Solari

Dony uses [Solari](https://getsolari.com) to give its agents a cloud browser. Agents can open websites, follow links, fill fields, and read pages to complete tasks. You can watch their progress from the app through a read-only browser preview that refreshes about every two seconds.

Tap the **globe button beside Search** in a conversation to open the preview. Browser sessions close when a run finishes, is canceled, fails, or pauses for a question.

## Find the app

All Dony code lives in **[applications/dony](applications/dony)**.

| Directory | Contents |
| --- | --- |
| [iPhone app](applications/dony/apps/mobile) | SwiftUI app and Xcode project |
| [API](applications/dony/packages/api) | Backend, AI task worker, and Solari integration |
| [Shared domain](applications/dony/packages/domain) | Shared schemas and task/chat behavior |

## Run the demo

You need macOS with Xcode 26 or later, an iPhone simulator, Node.js 24.14.1 or later, and pnpm 10.11.0.

```sh
cd applications/dony
pnpm install --frozen-lockfile
pnpm build
cp .env.example .env
```

Add **`SOLARI_API_KEY`** and **`DONY_OPENROUTER_API_KEY`** to `.env`, then run:

```sh
pnpm dev:demo
```

Open `applications/dony/apps/mobile/DonyMobile.xcodeproj` in Xcode, select **DonyMobile**, and run an iPhone simulator. Use **Continue with Google** to enter the local demo account; this development flow does not contact Google.

The demo uses a disposable local database and makes real Solari and OpenRouter requests with your keys. No email connection or subscription setup is required.

See the **[Dony README](applications/dony/README.md)** for a sample task, detailed setup, tests, and current limitations.
