import type { CameraWorkspace } from "./models";

export type CredentialFileFormat = "json" | "yaml" | "csv" | "tsv" | "xlsx";

export interface CredentialImportResult {
  credentials: Record<string, string>;
  importedAccounts: string[];
  unmatchedEntries: string[];
  processedRows: number;
}

interface ImportState {
  credentials: Record<string, string>;
  imported: Set<string>;
  unmatched: Set<string>;
  processedRows: number;
  accounts: Map<string, string>;
  workspaces: Map<string, CameraWorkspace>;
}

type GenericRecord = Record<string, unknown>;

export async function importCredentialFile(file: File, workspaces: CameraWorkspace[]): Promise<CredentialImportResult> {
  if (file.size > 10_000_000) throw new Error("Credential file is larger than the 10 MB limit.");
  const format = formatFromFilename(file.name);
  if (format === "xlsx") {
    const { default: readXlsxFile } = await import("read-excel-file/browser");
    const sheets = await readXlsxFile(file);
    const records = sheets.flatMap((sheet) => tableToRecords(sheet.data));
    return importCredentialDocument(records, workspaces);
  }
  return importCredentialText(await file.text(), format, workspaces);
}

export async function importCredentialText(
  text: string,
  format: Exclude<CredentialFileFormat, "xlsx">,
  workspaces: CameraWorkspace[],
): Promise<CredentialImportResult> {
  let document: unknown;
  if (format === "json") document = JSON.parse(text);
  else if (format === "yaml") {
    const { parse: parseYaml } = await import("yaml");
    document = parseYaml(text);
  }
  else document = tableToRecords(parseDelimited(text, format === "tsv" ? "\t" : ","));
  return importCredentialDocument(document, workspaces);
}

export function importCredentialDocument(document: unknown, workspaces: CameraWorkspace[]): CredentialImportResult {
  const accounts = new Map<string, string>();
  for (const workspace of workspaces) {
    for (const camera of workspace.cameras) {
      const account = `${camera.username}@${camera.host}`;
      accounts.set(normalizeLookup(account), account);
    }
    if (workspace.jumpHost) accounts.set(normalizeLookup(workspace.jumpHost), workspace.jumpHost);
  }

  const state: ImportState = {
    credentials: {},
    imported: new Set(),
    unmatched: new Set(),
    processedRows: 0,
    accounts,
    workspaces: new Map(workspaces.map((workspace) => [normalizeLookup(workspace.name), workspace])),
  };
  consumeDocument(document, state);
  return {
    credentials: state.credentials,
    importedAccounts: [...state.imported],
    unmatchedEntries: [...state.unmatched],
    processedRows: state.processedRows,
  };
}

export function formatFromFilename(filename: string): CredentialFileFormat {
  const extension = filename.toLowerCase().split(".").pop();
  if (extension === "json") return "json";
  if (extension === "yaml" || extension === "yml") return "yaml";
  if (extension === "csv") return "csv";
  if (extension === "tsv") return "tsv";
  if (extension === "xlsx") return "xlsx";
  throw new Error("Unsupported credential file. Use JSON, YAML, CSV, TSV, or XLSX.");
}

function consumeDocument(value: unknown, state: ImportState, suggestedWorkspace?: string): void {
  if (Array.isArray(value)) {
    for (const row of value) consumeRow(row, state, suggestedWorkspace);
    return;
  }
  if (!isRecord(value)) throw new Error("Credential file must contain an object, mapping, or table of rows.");

  const normalized = normalizedRecord(value);
  const credentialsContainer = normalized.credentials ?? normalized.accounts;
  if (credentialsContainer && credentialsContainer !== value) consumeDocument(credentialsContainer, state, suggestedWorkspace);

  const workspaceContainer = normalized.workspaces;
  if (workspaceContainer) {
    if (Array.isArray(workspaceContainer)) {
      for (const row of workspaceContainer) consumeRow(row, state);
    } else if (isRecord(workspaceContainer)) {
      for (const [workspaceName, entry] of Object.entries(workspaceContainer)) consumeDocument(entry, state, workspaceName);
    }
  }

  const entries = Object.entries(value);
  const accountMap = entries.filter(([key, entry]) => key.includes("@") && isPasswordValue(entry));
  if (accountMap.length) {
    for (const [account, password] of accountMap) assignAccount(account, password, state);
    state.processedRows += accountMap.length;
  }

  if (!credentialsContainer && !workspaceContainer && !accountMap.length) {
    const workspaceMappings = entries.filter(([key, entry]) => state.workspaces.has(normalizeLookup(key)) && isRecord(entry));
    if (workspaceMappings.length) {
      for (const [workspaceName, entry] of workspaceMappings) consumeRow(entry, state, workspaceName);
    } else {
      consumeRow(value, state, suggestedWorkspace);
    }
  } else if (suggestedWorkspace && !accountMap.length) {
    consumeRow(value, state, suggestedWorkspace);
  }
}

function consumeRow(value: unknown, state: ImportState, suggestedWorkspace?: string): void {
  if (!isRecord(value)) {
    if (value !== null && value !== undefined && String(value).trim()) state.unmatched.add("Unrecognized scalar entry");
    return;
  }
  state.processedRows += 1;
  const row = normalizedRecord(value);
  const workspaceName = stringValue(row.workspacename ?? row.workspace ?? row.cluster) || suggestedWorkspace;
  const account = stringValue(row.account ?? row.sshaccount ?? row.credentialaccount);
  const host = stringValue(row.host ?? row.hostname ?? row.ip ?? row.ipaddress);
  const username = stringValue(row.username ?? row.user);
  const password = passwordValue(row.password ?? row.pass ?? row.sshpassword);
  const cameraPassword = passwordValue(row.camerapassword ?? row.sharedcamerapassword);
  const jumpPassword = passwordValue(row.jumppassword ?? row.jumphostpassword);
  const cameraName = stringValue(row.cameraname ?? row.camera);
  const type = normalizeKey(stringValue(row.type ?? row.kind ?? row.role) ?? "");

  let assigned = false;
  if (account && password !== null) assigned = assignAccount(account, password, state) || assigned;
  else if (host && username && password !== null) assigned = assignAccount(`${username}@${host}`, password, state) || assigned;

  if (workspaceName) {
    const workspace = state.workspaces.get(normalizeLookup(workspaceName));
    if (!workspace) {
      state.unmatched.add(`Workspace not found: ${workspaceName}`);
      return;
    }

    if (cameraName && password !== null) {
      const camera = workspace.cameras.find((entry) => normalizeLookup(entry.name) === normalizeLookup(cameraName));
      if (camera) assigned = assignAccount(`${camera.username}@${camera.host}`, password, state) || assigned;
      else state.unmatched.add(`Camera not found in ${workspace.name}: ${cameraName}`);
    }

    const sharedCameraPassword = cameraPassword ?? (password !== null && type !== "jump" && !account && !host ? password : null);
    if (sharedCameraPassword !== null) {
      for (const camera of workspace.cameras) {
        assigned = assignAccount(`${camera.username}@${camera.host}`, sharedCameraPassword, state) || assigned;
      }
    }

    const sharedJumpPassword = jumpPassword ?? (password !== null && type === "jump" ? password : null);
    if (sharedJumpPassword !== null) {
      if (workspace.jumpHost) assigned = assignAccount(workspace.jumpHost, sharedJumpPassword, state) || assigned;
      else state.unmatched.add(`Workspace has no jump host: ${workspace.name}`);
    }
  }

  if (!assigned && !workspaceName && !account && !(host && username)) state.unmatched.add("Row has no account or workspace name");
}

function assignAccount(requestedAccount: string, rawPassword: unknown, state: ImportState): boolean {
  const password = passwordValue(rawPassword);
  if (password === null) return false;
  const account = state.accounts.get(normalizeLookup(requestedAccount));
  if (!account) {
    state.unmatched.add(`Account not found: ${requestedAccount}`);
    return false;
  }
  state.credentials[account] = password;
  state.imported.add(account);
  return true;
}

function parseDelimited(text: string, delimiter: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index]!;
    if (quoted) {
      if (character === '"' && text[index + 1] === '"') {
        field += '"';
        index += 1;
      } else if (character === '"') quoted = false;
      else field += character;
    } else if (character === '"') quoted = true;
    else if (character === delimiter) {
      row.push(field);
      field = "";
    } else if (character === "\n") {
      row.push(field.replace(/\r$/, ""));
      if (row.some((cell) => cell.trim())) rows.push(row);
      row = [];
      field = "";
    } else field += character;
  }
  row.push(field.replace(/\r$/, ""));
  if (row.some((cell) => cell.trim())) rows.push(row);
  if (quoted) throw new Error("Delimited credential file has an unterminated quoted field.");
  return rows;
}

function tableToRecords(rows: readonly (readonly unknown[])[]): GenericRecord[] {
  if (!rows.length) return [];
  const headers = rows[0]!.map((cell) => String(cell ?? "").trim());
  if (!headers.some(Boolean)) throw new Error("Credential table needs a header row.");
  return rows.slice(1).filter((row) => row.some((cell) => cell !== null && cell !== undefined && String(cell).trim())).map((row) => {
    const record: GenericRecord = {};
    headers.forEach((header, index) => {
      if (header) record[header] = row[index];
    });
    return record;
  });
}

function normalizedRecord(value: GenericRecord): GenericRecord {
  return Object.fromEntries(Object.entries(value).map(([key, entry]) => [normalizeKey(key), entry]));
}

function normalizeKey(value: string): string {
  return value.trim().toLowerCase().replace(/[^a-z0-9]/g, "");
}

function normalizeLookup(value: string): string {
  return value.trim().toLowerCase();
}

function stringValue(value: unknown): string | null {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

function passwordValue(value: unknown): string | null {
  if (typeof value === "string" && value.length) return value;
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

function isPasswordValue(value: unknown): boolean {
  return passwordValue(value) !== null;
}

function isRecord(value: unknown): value is GenericRecord {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
