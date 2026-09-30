# Dony mobile

Dony's existing native iPhone app and cloud API, copied here as the foundation for a Solari cloud-browser integration. **The Solari feature is not implemented yet.** The planned mobile browser preview is read-only.

Source: Dony commit `b24435c9cc2e937cafcd1ae57384c3c2b5372832` (September 30, 2026). Only tracked mobile, API, and shared-domain files were imported. Desktop code, credentials, local databases, build products, and simulator evidence are not part of this application.

## Layout

| Directory | Contents |
| --- | --- |
| `apps/mobile` | SwiftUI app, assets, Xcode project, unit tests, and UI tests |
| `packages/api` | Hono API, cloud task worker, authentication, billing, connectors, and D1 gateway |
| `packages/domain` | Shared schemas and task/chat behavior used by the API |

The app keeps Dony's existing screens and behavior. This copy uses the `com.dony.solari.mobile` bundle identifier, the `dony-solari-mobile` callback scheme, and the display name **Dony Solari**. Its default API is `http://127.0.0.1:8787`. The original Apple development team, Superwall public key, and production D1 database ID have been removed from the copied configuration.

## Requirements

- macOS with Xcode 26 or later and an installed iPhone simulator (the app targets iOS 18+).
- Node.js 24.14.1 or later and pnpm 10.11.0.
- No service credentials are needed to build or run the automated tests.
- Live AI execution needs an OpenRouter key. Google/Apple sign-in, Composio connectors, StoreKit/Superwall billing, and APNs need their own configuration. They are not provisioned by this copy.

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

## Run the API locally

```sh
cp .env.example .env
cp packages/api/d1/.dev.vars.example packages/api/d1/.dev.vars
pnpm build
pnpm dev:db
```

Leave the local database gateway running on port 8788. In a second terminal, from this directory:

```sh
pnpm dev:api
```

The API listens on port 8787. `curl http://127.0.0.1:8787/health` checks it. The supplied development tokens are for local testing only. Replace them and configure real authentication before exposing a server. The D1 ID is a local placeholder; remote deployment requires a separate database and credentials.

The existing development-auth flow lets the simulator's **Continue with Google** button return a local development account without contacting Google. It does not enable paid cloud execution or simulate a live model. The original billing checks remain in place.

## Run the iPhone app

Open `apps/mobile/DonyMobile.xcodeproj`, select **DonyMobile**, and run on an iPhone simulator. The shared scheme uses Debug. To select another development backend, add `DONY_MOBILE_API_URL` to the scheme's Run environment. A physical phone needs a reachable backend address and your own signing team.

For an isolated UI preview without a backend, use Debug launch arguments:

```text
--ui-testing --reset-todos
```

These select the app's existing disposable test store. They do not exercise cloud execution. See [mobile build and test commands](apps/mobile/README.md).

## Next stage

After the mobile baseline is reviewed, add Solari browser tools to the cloud worker and a read-only browser preview to the mobile task flow. A runnable Solari demo and live service verification are still required before submitting this application to the internship challenge.
