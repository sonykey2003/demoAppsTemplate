# SEA Bank Demo — React Native + Node microservices (RUM / APM)

A re-brandable **iOS banking demo** for showcasing **Splunk RUM / AppDynamics mobile RUM**
and backend **APM**. A React Native app (login, check balance, money transfer — all fake)
talks to a small set of Node.js/TypeScript microservices on Kubernetes, with **built-in
fault/latency injection** and a **load generator** so you can break things on demand.

The app re-skins instantly across the **top-15 Southeast Asia bank brands** via a logo/theme
switcher, so you can tailor a live demo to whichever bank is in the room.

> All data is synthetic. No real customer data, credentials, or bank logos are used
> (brands render as neutral monograms — see [docs/DATA_AND_PRIVACY.md](docs/DATA_AND_PRIVACY.md)).

Observability is **detached / console-managed** — this repo ships **no** agents or ingest
tokens. You add Splunk / AppDynamics instrumentation out of band (Kubernetes console for the
backend; a gated SDK for the app). The demo groups under the environment tag **`shawn-rum`**.

---

## What's here

```
native_iOS/
  app/          React Native app (iOS): login / balance / transfer, brand switcher,
                Demo Controls, gated RUM (Splunk or AppDynamics)
  services/     npm-workspace monorepo: packages/common + apps/{api-gateway,
                auth-service, account-service, transfer-service}
  k8s/          kustomize base + demo overlay (+ generated all.yaml)
  scripts/      build / deploy / smoke-test / load / fault-inject / init-app
  docs/         architecture, deployment, instrumentation, RUM, runbook, ...
```

| Service | Port | Responsibility |
|---|---|---|
| api-gateway | 8080 | BFF; the only backend the app talks to; aggregates the dashboard; fans faults out |
| auth-service | 8081 | Login + session (fake credentials, HMAC demo tokens) |
| account-service | 8082 | Accounts, balances (cache hit/miss), transactions, debit/credit |
| transfer-service | 8083 | Validate → create → **async settle** (continues the same trace) |

Data is in-memory with simulated `db.query` / cache spans, so the whole backend runs with
**zero external dependencies** (no Postgres/Redis to manage). See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Quick start

### 1. Backend (minikube)

```bash
minikube start -p sea-bank-demo --cpus=4 --memory=6144
kubectl config use-context sea-bank-demo
eval "$(minikube -p sea-bank-demo docker-env)"

cd native_iOS
./scripts/build-images.sh
./scripts/deploy.sh
./scripts/smoke-test.sh          # login -> dashboard -> transfer -> settle
./scripts/port-forward-gateway.sh  # http://localhost:8080
```

### 2. App (iOS)

```bash
cd native_iOS
./scripts/init-app.sh            # one-time: generates app/ios, installs pods
cd app && npm run ios            # boots the iOS simulator
```

Point the app at the gateway in [app/src/config.ts](app/src/config.ts) (`apiBaseUrl`,
default `http://localhost:8080`). Demo users: `demo/demo`, `alice/password`, `bob/password`.

### 3. Break things (APM/RUM demo)

```bash
./scripts/fault-inject.sh latency 2000       # +2s across all services
./scripts/fault-inject.sh error 0.5          # fail 50%
./scripts/fault-inject.sh clear
./scripts/load-generator.sh --scenario mixed --duration 120
```

…or use the in-app **Demo Controls** screen (backend faults, per-request fault headers,
and client-side RUM triggers: handled/uncaught errors, unhandled rejection, failed network,
JS-thread freeze).

---

## Build & run the iOS app (local compilation + Xcode Simulator)

Detailed, reproducible steps for compiling the React Native app and running it on the iOS
Simulator against the minikube backend.

### Step 0 — Prerequisites (one-time)

Install Xcode from the App Store, open it once so it finishes installing components, then:

```bash
xcode-select --install                 # command-line tools
sudo xcodebuild -license accept        # accept the Xcode license
brew install cocoapods node watchman   # CocoaPods + Node >= 20 + Watchman
```

Verify:

```bash
node -v          # >= 20
pod --version    # CocoaPods present
xcrun simctl list devices available    # at least one iOS simulator
```

### Step 1 — Start the backend and expose the gateway

```bash
minikube start -p sea-bank-demo --cpus=4 --memory=6144
kubectl config use-context sea-bank-demo
eval "$(minikube -p sea-bank-demo docker-env)"   # build images into the cluster daemon

cd native_iOS
./scripts/build-images.sh
./scripts/deploy.sh
./scripts/port-forward-gateway.sh        # LEAVE THIS RUNNING → http://localhost:8080
```

Keep the port-forward terminal open. The iOS Simulator shares the Mac's network, so
`localhost:8080` works with no config change (default `apiBaseUrl` in
[app/src/config.ts](app/src/config.ts)). On a **physical device**, set `apiBaseUrl` to your
Mac's LAN IP instead.

### Step 2 — Bootstrap the native iOS project (one-time)

The JS/TS sources are committed; the native `app/ios` project is generated once. This installs
JS deps, generates `app/ios` + `app/android`, and runs `pod install`:

```bash
cd native_iOS
./scripts/init-app.sh
```

### Step 3 — Compile and launch on the Simulator

**Option A — CLI (simplest):**

```bash
cd app
npm run ios                                   # builds + boots the default simulator
# choose a specific device:
npx react-native run-ios --simulator="iPhone 16 Pro"
```

This starts the Metro bundler, compiles the app, boots the Simulator, and installs + launches
it. If Metro doesn't start automatically, run `npm start` in a second terminal.

**Option B — Xcode GUI:**

```bash
open app/ios/SeaBankDemo.xcworkspace          # the .xcworkspace, NOT .xcodeproj
```

In Xcode: pick a simulator in the scheme selector (top bar) → press **▶ Run** (⌘R). Start Metro
first with `cd app && npm start` if it doesn't auto-launch.

### Step 4 — Use it

- Log in with `demo/demo` (or `alice/password`, `bob/password`).
- **Dashboard** → balances; **Transfer money**; **Switch bank brand** to cycle the 15 brands;
  **Demo controls** to inject faults / trigger RUM events.

### Step 5 — (Optional) Enable RUM

Edit [app/src/config.ts](app/src/config.ts): set `rum.provider` to `'splunk'` or
`'appdynamics'`, fill the token/appKey, then rebuild (repeat Step 3). For AppDynamics also run
`cd app && npm run appd:instrument` before rebuilding. See [docs/RUM.md](docs/RUM.md).

> Gotchas: always open `SeaBankDemo.xcworkspace` (not the `.xcodeproj`); if you hit
> "Native module not linked," re-run `cd app/ios && pod install`. More in
> [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

---

## Observability (opt-in, both platforms)

- **Backend APM** — install Kubernetes/Node auto-instrumentation from your console
  (Splunk `splunk-otel-js` via the OTel Operator, or the AppDynamics Node.js agent).
  The services already emit custom OpenTelemetry spans/metrics; nothing is baked in.
  See [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md).
- **Mobile RUM** — set `rum.provider` + token/appKey in [app/src/config.ts](app/src/config.ts)
  and rebuild. See [docs/RUM.md](docs/RUM.md).

Everything lands under environment **`shawn-rum`**.

## Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
- [docs/INSTRUMENTATION.md](docs/INSTRUMENTATION.md) · [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md) · [docs/RUM.md](docs/RUM.md)
- [docs/DEMO_RUNBOOK.md](docs/DEMO_RUNBOOK.md) · [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) · [docs/DATA_AND_PRIVACY.md](docs/DATA_AND_PRIVACY.md)
- [app/README.md](app/README.md)
