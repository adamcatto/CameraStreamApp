---
name: security-review
description: >-
  Security review checklist for Camera Stream: credentials, SSH, shell injection,
  logging, and repo hygiene. Use before committing, publishing the repo, or
  shipping a DMG.
---

# Security review

## Credential handling

- [ ] No hardcoded passwords, API keys, or private keys anywhere in repo or DMG
- [ ] `CredentialStore` is memory-only; cleared on quit
- [ ] `SessionCredentials` files are mode 0600 and deleted after use
- [ ] Settings UI uses `SecureField` for passwords
- [ ] `CameraSSHAskpass` reads only from env-specified credential file

## SSH

- [ ] Uses `/usr/bin/ssh` with `-F /dev/null`
- [ ] `ControlMaster=no` / `ControlPersist=no`
- [ ] `StrictHostKeyChecking=accept-new` (document MITM tradeoff for lab use)
- [ ] Remote commands are fixed templates; no user-controlled shell on Mac side

## Shell injection

- [ ] `ClusterShell` validates username/host charset before `osascript`
- [ ] Arguments shell-escaped with single-quote wrapping
- [ ] No user string passed unescaped to `do script`

## Logging

- [ ] `streaming.log` contains SSH stderr only
- [ ] Grep platform sources for credential literals; UI labels/bindings are expected

## Repo hygiene

- [ ] No internal lab IPs in `apps/*/Sources`, `apps/web/src`, or `apps/web/server` (use `config/sandbox/workspaces.local.json`)
- [ ] `.gitignore` covers local files under `config/sandbox`, `dist/`, build outputs, keys, and `.env`
- [ ] Run `./apps/macos/scripts/smoke-test.sh` secret scan on bundle

## DMG / bundle

- [ ] Only expected binaries in `Contents/MacOS` and `Resources/bin`
- [ ] csshX is vendored with license file
- [ ] Unsigned builds documented; recommend signing for external distribution

## Scan commands

```sh
# Secrets in source
grep -rEn 'BEGIN (RSA|OPENSSH)|api[_-]?key|secret|token|password\s*=\s*"[^"]+"' apps/macos/Sources apps/macos/Vendor apps/windows apps/web/src apps/web/server || true

# Internal IPs in source (should be none)
grep -rE '10\.(81|1)\.' apps/macos/Sources apps/windows apps/web/src apps/web/server || true

# Bundle scan
./apps/macos/scripts/smoke-test.sh
```
