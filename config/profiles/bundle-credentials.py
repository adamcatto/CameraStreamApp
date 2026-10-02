#!/usr/bin/env python3
"""Convert a private credentials file into the account map the apps bundle.

Usage: bundle-credentials.py WORKSPACES_JSON CREDENTIALS_JSON OUTPUT_JSON

The credentials file may be a list of {workspaceName, cameraPassword, jumpPassword},
an object {"workspaces": {name: {cameraPassword, jumpPassword}}}, or a direct
{"user@host": "password"} account map. The output is always an account map that
contains only the accounts the given workspaces use.
"""
import json
import os
import sys


def workspace_accounts(workspace):
    accounts = []
    for camera in workspace.get("cameras", []):
        host = camera.get("host", "")
        if host:
            accounts.append(f"{camera.get('username') or 'pi'}@{host}")
    return accounts


def main(workspaces_path, credentials_path, output_path):
    workspaces = json.load(open(workspaces_path))
    raw = json.load(open(credentials_path))
    by_name = {}
    if isinstance(raw, list):
        for entry in raw:
            by_name[entry["workspaceName"]] = entry
    elif isinstance(raw, dict) and "workspaces" in raw:
        for name, entry in raw["workspaces"].items():
            by_name[name] = {"workspaceName": name, **entry}
    elif isinstance(raw, dict):
        by_name = None
    else:
        raise SystemExit("Credentials file must be a JSON array or object.")

    account_credentials = {}
    if by_name is None:
        missing = []
        for workspace in workspaces:
            accounts = workspace_accounts(workspace) + ([workspace["jumpHost"]] if workspace.get("jumpHost") else [])
            for account in accounts:
                password = str(raw.get(account, "")).strip()
                if password:
                    account_credentials[account] = password
                elif account not in missing:
                    missing.append(account)
        if missing:
            raise SystemExit("Account credentials file has missing passwords for: " + ", ".join(missing))
    else:
        for workspace in workspaces:
            name = workspace["name"]
            entry = by_name.get(name)
            if not entry:
                raise SystemExit(f"Missing credentials entry for workspace: {name}")
            camera_password = str(entry.get("cameraPassword", "")).strip()
            if not camera_password:
                raise SystemExit(f"Missing cameraPassword for workspace: {name}")
            for account in workspace_accounts(workspace):
                account_credentials[account] = camera_password
            jump_host = workspace.get("jumpHost")
            if jump_host:
                jump_password = str(entry.get("jumpPassword", "")).strip()
                if not jump_password:
                    raise SystemExit(f"Missing jumpPassword for workspace: {name}")
                account_credentials[jump_host] = jump_password

    if not account_credentials:
        raise SystemExit("No account credentials were generated.")
    descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as output:
        json.dump(account_credentials, output, indent=2)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
