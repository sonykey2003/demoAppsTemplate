#!/usr/bin/env bash
# scripts/init-android.sh — One-time bootstrap of the React Native app's NATIVE
# Android project. The JS/TS sources in app/ are complete and committed; the native
# android/ shell is generated here (it can't be meaningfully hand-authored/committed).
#
# What it does:
#   1. Installs the app's npm dependencies.
#   2. Generates the native Android project for the pinned RN version and copies it
#      into app/android (skipped if it already exists).
#   3. Applies the Android tweaks this demo needs:
#        - Core-library desugaring (required by the Splunk RUM Android SDK).
#        - Cleartext HTTP for the emulator host (so http://10.0.2.2:8080 works).
#        - ACCESS_NETWORK_STATE permission (used by the AppDynamics agent).
#   4. If RUM_PROVIDER=appdynamics, runs the AppDynamics build-time instrumentation CLI.
#
# Usage: ./scripts/init-android.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${ROOT}/app"
APP_NAME="SeaBankDemo"
RN_VERSION="0.77.3"

echo "==> [1/4] Installing app dependencies"
(cd "${APP_DIR}" && npm install)

if [[ -d "${APP_DIR}/android" ]]; then
  echo "==> [2/4] app/android already exists — skipping native project generation"
else
  echo "==> [2/4] Generating native Android project (RN ${RN_VERSION})"
  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP}"' EXIT
  npx --yes @react-native-community/cli@latest init "${APP_NAME}" \
    --version "${RN_VERSION}" --directory "${TMP}/${APP_NAME}" --skip-install --pm npm
  cp -R "${TMP}/${APP_NAME}/android" "${APP_DIR}/android"
  echo "    Copied android/ into app/"
fi

echo "==> [3/4] Applying Android tweaks"
BG="${APP_DIR}/android/app/build.gradle"
MAN="${APP_DIR}/android/app/src/main/AndroidManifest.xml"

# 3a. Core-library desugaring — appended as merged android{}/dependencies{} blocks
#     (Gradle merges repeated blocks, so this is safe and avoids fragile in-place edits).
if [[ -f "${BG}" ]] && ! grep -q 'sea-bank: core library desugaring' "${BG}"; then
  cat >> "${BG}" <<'GRADLE'

// sea-bank: core library desugaring (required by @splunk/otel-react-native on Android)
android {
    compileOptions {
        coreLibraryDesugaringEnabled true
    }
}
dependencies {
    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.5"
}
GRADLE
  echo "    ✓ build.gradle: core-library desugaring enabled"
else
  echo "    • build.gradle: desugaring already present or file missing"
fi

# 3b. Cleartext HTTP (demo only) so the emulator can reach http://10.0.2.2:8080.
if [[ -f "${MAN}" ]] && ! grep -q 'usesCleartextTraffic' "${MAN}"; then
  perl -0pi -e 's/(<application\b)/$1 android:usesCleartextTraffic="true"/' "${MAN}"
  echo "    ✓ AndroidManifest.xml: usesCleartextTraffic=true"
else
  echo "    • AndroidManifest.xml: cleartext already set or file missing"
fi

# 3c. ACCESS_NETWORK_STATE (used by the AppDynamics agent).
if [[ -f "${MAN}" ]] && ! grep -q 'ACCESS_NETWORK_STATE' "${MAN}"; then
  perl -0pi -e 's/(<manifest\b[^>]*>)/$1\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" \/>/' "${MAN}"
  echo "    ✓ AndroidManifest.xml: ACCESS_NETWORK_STATE permission added"
else
  echo "    • AndroidManifest.xml: permission already present or file missing"
fi

# 3d. Disable New Architecture — the Splunk RUM Android network (HTTP) instrumentation
#     does not attach under bridgeless/New Arch, so no HTTP spans / APM correlation.
GP="${APP_DIR}/android/gradle.properties"
if [[ -f "${GP}" ]] && grep -q 'newArchEnabled=true' "${GP}"; then
  perl -0pi -e 's/newArchEnabled=true/newArchEnabled=false/' "${GP}"
  echo "    ✓ gradle.properties: newArchEnabled=false (for Android HTTP instrumentation)"
else
  echo "    • gradle.properties: newArchEnabled already false or file missing"
fi

# 3e. Splunk OkHttp3 auto network instrumentation (byte-buddy weaving) so RN's fetch
#     produces HTTP client spans + APM correlation on Android (parity with iOS).
GS="${APP_DIR}/android/settings.gradle"
APPBG="${APP_DIR}/android/app/build.gradle"
if [[ -f "${GS}" ]] && ! grep -q 'splunk-rum-android-releases' "${GS}"; then
  perl -0pi -e 's!pluginManagement \{ includeBuild\("\.\./node_modules/\@react-native/gradle-plugin"\) \}!pluginManagement {\n  includeBuild("../node_modules/\@react-native/gradle-plugin")\n  repositories {\n    gradlePluginPortal()\n    google()\n    mavenCentral()\n    maven { url "https://splunk.jfrog.io/splunk/splunk-rum-android-releases" }\n  }\n}!' "${GS}"
  echo "    ✓ settings.gradle: Splunk jFrog pluginManagement repo"
else
  echo "    • settings.gradle: Splunk repo already present or file missing"
fi
if [[ -f "${APPBG}" ]] && ! grep -q 'rum-okhttp3-auto-plugin' "${APPBG}"; then
  perl -0pi -e 's!apply plugin: "com\.android\.application"!plugins {\n    id "net.bytebuddy.byte-buddy-gradle-plugin" version "1.18.8" apply false\n    id "com.splunk.rum-okhttp3-auto-plugin" version "2.3.2" apply false\n}\n\napply plugin: "com.android.application"!' "${APPBG}"
  perl -0pi -e 's!apply plugin: "com\.facebook\.react"!apply plugin: "com.facebook.react"\napply plugin: "net.bytebuddy.byte-buddy-gradle-plugin"\napply plugin: "com.splunk.rum-okhttp3-auto-plugin"!' "${APPBG}"
  echo "    ✓ app/build.gradle: byte-buddy + Splunk okhttp3 auto plugins"
else
  echo "    • app/build.gradle: Splunk okhttp3 plugin already present or file missing"
fi

if [[ "${RUM_PROVIDER:-}" == "appdynamics" ]]; then
  echo "==> [4/4] Applying AppDynamics build-time instrumentation"
  (cd "${APP_DIR}" && npm run appd:instrument)
else
  echo "==> [4/4] Skipping AppDynamics build-time step (set RUM_PROVIDER=appdynamics to enable)"
fi

cat <<EOF

✓ Android bootstrap complete.

Next:
  1. Backend must be running (in native_iOS): ./scripts/deploy.sh && ./scripts/port-forward-gateway.sh
     The app already targets http://10.0.2.2:8080 on Android (the emulator's host alias).
  2. (Optional) RUM: put your token in native_android/app/.env (SPLUNK_RUM_ACCESS_TOKEN=...).
  3. Run on an emulator/device:
       cd app && npm run android
     If you changed .env/babel, restart Metro with a clean cache:
       npm start -- --reset-cache
EOF
