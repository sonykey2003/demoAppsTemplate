# Troubleshooting — SEA Bank Demo

## Backend

**Pods not Ready**
```bash
kubectl -n sea-bank-demo get pods
kubectl -n sea-bank-demo logs deploy/api-gateway
kubectl -n sea-bank-demo describe pod <pod>
```
- `ImagePullBackOff` / `ErrImageNeverPull`: images aren't in the cluster's Docker daemon.
  Run `eval "$(minikube -p sea-bank-demo docker-env)"` **before** `./scripts/build-images.sh`,
  or for kind run `./scripts/load-images-kind.sh`.

**Smoke test / app can't reach the gateway**
- Ensure the port-forward is running: `./scripts/port-forward-gateway.sh`.
- `curl localhost:8080/healthz` should return `{"status":"ok"}`.
- On a physical device, `localhost` points at the phone — use your machine's LAN IP in
  `app/src/config.ts`.

**Transfer stays PENDING**
- Settlement runs every ~200ms; give it ~1s. Check `kubectl logs deploy/transfer-service`.
- If it's `FAILED`, an injected fault or insufficient funds hit debit/credit — check
  `./scripts/fault-inject.sh status` and clear with `./scripts/fault-inject.sh clear`.

**Can't clear a 100% error injection**
- The gateway's `/api/admin/fault` routes run before its fault middleware, so
  `./scripts/fault-inject.sh clear` (DELETE) always works. If you injected directly on a
  single service, `curl -X DELETE localhost:8080/api/admin/fault` fans the clear to all.

## App build

**`pod install` fails / "Native module not linked"**
- Run `./scripts/init-app.sh` to (re)generate `app/ios` and install pods.
- Clean and retry: `cd app/ios && rm -rf build Pods Podfile.lock && pod install`.
- Splunk RUM requires iOS ≥ 15 deployment target.

**Metro can't resolve `@splunk/otel-react-native` / `@appdynamics/react-native-agent`**
- They're runtime deps of `app/package.json`; run `npm install` in `app/`.
- If you intentionally removed one, also remove its `require` in `app/src/telemetry/index.ts`.

**Type-check**
```bash
cd app && npx tsc --noEmit
```

## RUM

**No RUM data**
- `rum.provider` must be `splunk` or `appdynamics` in `app/src/config.ts`, with a non-empty
  token/appKey. The console logs `[telemetry] … initialized` on success or a warning if it
  stayed off.
- Splunk: verify realm + RUM access token. AppDynamics: run `npm run appd:instrument` and
  rebuild.
- Rebuild the app after changing `config.ts` (native init happens at launch via `index.js`).

**RUM not correlating to APM**
- The backend must be instrumented (see OBSERVABILITY.md) and reachable at the same origin the
  RUM SDK correlates with. Check that gateway traces exist for the same time window.

## Telemetry (backend)

**Custom spans/metrics missing in the backend**
- Expected until an SDK/agent is injected — the app uses the OTel **API** only. Attach
  `splunk-otel-js` or the AppDynamics Node agent out of band (OBSERVABILITY.md).
