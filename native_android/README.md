# SEA Bank Demo — Android

The **Android build** of the re-brandable React Native banking app (login, balance,
transfer) for **Splunk RUM / AppDynamics** mobile RUM demos.

This folder contains the **app only**. It talks to the **same backend** as the iOS
demo (the microservices + K8s + Splunk instrumentation live under
[`../native_iOS`](../native_iOS)) — nothing backend is duplicated. The app's JS/TS is
the same cross-platform source as the iOS app, tuned for Android:

- `apiBaseUrl` is platform-aware — Android uses `http://10.0.2.2:8080` (the emulator's
  alias for your Mac) instead of `localhost`.
- RUM `applicationName` is `shawn-rum-android` (so it's distinct from `shawn-rum-ios`),
  same environment tag `shawn-rum`.

> **React Native version:** this Android app is on **RN 0.77.3**, while the iOS app is on
> RN 0.76.5. That's intentional — the Splunk RUM Android SDK (`@splunk/otel-react-native`)
> is built with **Kotlin 2.1** metadata, which RN 0.76's Kotlin 1.9 toolchain can't compile.
> RN 0.77 ships **Kotlin 2.0.21**, which reads it. The two apps are independent projects,
> so the version difference is fine. `scripts/init-android.sh` pins RN 0.77.3.

> Data is synthetic; brands render as neutral monograms (not real logos). RUM is
> off until you set a token. See [../native_iOS/docs/DATA_AND_PRIVACY.md](../native_iOS/docs/DATA_AND_PRIVACY.md).

## Prerequisites
- Android Studio + Android SDK + JDK 17, and an emulator (AVD) or a device.
- Node ≥ 20, Watchman (recommended).
- The backend running (see below).

## Quick start

```bash
# 1. Backend (from the iOS folder — shared):
cd ../native_iOS
./scripts/deploy.sh
./scripts/port-forward-gateway.sh          # http://localhost:8080 (host) → 10.0.2.2 in the emulator

# 2. Android app (one-time native bootstrap):
cd ../native_android
./scripts/init-android.sh                  # installs deps, generates app/android, applies tweaks

# 3. Run:
cd app && npm run android
```

Demo users: `demo/demo`, `alice/password`, `bob/password`.

## RUM (optional)
Put a Splunk **RUM** access token in the gitignored [app/.env](app/.env):

```
SPLUNK_RUM_ACCESS_TOKEN=<your RUM token>
```

Then rebuild (restart Metro with `npm start -- --reset-cache` after editing `.env`).
In O11y RUM filter **Source: Mobile**, **Environment: `shawn-rum`**, **App: `shawn-rum-android`**.
Full details (incl. AppDynamics) in [../native_iOS/docs/RUM.md](../native_iOS/docs/RUM.md).

## Viewing JS logs (RN 0.77)
RN 0.77 moved JavaScript `console` logs out of the Metro terminal into **React Native
DevTools**. Press **`j`** in the Metro terminal to open it (needs Chrome/Edge). The
`[telemetry] … RUM initialized` line and other `console.log` output appear there, not in
Metro's stdout.

## What `init-android.sh` sets up
Generating the native project can't be committed, so the script does it and applies the
Android-specific bits this demo needs:
- Pins **React Native 0.77.3** (Kotlin 2.0.21) — needed to compile the Splunk RUM Android SDK.
- **Core-library desugaring** in `app/android/app/build.gradle` (required by the Splunk RUM Android SDK; minSdk 24).
- **Cleartext HTTP** (`usesCleartextTraffic=true`) so the emulator can reach `http://10.0.2.2:8080` (demo only — don't ship cleartext).
- **`ACCESS_NETWORK_STATE`** permission (used by the AppDynamics agent).

## Relationship to the iOS app
The JS/TS here is a copy of [`../native_iOS/app`](../native_iOS/app) tuned for Android.
If you change shared screens/logic, apply it to both (or later refactor to a shared
package). The backend, K8s, and Splunk collector setup are shared and unchanged.
