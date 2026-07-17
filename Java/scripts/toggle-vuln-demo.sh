#!/usr/bin/env bash
# Switch operations-service between clean and demo-vulnerable images.
set -euo pipefail

NAMESPACE="${NAMESPACE:-port-ops-demo}"
DEPLOYMENT="${DEPLOYMENT:-operations-service}"
CONTAINER="${CONTAINER:-operations-service}"
IMAGE_PREFIX="${IMAGE_PREFIX:-localhost/port-ops-demo}"
VERSION="${VERSION:-0.1.0}"
CLEAN_IMAGE="${IMAGE_PREFIX}/operations-service:${VERSION}"
VULN_IMAGE="${IMAGE_PREFIX}/operations-service:${VERSION}-vuln-demo"

usage() {
  cat <<EOF
Usage: $(basename "$0") on|off|status

Commands:
  on      Deploy the demo-vulnerable operations-service image
  off     Deploy the clean operations-service image
  status  Show the current operations-service image and demo env marker

Environment overrides:
  NAMESPACE=${NAMESPACE}
  IMAGE_PREFIX=${IMAGE_PREFIX}
  VERSION=${VERSION}
EOF
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

case "$1" in
  on)
    kubectl -n "${NAMESPACE}" set image "deployment/${DEPLOYMENT}" "${CONTAINER}=${VULN_IMAGE}"
    # VULN_DEMO_MODE enables the vulnerable libraries + sink endpoints.
    # JDK_JAVA_OPTIONS adds the runtime-security JVM flag that turns on attack-event
    # collection so a Secure Application agent (e.g. Splunk CSA) populates the Attacks
    # page. NOTE: the property is argento.allow.security.events (PLURAL) per the agent's
    # bundled otel-extension-system.properties; the singular spelling seen in some docs
    # is a typo and is silently ignored. It has no env-var equivalent, so it must be a -D
    # system property; JDK_JAVA_OPTIONS is appended by the java launcher without
    # clobbering an operator-injected JAVA_TOOL_OPTIONS (-javaagent).
    # jdk.xml.enableTemplatesImplDeserialization re-enables JAXP TemplatesImpl
    # deserialization (hardened off by default in current JDKs) and the --add-opens
    # opens the internal Xalan package so the demo's commons-beanutils CommonsBeanutils1
    # gadget can reach the vulnerable code path; the Attacks view then populates CVEs
    # Reached with CVE-2019-10086. Both are deliberate demo-only weakenings of JDK
    # hardening.
    kubectl -n "${NAMESPACE}" set env "deployment/${DEPLOYMENT}" \
      VULN_DEMO_MODE=enabled \
      JDK_JAVA_OPTIONS="-Dargento.allow.security.events=true -Djdk.xml.enableTemplatesImplDeserialization=true --add-opens=java.xml/com.sun.org.apache.xalan.internal.xsltc.trax=ALL-UNNAMED"
    kubectl -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}"
    ;;
  off)
    kubectl -n "${NAMESPACE}" set image "deployment/${DEPLOYMENT}" "${CONTAINER}=${CLEAN_IMAGE}"
    kubectl -n "${NAMESPACE}" set env "deployment/${DEPLOYMENT}" VULN_DEMO_MODE- JDK_JAVA_OPTIONS-
    kubectl -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}"
    ;;
  status)
    kubectl -n "${NAMESPACE}" get "deployment/${DEPLOYMENT}" \
      -o jsonpath='{.spec.template.spec.containers[?(@.name=="operations-service")].image}{"\n"}{.spec.template.spec.containers[?(@.name=="operations-service")].env[?(@.name=="VULN_DEMO_MODE")].value}{"\n"}'
    ;;
  --help|-h)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
