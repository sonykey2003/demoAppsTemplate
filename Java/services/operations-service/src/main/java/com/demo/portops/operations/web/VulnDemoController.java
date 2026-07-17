package com.demo.portops.operations.web;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.sql.DataSource;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.ObjectInputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.Base64;
import java.util.Map;

/**
 * DEMO-ONLY intentionally vulnerable endpoints. Registered ONLY when
 * VULN_DEMO_MODE=enabled (set by scripts/toggle-vuln-demo.sh against the
 * operations-service:0.1.0-vuln-demo image), so the clean image never exposes a
 * sink. Each handler drives attacker-controlled input into one of the exact
 * dangerous operations a runtime application-security agent (e.g. Splunk Secure
 * Application (CSA) or Cisco Secure Application) instruments, so the agent's
 * "Attacks" view records the matching event type:
 *   - /api/debug/search      -> raw java.sql.Statement (non-parameterized) -> SQL_NONPARAM (SQLi)
 *   - /api/debug/exec        -> Runtime.exec(["/bin/echo", arg])            -> EXECUTE (RCE)
 *   - /api/debug/fetch       -> outbound HttpURLConnection to user host     -> SOCKET_RESOLVE (SSRF)
 *   - /api/debug/deserialize -> ObjectInputStream.readObject                -> DESEREAL
 * Backend-agnostic: the app only exposes the sinks; whichever runtime security
 * agent is attached out of band records the events. Paired with
 * scripts/attack-sim.sh. NOT for production use.
 *
 * The /api/debug/deserialize sink is library-agnostic: scripts/attack-sim.sh posts
 * a real commons-collections gadget (-> CVE-2015-7501) and a real commons-beanutils
 * gadget (-> CVE-2019-10086), so the Attacks view shows two distinct CVEs Reached.
 *
 * Safety: the exec sink only ever runs /bin/echo with the supplied string as a
 * single argument (cannot spawn arbitrary commands); the fetch sink only opens an
 * outbound connection and never returns the body. Both still carry request-derived
 * input into the instrumented sink, which is what the agent detects.
 */
@RestController
@RequestMapping("/api/debug")
@org.springframework.boot.autoconfigure.condition.ConditionalOnExpression(
        "'${VULN_DEMO_MODE:}' == 'enabled'")
public class VulnDemoController {

    private static final Logger log = LoggerFactory.getLogger(VulnDemoController.class);

    private final DataSource dataSource;

    public VulnDemoController(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    /** SQLi sink: vessel_code is concatenated into a raw, non-parameterized JDBC query. */
    @GetMapping("/search")
    public ResponseEntity<?> search(@RequestParam("vessel_code") String vesselCode) {
        String sql = "SELECT id, vessel_code, container_id FROM jobs "
                + "WHERE vessel_code = '" + vesselCode + "'";
        log.warn("vuln-demo: executing unsanitized query: {}", sql);
        int count = 0;
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                count++;
            }
            return ResponseEntity.ok(Map.of("count", count));
        } catch (Exception e) {
            return ResponseEntity.status(400).body(Map.of("error", e.getMessage()));
        }
    }

    /** RCE sink: request input is passed to Runtime.exec (constrained to /bin/echo). */
    @GetMapping("/exec")
    public ResponseEntity<?> exec(@RequestParam("cmd") String cmd) {
        log.warn("vuln-demo: invoking Runtime.exec with request input: {}", cmd);
        try {
            Process p = Runtime.getRuntime().exec(new String[]{"/bin/echo", cmd});
            p.waitFor();
            return ResponseEntity.ok(Map.of("status", "executed", "cmd", cmd));
        } catch (Exception e) {
            Thread.currentThread().interrupt();
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    /** SSRF sink: opens an outbound connection to a user-supplied URL. */
    @GetMapping("/fetch")
    public ResponseEntity<?> fetch(@RequestParam("url") String url) {
        log.warn("vuln-demo: opening outbound connection to user-supplied URL: {}", url);
        try {
            HttpURLConnection conn = (HttpURLConnection) URI.create(url).toURL().openConnection();
            conn.setConnectTimeout(1500);
            conn.setReadTimeout(1500);
            conn.setRequestMethod("GET");
            int code = conn.getResponseCode();
            conn.disconnect();
            return ResponseEntity.ok(Map.of("status", code));
        } catch (Exception e) {
            return ResponseEntity.status(502).body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Deserialization sink: the raw request body is fed straight to
     * ObjectInputStream.readObject(). Accepting the body as byte[] (instead of a
     * base64 String that the app decodes) is deliberate — the runtime security
     * agent taints the HTTP request body and must be able to follow that taint
     * into readObject() to record a DESEREAL attack and map "CVEs Reached".
     * Base64-decoding inside the app produces a fresh, untainted byte[] and the
     * agent never flags the deserialization. A base64 fallback is kept only so a
     * text body still works for manual testing (that path is not taint-tracked).
     */
    @PostMapping("/deserialize")
    public ResponseEntity<?> deserialize(@RequestBody byte[] body) {
        log.warn("vuln-demo: deserializing untrusted request body ({} bytes)", body.length);
        try {
            byte[] data = looksSerialized(body)
                    ? body
                    : Base64.getDecoder().decode(new String(body, java.nio.charset.StandardCharsets.US_ASCII).trim());
            try (InputStream in = new ByteArrayInputStream(data);
                 ObjectInputStream ois = new ObjectInputStream(in)) {
                Object obj = ois.readObject();
                return ResponseEntity.ok(Map.of("type", String.valueOf(obj)));
            }
        } catch (Exception e) {
            return ResponseEntity.status(400).body(Map.of("error", String.valueOf(e.getMessage())));
        }
    }

    /** Java serialization streams start with the magic bytes 0xAC 0xED. */
    private static boolean looksSerialized(byte[] b) {
        return b.length >= 2 && (b[0] & 0xFF) == 0xAC && (b[1] & 0xFF) == 0xED;
    }
}
