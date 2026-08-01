# Sandbox (local only)

This directory is for machine-specific configuration and functional tests. Everything here except the committed example files is **gitignored**.

## Workspace import

1. Copy `workspaces.example.json` → `workspaces.local.json`
2. Replace placeholder hosts with your lab camera IPs and jump hosts
3. Run `./import-workspaces.sh` to load into the app's Application Support directory

Never commit `workspaces.local.json` — it may contain internal network addresses.

## Functional tests (backburner)

Future UI and integration tests that require real camera IPs or VPN access can live here:

```
sandbox/
  tests/                  Test plans and scripts (optional)
  workspaces.local.json   Your lab workspace definitions
  credentials.local.json  Never commit — session test data only
```

See `.agents/app-testing/SKILL.md` for manual functional test descriptions.
