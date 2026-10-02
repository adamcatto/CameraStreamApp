import { readFile } from "node:fs/promises";
import { join } from "node:path";

export interface BundledProfile {
  workspaces: unknown[];
  credentials: Record<string, string>;
}

// Private lab packages place profiles-workspaces.json and profiles-credentials.json
// (the same files the native clients bundle) in this directory. Standard builds have
// none, so the endpoint reports that no profile exists.
export function profileDirectory(appRoot: string): string {
  return process.env.CAMERA_STREAM_PROFILE_DIR || join(appRoot, "profile");
}

export async function loadBundledProfile(directory: string): Promise<BundledProfile | null> {
  const workspaces = await readJsonFile(join(directory, "profiles-workspaces.json"));
  const credentials = await readJsonFile(join(directory, "profiles-credentials.json"));
  if (workspaces === undefined && credentials === undefined) return null;
  return {
    workspaces: Array.isArray(workspaces) ? workspaces : [],
    credentials: sanitizeCredentials(credentials),
  };
}

export function sanitizeCredentials(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const credentials: Record<string, string> = {};
  for (const [account, password] of Object.entries(value)) {
    if (account.trim() && typeof password === "string" && password) credentials[account.trim()] = password;
  }
  return credentials;
}

async function readJsonFile(path: string): Promise<unknown> {
  let text: string;
  try {
    text = await readFile(path, "utf8");
  } catch {
    return undefined;
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Error("The bundled profile is not valid JSON.");
  }
}
