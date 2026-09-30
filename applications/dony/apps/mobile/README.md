# Dony Solari for iPhone

This is the existing Dony mobile app copied into the Solari cookbook. See the [application README](../../README.md) for scope, configuration, and the pending cloud-browser feature.

## Build

From `applications/dony`, a simulator build without device signing is:

```sh
xcodebuild -project apps/mobile/DonyMobile.xcodeproj \
  -scheme DonyMobile -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/dony-solari-derived CODE_SIGNING_ALLOWED=NO build
```

For simulator execution and tests, keep signing enabled so Keychain works. Find an installed simulator with `xcrun simctl list devices available`, then use its ID:

```sh
xcodebuild -project apps/mobile/DonyMobile.xcodeproj \
  -scheme DonyMobile -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath /tmp/dony-solari-tests \
  -only-testing:DonyMobileTests test
```

A physical-device build requires your own Apple development team and provisioning profile. This fork has a separate bundle ID and URL scheme; production Dony pairing links do not target it.

## Existing test modes

Debug `--ui-testing --reset-todos` uses a disposable data store. Add `--onboarding-testing` to preview onboarding. These fixtures do not prove authentication, billing, or AI execution against live services.

Most UI tests can run with `-only-testing:DonyMobileUITests`. Some existing connected UI tests depend on desktop fixtures that are not included here and skip when those fixtures are unavailable. The API-based agent fixture is included: run `pnpm dev:fixture` from `applications/dony` to test mobile agent editing.

Local builds, Xcode user state, and test-result bundles are ignored by Git.
