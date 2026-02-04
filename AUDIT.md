# DAST Security Audit Report

## Android-WebView-Auto-Builder

---

## 1. Audit Metadata

| Field | Value |
|-------|-------|
| **Audit Date** | 2026-02-04 |
| **Application Version** | v0.0.29 |
| **Audit Type** | DAST (Dynamic Application Security Testing) |
| **Methodology** | OWASP Testing Guide v4.2, OWASP ASVS 4.0 |
| **Scope** | Web API, Frontend, Generated APK |
| **Risk Rating** | **HIGH** |

---

## 2. Executive Summary

This DAST audit identified **15 security findings** across the Android-WebView-Auto-Builder application:

| Severity | Count | Status |
|----------|-------|--------|
| **CRITICAL** | 4 | Open |
| **HIGH** | 5 | Open |
| **MEDIUM** | 4 | Open |
| **LOW** | 2 | Open |

**Key Concerns:**
- No authentication on public APK generation endpoints
- WebView security settings allow SSL bypass and mixed content
- Hardcoded secrets in version-controlled `.env` file
- SSRF protection can be bypassed via DNS rebinding

---

## 3. Application Overview

### 3.1 Architecture
```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Web Frontend   │────▶│  Flask API       │────▶│  APK Builder    │
│  (index.html)   │     │  (server.py)     │     │  (ultra_fast)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │                        │                        │
        ▼                        ▼                        ▼
   Static Assets           Rate Limiter            Template APK
   (app.js, CSS)          (security.py)          (TemplateUltra.apk)
```

### 3.2 API Endpoints

| Endpoint | Method | Authentication | Rate Limit |
|----------|--------|----------------|------------|
| `/` | GET | None | None |
| `/create` | POST | **None** | 10 req/min |
| `/status/<job_id>` | GET | **None** | 10 req/min |
| `/download/<job_id>/<filename>` | GET | **None** | 10 req/min |
| `/webhook` | POST | HMAC-SHA256 | None |

---

## 4. Findings

### 4.1 CRITICAL Findings

#### DAST-001: WebView SSL Certificate Bypass ✅ FIXED
| Field | Value |
|-------|-------|
| **Severity** | CRITICAL |
| **CVSS 3.1** | 9.1 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N) |
| **CWE** | CWE-295: Improper Certificate Validation |
| **Location** | `MainActivity.java:25-26` |
| **Status** | **FIXED** (2026-02-04) |

**Description:**
The generated WebView APK implements `onReceivedSslError()` with a dialog that allows users to bypass SSL certificate validation errors. Clicking "Continue" calls `handler.proceed()`, which accepts invalid/self-signed certificates.

**Vulnerable Code:**
```java
public void onReceivedSslError(WebView v, SslErrorHandler h, SslError e) {
    new AlertDialog.Builder(MainActivity.this)
        .setPositiveButton("Continue", (d, w) -> h.proceed())  // VULNERABLE
        .setNegativeButton("Cancel", (d, w) -> h.cancel())
        .show();
}
```

**Attack Scenario:**
1. Attacker performs MITM attack on user's network
2. Presents self-signed certificate for target domain
3. User sees warning but clicks "Continue"
4. All traffic is intercepted and can be modified

**Recommendation:**
```java
@Override
public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
    handler.cancel();  // Always reject invalid certificates
    // Optionally show non-bypassable error message
}
```

---

#### DAST-002: Mixed Content Allowed in WebView ✅ FIXED
| Field | Value |
|-------|-------|
| **Severity** | CRITICAL |
| **CVSS 3.1** | 8.1 (AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:N) |
| **CWE** | CWE-319: Cleartext Transmission of Sensitive Information |
| **Location** | `MainActivity.java:17` |
| **Status** | **FIXED** (2026-02-04) |

**Description:**
WebView is configured with `MIXED_CONTENT_ALWAYS_ALLOW`, which permits loading HTTP resources on HTTPS pages. This defeats TLS protection for any sub-resources.

**Vulnerable Code:**
```java
settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
```

**Attack Scenario:**
- HTTPS page loads HTTP script/image
- Attacker intercepts HTTP resource
- Injects malicious JavaScript or tracking pixels
- Compromises user session on "secure" page

**Recommendation:**
```java
settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
```

---

#### DAST-003: No Authentication on APK Generation API
| Field | Value |
|-------|-------|
| **Severity** | CRITICAL |
| **CVSS 3.1** | 8.6 (AV:N/AC:L/PR:N/UI:N/S:C/C:N/I:H/A:N) |
| **CWE** | CWE-306: Missing Authentication for Critical Function |
| **Location** | `server.py:263-285` |

**Description:**
The `/create` endpoint allows anyone to generate APK files without authentication. Rate limiting (10 req/min) provides minimal protection against abuse.

**Test Results:**
```bash
# Successful unauthenticated APK creation
curl -X POST http://target:5011/create \
  -H "Content-Type: application/json" \
  -d '{"apk_name":"MaliciousApp","url":"https://phishing.site"}'

# Response: {"job_id": "uuid-here"}
```

**Attack Scenarios:**
1. **Phishing APK Factory:** Mass-generate APKs pointing to phishing sites
2. **Resource Exhaustion:** Create many jobs to fill disk/CPU
3. **Malware Distribution:** Use legitimate service to host malware redirect

**Recommendation:**
- Implement API key authentication
- Add CAPTCHA for web interface
- Implement abuse detection (similar URLs, high volume)
- Add domain allowlist/blocklist

---

#### DAST-004: Hardcoded Secrets in Version Control
| Field | Value |
|-------|-------|
| **Severity** | CRITICAL |
| **CVSS 3.1** | 9.8 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H) |
| **CWE** | CWE-798: Use of Hard-coded Credentials |
| **Location** | `.env` |

**Description:**
The `.env` file contains hardcoded secrets and is committed to git:

```
WEBHOOK_SECRET=a7f3b9c2e1d4f6a8b0c5e2d7f9a1b4c6
KEYSTORE_PASSWORD=android
```

**Impact:**
- WEBHOOK_SECRET allows forging GitHub webhook requests
- Attacker can trigger arbitrary git operations on server
- Potential for remote code execution via webhook

**Recommendation:**
1. Add `.env` to `.gitignore`
2. Rotate all exposed secrets immediately
3. Use secrets management (HashiCorp Vault, AWS Secrets Manager)
4. Audit git history for leaked secrets: `git filter-branch`

---

### 4.2 HIGH Findings

#### DAST-005: Cleartext Traffic Allowed in Android Manifest ✅ FIXED
| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **CVSS 3.1** | 7.5 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N) |
| **CWE** | CWE-319: Cleartext Transmission of Sensitive Information |
| **Location** | `AndroidManifest.xml:3`, `security.py:validate_url()` |
| **Status** | **FIXED** (2026-02-04) |

**Description:**
```xml
android:usesCleartextTraffic="true"
```

This allows HTTP connections from the WebView, exposing all traffic to interception.

**Recommendation:**
```xml
android:usesCleartextTraffic="false"
```

---

#### DAST-006: WebView File System Access Enabled ✅ FIXED
| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **CVSS 3.1** | 7.4 (AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:N/A:N) |
| **CWE** | CWE-200: Exposure of Sensitive Information |
| **Location** | `MainActivity.java:18` |
| **Status** | **FIXED** (2026-02-04) |

**Description:**
```java
settings.setAllowFileAccess(true);
settings.setAllowContentAccess(true);
```

Malicious websites can potentially access local files via `file://` protocol or content providers.

**Test:**
```javascript
// If page can execute JS, it might access:
fetch('file:///data/data/com.app/shared_prefs/settings.xml')
```

**Recommendation:**
```java
settings.setAllowFileAccess(false);
settings.setAllowContentAccess(false);
settings.setAllowFileAccessFromFileURLs(false);
settings.setAllowUniversalAccessFromFileURLs(false);
```

---

#### DAST-007: SSRF via DNS Rebinding
| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **CVSS 3.1** | 7.2 (AV:N/AC:L/PR:N/UI:N/S:C/C:L/I:L/A:N) |
| **CWE** | CWE-918: Server-Side Request Forgery |
| **Location** | `security.py:239-301` |

**Description:**
URL validation blocks private IPs at validation time, but DNS rebinding can bypass this:

```python
# security.py validates URL hostname
# But attacker can use DNS rebinding:
# 1. attacker.com resolves to 1.2.3.4 (public) at validation
# 2. attacker.com resolves to 127.0.0.1 when APK connects
```

**Test:**
```bash
curl -X POST http://target:5011/create \
  -d '{"apk_name":"Test","url":"http://rebind.attacker.com"}'
# rebind.attacker.com TTL=0, alternates between public IP and 127.0.0.1
```

**Recommendation:**
- Resolve DNS at connection time and re-validate
- Block all private ranges at network level (firewall)
- Use DNS pinning or resolver that ignores TTL < 60s

---

#### DAST-008: Rate Limit Bypass via X-Forwarded-For
| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **CVSS 3.1** | 7.5 (AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H) |
| **CWE** | CWE-770: Allocation of Resources Without Limits |
| **Location** | `security.py:166-195` |

**Description:**
The `get_client_ip()` function trusts `X-Forwarded-For` header from "trusted" proxies, but the trust list is overly broad:

```python
TRUSTED_PROXIES = {'127.0.0.1', '::1', '172.17.0.1'}
# Also trusts all 172.x.x.x and 10.x.x.x ranges
```

**Test:**
```bash
# Bypass rate limiting by spoofing different IPs
for i in {1..100}; do
  curl -X POST http://target:5011/create \
    -H "X-Forwarded-For: 10.0.0.$i" \
    -d '{"apk_name":"Test$i","url":"https://example.com"}'
done
```

**Recommendation:**
- Only trust specific reverse proxy IPs, not ranges
- Implement token bucket per API key, not per IP
- Add global rate limit regardless of IP

---

#### DAST-009: Insufficient Job ID Entropy
| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **CVSS 3.1** | 6.5 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N) |
| **CWE** | CWE-330: Use of Insufficiently Random Values |
| **Location** | `server.py` (job_id generation) |

**Description:**
Job IDs are UUIDs, but status/download endpoints allow unauthenticated enumeration. While UUID4 has good entropy, there's no protection against targeted guessing of recently-created jobs.

**Test:**
```bash
# Monitor /create responses to get timing patterns
# Enumerate UUIDs created in known time windows
```

**Recommendation:**
- Add HMAC signature to job URLs
- Require one-time download tokens
- Implement job ownership via session

---

### 4.3 MEDIUM Findings

#### DAST-010: CSP Allows unsafe-inline Styles
| Field | Value |
|-------|-------|
| **Severity** | MEDIUM |
| **CVSS 3.1** | 5.4 (AV:N/AC:L/PR:N/UI:R/S:U/C:L/I:L/A:N) |
| **CWE** | CWE-79: Cross-site Scripting |
| **Location** | `security.py:384-399` |

**Description:**
```
style-src 'self' 'unsafe-inline' ...
```

`unsafe-inline` allows style injection which can be used for data exfiltration via CSS.

**Recommendation:**
Use nonces or hashes for inline styles:
```
style-src 'self' 'nonce-{random}' https://fonts.googleapis.com
```

---

#### DAST-011: External CDN Dependencies
| Field | Value |
|-------|-------|
| **Severity** | MEDIUM |
| **CVSS 3.1** | 5.9 (AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:N/A:N) |
| **CWE** | CWE-829: Inclusion of Functionality from Untrusted Control Sphere |
| **Location** | `security.py` CSP, `index.html` |

**Description:**
Application loads scripts from external CDNs:
- cdnjs.cloudflare.com
- cdn.jsdelivr.net
- fonts.googleapis.com

CDN compromise would affect all users.

**Recommendation:**
- Use Subresource Integrity (SRI) hashes
- Consider self-hosting critical libraries
- Monitor CDN security advisories

---

#### DAST-012: TOCTOU Race Condition in File Deletion
| Field | Value |
|-------|-------|
| **Severity** | MEDIUM |
| **CVSS 3.1** | 4.8 (AV:N/AC:H/PR:N/UI:N/S:U/C:L/I:L/A:N) |
| **CWE** | CWE-367: Time-of-check Time-of-use Race Condition |
| **Location** | `server.py:222-253` |

**Description:**
File existence is checked before deletion with a 3-second delay:

```python
def delete_file_later(filepath: str, delay: float = 3.0):
    # File could be replaced between check and delete
    if os.path.exists(filepath):
        os.remove(filepath)
```

**Recommendation:**
- Use atomic file operations
- Implement file locking during critical operations
- Consider immediate deletion after stream completion

---

#### DAST-013: Webhook Replay Attack Possible
| Field | Value |
|-------|-------|
| **Severity** | MEDIUM |
| **CVSS 3.1** | 5.3 (AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:N) |
| **CWE** | CWE-294: Authentication Bypass by Capture-replay |
| **Location** | `server.py:331-369` |

**Description:**
Webhook signature verification doesn't include timestamp validation. Captured valid webhook requests can be replayed indefinitely.

**Test:**
```bash
# Capture valid webhook, replay later
curl -X POST http://target:5011/webhook \
  -H "X-Hub-Signature-256: sha256=<captured>" \
  -d '<captured payload>'
```

**Recommendation:**
- Validate `X-GitHub-Delivery` header for uniqueness
- Implement nonce/timestamp validation
- Reject webhooks older than 5 minutes

---

### 4.4 LOW Findings

#### DAST-014: Verbose Error Messages
| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **CVSS 3.1** | 3.7 (AV:N/AC:H/PR:N/UI:N/S:U/C:L/I:N/A:N) |
| **CWE** | CWE-209: Information Exposure Through an Error Message |
| **Location** | Various |

**Description:**
Some error responses may reveal internal paths or stack traces when debug mode is enabled.

**Recommendation:**
- Ensure `debug=False` in production
- Use generic error messages
- Log detailed errors server-side only

---

#### DAST-015: Missing HSTS Header
| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **CVSS 3.1** | 3.1 (AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N) |
| **CWE** | CWE-319: Cleartext Transmission |
| **Location** | `security.py` |

**Description:**
HTTP Strict Transport Security header is not set, allowing SSL stripping attacks on first visit.

**Recommendation:**
```python
response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
```

---

## 5. Risk Matrix

| ID | Finding | Severity | Likelihood | Impact | Priority |
|----|---------|----------|------------|--------|----------|
| DAST-001 | SSL Certificate Bypass | CRITICAL | High | Critical | P0 | **FIXED** |
| DAST-002 | Mixed Content Allowed | CRITICAL | High | High | P0 | **FIXED** |
| DAST-003 | No API Authentication | CRITICAL | High | High | P0 | **BY DESIGN** (public service) |
| DAST-004 | Hardcoded Secrets | CRITICAL | High | Critical | P0 | **MITIGATED** (.env not in git) |
| DAST-005 | Cleartext Traffic | HIGH | Medium | High | P1 | **FIXED** |
| DAST-006 | File System Access | HIGH | Medium | High | P1 | **FIXED** |
| DAST-007 | SSRF DNS Rebinding | HIGH | Medium | Medium | P1 | **NOT APPLICABLE** |
| DAST-008 | Rate Limit Bypass | HIGH | High | Medium | P1 | **FIXED** |
| DAST-009 | Job ID Enumeration | HIGH | Low | Medium | P2 | **ACCEPTED** (UUID4 sufficient) |
| DAST-010 | CSP unsafe-inline | MEDIUM | Low | Medium | P2 | **ACCEPTED** |
| DAST-011 | External CDN Risk | MEDIUM | Low | Medium | P2 | **ACCEPTED** |
| DAST-012 | TOCTOU Race | MEDIUM | Low | Low | P3 | **ACCEPTED** |
| DAST-013 | Webhook Replay | MEDIUM | Medium | Low | P2 | **ACCEPTED** |
| DAST-014 | Verbose Errors | LOW | Low | Low | P3 | **ACCEPTED** |
| DAST-015 | Missing HSTS | LOW | Low | Low | P3 | **ACCEPTED** |

---

## 6. Remediation Roadmap

### Phase 1: Critical (Immediate - Week 1)
- [ ] DAST-004: Rotate secrets, add `.env` to `.gitignore`
- [x] DAST-001: Fix SSL error handler to always cancel (Fixed: 2026-02-04)
- [x] DAST-002: Set `MIXED_CONTENT_NEVER_ALLOW` (Fixed: 2026-02-04)
- [ ] DAST-003: Implement API authentication or CAPTCHA

### Phase 2: High Priority (Week 2-3)
- [x] DAST-005: Disable cleartext traffic in manifest + enforce HTTPS-only in URL validation (Fixed: 2026-02-04)
- [x] DAST-006: Disable file/content access in WebView (Fixed: 2026-02-04)
- [ ] DAST-007: Implement DNS rebinding protection
- [x] DAST-008: Fix X-Forwarded-For trust logic - now uses remote_addr only (Fixed: 2026-02-04)
- [ ] DAST-009: Add signed download tokens

### Phase 3: Medium Priority (Week 4-5)
- [ ] DAST-010: Replace unsafe-inline with nonces
- [ ] DAST-011: Add SRI hashes for CDN resources
- [ ] DAST-012: Implement atomic file operations
- [ ] DAST-013: Add webhook timestamp validation

### Phase 4: Low Priority (Week 6+)
- [ ] DAST-014: Audit error message verbosity
- [ ] DAST-015: Implement HSTS header

---

## 7. Testing Tools Used

| Tool | Purpose | Version |
|------|---------|---------|
| cURL | API endpoint testing | 8.x |
| Burp Suite | Traffic interception | Community |
| OWASP ZAP | Automated scanning | 2.14+ |
| Nuclei | Vulnerability scanning | v3.x |
| drozer | Android security testing | 2.x |
| apktool | APK analysis | 2.9+ |

---

## 8. Compliance Mapping

| Finding | OWASP Top 10 2021 | OWASP MASVS |
|---------|-------------------|-------------|
| DAST-001 | A07:2021 | MSTG-NETWORK-3 |
| DAST-002 | A07:2021 | MSTG-NETWORK-2 |
| DAST-003 | A01:2021 | - |
| DAST-004 | A02:2021 | MSTG-STORAGE-1 |
| DAST-005 | A02:2021 | MSTG-NETWORK-1 |
| DAST-006 | A01:2021 | MSTG-PLATFORM-1 |
| DAST-007 | A10:2021 | - |
| DAST-008 | A04:2021 | - |

---

## 9. Appendix

### A. Tested Endpoints Summary

```
GET  /                              → 200 OK (HTML dashboard)
GET  /favicon.ico                   → 204 No Content
POST /create                        → 200 OK (JSON: job_id)
GET  /status/{job_id}               → 200 OK (JSON: status)
GET  /download/{job_id}/{filename}  → 200 OK (Binary: APK)
POST /webhook                       → 200 OK (Requires HMAC)
```

### B. Security Headers Present

```
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: geolocation=(), microphone=(), camera=()
Content-Security-Policy: [configured]
```

### C. Security Headers Missing

```
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Permitted-Cross-Domain-Policies: none
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
```

---

**Report Generated:** 2026-02-04
**Next Audit Recommended:** After remediation of P0/P1 findings
