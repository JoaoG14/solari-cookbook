# Dony mobile

Dony is a native iPhone task and agent app. Its cloud agent can now use a **Solari browser** to inspect websites, click links, fill labeled fields, and read page contents. Tap the **globe button beside Search** in a cloud conversation, or **View browser** in a running task to watch a live, view-only stream. The landscape image fits the available width.

Source: Dony commit `b24435c9cc2e937cafcd1ae57384c3c2b5372832` (September 30, 2026). Only tracked mobile, API, and shared-domain files were imported. Desktop code, credentials, local databases, build products, and simulator evidence are not part of this application.

## Layout

| Directory | Contents |
| --- | --- |
| `apps/mobile` | SwiftUI app, assets, Xcode project, unit tests, and UI tests |
| `packages/api` | Hono API, cloud task worker, authentication, billing, connectors, and D1 gateway |
| `packages/domain` | Shared schemas and task/chat behavior used by the API |

The app keeps Dony's task and chat screens. Onboarding ends after choosing optional browser-based starter tasks; it does not ask reviewers to connect email or choose a subscription. This copy uses the `com.dony.solari.mobile` bundle identifier, the `dony-solari-mobile` callback scheme, and the display name **Dony Solari**. Its default API is `http://127.0.0.1:8787`. The original Apple development team, Superwall public key, and production D1 database ID have been removed from the copied configuration.

## Requirements

- macOS with Xcode 26 or later and an installed iPhone simulator (the app targets iOS 18+).
- Node.js 24.14.1 or later and pnpm 10.11.0.
- No service credentials are needed to build or run the automated tests.
- The submission demo needs **only two service keys**: Solari and OpenRouter. Local sign-in and the disposable database are configured automatically. Connected apps, subscriptions, and push notifications are disabled in this demo.

Run the following commands from **this directory**, not the cookbook root:

```sh
pnpm install --frozen-lockfile
pnpm typecheck
pnpm build
pnpm test
```

The backend tests use disposable databases through Miniflare; they do not connect to Dony's production database or call a live model.

### Baseline verification — September 30, 2026

- iOS simulator build, all 80 mobile unit tests, and the to-do create/edit/complete/relaunch/reopen/delete UI test passed.
- TypeScript checks and the domain/API builds passed.
- Local API startup, development sign-in through the new callback scheme, authenticated account loading, and workspace loading passed.
- Domain tests: 37 passed, 2 failed. API tests: 145 passed, 1 failed. All three failures also reproduce in the original Dony checkout: the transcript fixture and provider catalog expectations in `packages/domain/src/index.test.ts`, and the response-style wording expectation in `packages/api/tests/modelGateway.test.ts`. They were preserved with the baseline. Because `pnpm test` stops after the domain failures, run `pnpm --filter @dony/api test` separately to exercise the API suite.
- No live model, provider login, subscription purchase, push delivery, or Solari session was exercised.

## Try the Solari demo

This is the quickest end-to-end path. It runs the real Dony cloud worker, real Solari browser, and real OpenRouter model with a disposable local database and a development account. Service usage is billed to your keys. There is no subscription purchase in this local demo; the normal API retains Dony's billing checks.

1. Run `pnpm install --frozen-lockfile` and `pnpm build` here.
2. Copy `.env.example` to `.env`. Set `SOLARI_API_KEY` and `DONY_OPENROUTER_API_KEY`. These are the only entries in the example file, and both stay on the server.
3. Run `pnpm dev:demo`. This starts its own local database and listens only on `127.0.0.1:8787`. Missing keys cause a startup error.
4. Open `apps/mobile/DonyMobile.xcodeproj`, choose **DonyMobile**, and run an iPhone simulator. Keep the default API URL and use **Continue with Google** to sign in to the local development account. This flow does not contact Google.
5. Open **Employees**, start a chat, and send: “Use the browser to open https://en.wikipedia.org/wiki/Solar_energy, follow a relevant link, and summarize what you find with source links.” Tap the **globe button beside Search** while Dony works. The same preview is available inside running cloud tasks.
6. Close the preview to disconnect the stream. Stop the run to cancel work. The browser closes when the run finishes, is canceled, fails, or pauses for a question. Press Ctrl-C to stop the demo. Local demo data is discarded when the server exits.

A physical phone needs your own signing team and a reachable authenticated backend; the loopback demo is intended for the iPhone simulator.

### How it works

- `packages/api/src/cloudBrowser.ts` launches `@solarisdk/browser`, uses its Playwright-compatible page API, and owns one fresh context/page per active run. The agent receives bounded accessibility-tree text.
- `cloudWorker.ts` exposes `browser_use` only when `SOLARI_API_KEY` exists. Browser actions share Dony's existing authorization instructions and tool-result checkpoints. Resumed runs open a fresh browser; cookies and login profiles are not persisted.
- `GET /v1/mobile/threads/:id/browser/stream` requires Dony authentication and streams Chromium screencast JPEG frames over server-sent events. It checks ownership and the running job/lease before each frame, rechecks authentication every second, and keeps only the latest pending frame for slow viewers. Responses use `Cache-Control: no-store`. The phone receives images and metadata only; Solari credentials, CDP endpoints, and input controls stay on the server. The original snapshot endpoint remains available for compatibility.
- `CloudBrowserView.swift` consumes one streaming connection while visible and active, clears stale frames after disconnection, and reconnects automatically. Closing the sheet or backgrounding the app cancels the connection. Viewers share one screencast per run; the last viewer disconnecting stops capture without stopping the agent.

### Limits

This version supports one page per run and public websites. Login handoff, persistent profiles, downloads, popup switching, and browser takeover are not implemented. The live preview streams JPEG frames, with delivery capped at about 12 frames per second; actual cadence depends on page changes and connection speed. It carries no audio. Preview frames and sessions are held in the API process, so run a **single API/worker instance**. Browser actions have timeouts, and Dony's existing 10-minute run limit and 30-step limit apply. Cancellation is observed by the worker heartbeat within about 15 seconds. A hard process crash or provider cleanup failure relies on Solari's session expiry; this demo does not add a durable session reaper or Solari billing budget.

### Test the browser flow without service keys

```sh
NODE_OPTIONS=--no-experimental-webstorage pnpm --filter @dony/api exec vitest run --config vitest.config.ts tests/cloudBrowser.test.ts tests/cloud.test.ts
pnpm --filter @dony/api exec tsx tests/helpers/browserMobileServer.ts
```

The first command tests isolation, authentication and revocation, streaming backpressure, screenshot compatibility, canceled runs, URL checks, and cleanup on completion/failure/question/stop. The second starts a simulator fixture on port 18790 with **local Chrome and a scripted model**, using the production worker and mobile routes. It defaults to the macOS Google Chrome path; set `CHROME_PATH` if needed. In another terminal run:

```sh
xcodebuild -project apps/mobile/DonyMobile.xcodeproj -scheme DonyMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:DonyMobileUITests/DonyMobileBrowserUITests test
```

The UI test checks continuous frames, page updates, connection recovery, stream cancellation on dismissal, and browser cleanup at completion. These local tests do not verify Solari provisioning or a live model.

To run the same fixture with a real Solari browser, launch it from this directory with `DONY_BROWSER_FIXTURE_LIVE=1 node --env-file=.env --import tsx packages/api/tests/helpers/browserMobileServer.ts`. This uses your Solari key and a scripted agent with an animated test page; it does not call OpenRouter.

### Integration verification — September 30, 2026

- Streaming update: TypeScript checks, API/domain builds, and all 40 focused cloud/browser tests passed. The iPhone simulator UI flow passed twice against a real Solari browser using the animated fixture and scripted agent: continuous frames, page transitions, reconnect, dismissal stopping capture, and browser cleanup. A separate live provider probe received 33 frames in three seconds. Streaming was also visually checked in the simulator; this does not constitute physical-device or live-model streaming verification.

- TypeScript checks, domain/API builds, and iOS simulator build passed.
- All 34 focused cloud/browser tests passed.
- The iPhone simulator preview journey passed with real local Chrome screenshots: page changes, zoom, reconnect, dismissal stopping requests, and cleanup after completion.
- Local demo startup, development PKCE sign-in, account access, and inactive preview passed using placeholder provider keys without making provider requests. Missing Solari configuration fails with a clear message.
- Live Solari and OpenRouter browsing was verified through computer use in the iPhone simulator: two Wikipedia research requests completed with linked summaries; the preview showed changing pages and supported zoom. Stopping a third run returned the preview to its inactive state. The three inherited baseline test failures listed above remain unchanged.
- Follow-up fixes remove the email/subscription onboarding steps and use browser-based starter tasks. Chat messages now have their full heights measured before scrolling when the composer or keyboard resizes, avoiding lazy height estimates. Eight onboarding unit checks and five UI scenarios passed, covering selected/empty onboarding, relaunch, large text, browser preview, and four conversation turns with long replies and a long third draft. Two further real-model replies in the original conversation also completed during computer-use verification, with Browser and Search still responsive. The original intermittent hang also failed to reproduce in the pre-change automated checks, so its exact root cause remains unconfirmed.

## Run the iPhone app

Open `apps/mobile/DonyMobile.xcodeproj`, select **DonyMobile**, and run on an iPhone simulator. The shared scheme uses Debug. To select another development backend, add `DONY_MOBILE_API_URL` to the scheme's Run environment. A physical phone needs a reachable backend address and your own signing team.

For an isolated UI preview without a backend, use Debug launch arguments:

```text
--ui-testing --reset-todos
```

These select the app's existing disposable test store. They do not exercise cloud execution. See [mobile build and test commands](apps/mobile/README.md).
