import { randomUUID } from "node:crypto";
import {
  lstat,
  mkdir,
  open,
  readFile,
  realpath,
  rename,
  rm,
} from "node:fs/promises";
import {
  basename,
  dirname,
  isAbsolute,
  relative,
  resolve,
} from "node:path";
import { Value } from "typebox/value";

import type {
  ExtensionPackageScope,
  InstalledExtensionPackage,
  InstalledExtensionPackagesSnapshot,
} from "./extension-packages.ts";

type JSONObject = Record<string, unknown>;

export type ExtensionSettingsPackageProvider =
  () => Promise<InstalledExtensionPackagesSnapshot>;

export type ExtensionSettingsFieldKind =
  | "boolean"
  | "choice"
  | "secure"
  | "integer"
  | "number"
  | "text"
  | "json";

export type ExtensionSettingsOption = {
  value: string;
  label: string;
};

export type ExtensionSettingsField = {
  path: string;
  kind: ExtensionSettingsFieldKind;
  title: string;
  description?: string;
  group?: string;
  value?: string;
  defaultValue?: string;
  hasValue: boolean;
  options?: ExtensionSettingsOption[];
  required: boolean;
  readOnly: boolean;
  advanced: boolean;
};

export type ExtensionSettingsDescriptor = {
  source: string;
  scope: ExtensionPackageScope;
  configurable: boolean;
  fields: ExtensionSettingsField[];
};

export type ExtensionSettingsSnapshot = {
  extensions: ExtensionSettingsDescriptor[];
};

export type ExtensionSettingsChange =
  | { path: string; operation: "set"; value: string }
  | { path: string; operation: "remove" };

type ConfigurationDeclaration = {
  schema: JSONObject;
  file: string;
};

type InternalField = {
  descriptor: ExtensionSettingsField;
  segments: string[];
  choices?: Array<{ encoded: string; value: unknown }>;
};

const piWebAccessSource = "npm:pi-web-access";
const piWebAccessConfiguration: ConfigurationDeclaration = {
  file: "web-search.json",
  schema: {
    type: "object",
    properties: {
      provider: {
        type: "string",
        title: "Search provider",
        description: "Provider name, or auto to select an available provider.",
        default: "auto",
        "x-pi-order": 1,
      },
      workflow: {
        type: "string",
        title: "Search workflow",
        description: "How search results are reviewed and summarized.",
        enum: ["summary-review", "auto-summary", "none"],
        "x-pi-enumNames": ["Summary review", "Auto summary", "None"],
        default: "auto-summary",
        "x-pi-order": 2,
      },
    },
  },
};

export class ExtensionSettingsCoordinator {
  private readonly agentDirectory: string;

  constructor(
    agentDirectory: string,
    private readonly packageProvider: ExtensionSettingsPackageProvider,
  ) {
    this.agentDirectory = resolve(agentDirectory);
  }

  async list(): Promise<ExtensionSettingsSnapshot> {
    const packages = [...(await this.packageProvider()).packages]
      .sort((left, right) => (
        left.source.localeCompare(right.source)
        || left.scope.localeCompare(right.scope)
      ));
    return {
      extensions: await Promise.all(packages.map((pkg) => this.describe(pkg))),
    };
  }

  async update(
    source: string,
    scope: ExtensionPackageScope,
    changes: ExtensionSettingsChange[],
  ): Promise<ExtensionSettingsDescriptor> {
    const pkg = (await this.packageProvider()).packages.find((candidate) => (
      candidate.source === source && candidate.scope === scope
    ));
    if (!pkg) {
      throw new Error(`No matching installed extension found: ${source} (${scope})`);
    }

    const declaration = await this.configurationDeclaration(pkg);
    if (!declaration) throw new Error(`Extension is not configurable: ${source}`);
    const configuration = await this.readConfiguration(declaration.file);
    const fields = buildFields(declaration.schema, configuration);
    const fieldsByPath = new Map(fields.map((field) => [field.descriptor.path, field]));
    const next = cloneJSON(configuration);
    const changedPaths = new Set<string>();

    for (const change of changes) {
      const field = fieldsByPath.get(change.path);
      if (!field) {
        throw new Error(`Configuration path is not declared by the schema: ${change.path}`);
      }
      if (field.descriptor.readOnly) {
        throw new Error(`Configuration field is read-only: ${change.path}`);
      }
      if (changedPaths.has(change.path)) {
        throw new Error(`Configuration path was changed more than once: ${change.path}`);
      }
      changedPaths.add(change.path);

      if (change.operation === "remove") {
        removeConfigurationValue(next, field.segments);
      } else {
        const value = parseFieldValue(field, change.value);
        setConfigurationValue(next, field.segments, value);
      }
    }

    if (changes.length > 0) {
      validateConfiguration(declaration.schema, next);
      await this.writeConfiguration(declaration.file, next);
    }
    return descriptor(pkg, declaration.schema, next);
  }

  private async describe(
    pkg: InstalledExtensionPackage,
  ): Promise<ExtensionSettingsDescriptor> {
    const declaration = await this.configurationDeclaration(pkg);
    if (!declaration) {
      return {
        source: pkg.source,
        scope: pkg.scope,
        configurable: false,
        fields: [],
      };
    }
    return descriptor(
      pkg,
      declaration.schema,
      await this.readConfiguration(declaration.file),
    );
  }

  private async configurationDeclaration(
    pkg: InstalledExtensionPackage,
  ): Promise<ConfigurationDeclaration | undefined> {
    const manifest = await readPackageManifest(pkg.installedPath);
    const pi = manifest && isJSONObject(manifest.pi) ? manifest.pi : undefined;
    const configuration = pi && isJSONObject(pi.configuration)
      ? pi.configuration
      : undefined;
    if (!configuration) {
      return pkg.source === piWebAccessSource
        ? piWebAccessConfiguration
        : undefined;
    }

    const schemaFile = configuration.schema;
    const configurationFile = configuration.file;
    if (typeof schemaFile !== "string" || schemaFile.trim().length === 0) {
      throw new Error(`${pkg.source} pi.configuration.schema must be a relative path`);
    }
    if (typeof configurationFile !== "string" || configurationFile.trim().length === 0) {
      throw new Error(`${pkg.source} pi.configuration.file must be a relative path`);
    }
    if (!pkg.installedPath) {
      throw new Error(`${pkg.source} does not expose an installed package path`);
    }

    const packageRoot = await realpath(pkg.installedPath);
    const schemaPath = await existingPathWithin(
      packageRoot,
      schemaFile,
      `${pkg.source} schema must stay within its package root`,
    );
    assertRelativePath(
      configurationFile,
      `${pkg.source} configuration file must stay within the agent root`,
    );
    assertPathWithin(
      this.agentDirectory,
      resolve(this.agentDirectory, configurationFile),
      `${pkg.source} configuration file must stay within the agent root`,
    );

    const schema = parseJSONObject(
      await readFile(schemaPath, "utf8"),
      `${pkg.source} configuration schema`,
    );
    const resolvedRoot = resolveSchemaReference(schema, schema);
    if (resolvedRoot.type !== "object" || !isJSONObject(resolvedRoot.properties)) {
      throw new Error(`${pkg.source} configuration schema must describe an object`);
    }
    return { schema, file: configurationFile };
  }

  private async readConfiguration(file: string): Promise<JSONObject> {
    assertRelativePath(file, "Extension configuration file must stay within the agent root");
    const root = await existingRealPath(this.agentDirectory);
    if (!root) return {};
    const path = resolve(root, file);
    assertPathWithin(root, path, "Extension configuration file must stay within the agent root");

    let status;
    try {
      status = await lstat(path);
    } catch (error) {
      if (isMissingFile(error)) return {};
      throw error;
    }
    if (status.isSymbolicLink()) {
      throw new Error("Extension configuration file must not be a symbolic link");
    }
    const resolvedPath = await realpath(path);
    assertPathWithin(root, resolvedPath, "Extension configuration file must stay within the agent root");
    return parseJSONObject(
      await readFile(resolvedPath, "utf8"),
      "Extension configuration",
    );
  }

  private async writeConfiguration(file: string, configuration: JSONObject): Promise<void> {
    assertRelativePath(file, "Extension configuration file must stay within the agent root");
    await mkdir(this.agentDirectory, { recursive: true });
    const root = await realpath(this.agentDirectory);
    const requestedPath = resolve(root, file);
    assertPathWithin(
      root,
      requestedPath,
      "Extension configuration file must stay within the agent root",
    );

    await assertExistingAncestorWithin(root, dirname(requestedPath));
    await mkdir(dirname(requestedPath), { recursive: true });
    const parent = await realpath(dirname(requestedPath));
    assertPathWithin(root, parent, "Extension configuration file must stay within the agent root");
    const path = resolve(parent, basename(requestedPath));
    assertPathWithin(root, path, "Extension configuration file must stay within the agent root");
    try {
      if ((await lstat(path)).isSymbolicLink()) {
        throw new Error("Extension configuration file must not be a symbolic link");
      }
    } catch (error) {
      if (!isMissingFile(error)) throw error;
    }

    const temporaryPath = resolve(
      parent,
      `.${basename(path)}.${process.pid}.${randomUUID()}.tmp`,
    );
    let handle;
    try {
      handle = await open(temporaryPath, "wx", 0o600);
      await handle.writeFile(`${JSON.stringify(configuration, null, 2)}\n`, "utf8");
      await handle.sync();
      await handle.close();
      handle = undefined;
      await rename(temporaryPath, path);
    } finally {
      await handle?.close().catch(() => {});
      await rm(temporaryPath, { force: true }).catch(() => {});
    }
  }
}

function descriptor(
  pkg: InstalledExtensionPackage,
  schema: JSONObject,
  configuration: JSONObject,
): ExtensionSettingsDescriptor {
  return {
    source: pkg.source,
    scope: pkg.scope,
    configurable: true,
    fields: buildFields(schema, configuration).map((field) => field.descriptor),
  };
}

function buildFields(rootSchema: JSONObject, configuration: JSONObject): InternalField[] {
  const root = resolveSchemaReference(rootSchema, rootSchema);
  const properties = root.properties;
  if (!isJSONObject(properties)) return [];

  const fields: InternalField[] = [];
  walkProperties(rootSchema, properties, configuration, [], undefined, root.required, fields);
  return fields;
}

function walkProperties(
  rootSchema: JSONObject,
  properties: JSONObject,
  configuration: unknown,
  parentSegments: string[],
  group: string | undefined,
  requiredValue: unknown,
  fields: InternalField[],
): void {
  const required = new Set(
    Array.isArray(requiredValue)
      ? requiredValue.filter((value): value is string => typeof value === "string")
      : [],
  );
  const ordered = Object.entries(properties)
    .filter((entry): entry is [string, JSONObject] => isJSONObject(entry[1]))
    .map(([name, schema], index) => ({ name, schema, index }))
    .sort((left, right) => (
      schemaOrder(left.schema) - schemaOrder(right.schema)
      || left.index - right.index
    ));

  for (const { name, schema } of ordered) {
    const resolvedSchema = resolveSchemaReference(rootSchema, schema);
    const segments = [...parentSegments, name];
    const path = `/${segments.map(escapeJSONPointerSegment).join("/")}`;
    const value = configurationValue(configuration, name);
    const nestedProperties = resolvedSchema.properties;
    if (
      !isSecureSchema(resolvedSchema)
      && resolvedSchema.type === "object"
      && isJSONObject(nestedProperties)
      && Object.keys(nestedProperties).length > 0
    ) {
      const nestedTitle = schemaTitle(resolvedSchema, name);
      walkProperties(
        rootSchema,
        nestedProperties,
        value.present && isJSONObject(value.value) ? value.value : undefined,
        segments,
        group ? `${group} / ${nestedTitle}` : nestedTitle,
        resolvedSchema.required,
        fields,
      );
      continue;
    }

    const choiceValues = schemaChoices(resolvedSchema);
    const kind = schemaKind(resolvedSchema, choiceValues);
    const defaultValue = resolvedSchema.default;
    const displayValue = value.present ? value.value : defaultValue;
    const secure = kind === "secure";
    const description = typeof resolvedSchema.description === "string"
      && resolvedSchema.description.trim().length > 0
      ? resolvedSchema.description
      : undefined;
    const choices = choiceValues?.map((choice) => ({
      encoded: encodeFieldValue(choice.value),
      value: choice.value,
    }));
    fields.push({
      descriptor: {
        path,
        kind,
        title: schemaTitle(resolvedSchema, name),
        ...(description ? { description } : {}),
        ...(group ? { group } : {}),
        ...(!secure && displayValue !== undefined
          ? { value: encodeFieldValue(displayValue) }
          : {}),
        ...(!secure && defaultValue !== undefined
          ? { defaultValue: encodeFieldValue(defaultValue) }
          : {}),
        hasValue: value.present,
        ...(choiceValues
          ? {
              options: choiceValues.map((choice) => ({
                value: encodeFieldValue(choice.value),
                label: choice.label,
              })),
            }
          : {}),
        required: required.has(name),
        readOnly: resolvedSchema.readOnly === true,
        advanced: resolvedSchema["x-pi-advanced"] === true,
      },
      segments,
      choices,
    });
  }
}

function schemaKind(
  schema: JSONObject,
  choices: Array<{ value: unknown; label: string }> | undefined,
): ExtensionSettingsFieldKind {
  if (isSecureSchema(schema)) return "secure";
  if (choices) return "choice";
  if (schema.type === "boolean") return "boolean";
  if (schema.type === "integer") return "integer";
  if (schema.type === "number") return "number";
  if (schema.type === "string") return "text";
  return "json";
}

function schemaChoices(
  schema: JSONObject,
): Array<{ value: unknown; label: string }> | undefined {
  if (Array.isArray(schema.enum) && schema.enum.length > 0) {
    const names = Array.isArray(schema["x-pi-enumNames"])
      ? schema["x-pi-enumNames"]
      : [];
    return schema.enum.map((value, index) => ({
      value,
      label: typeof names[index] === "string" ? names[index] : encodeFieldValue(value),
    }));
  }
  if (Array.isArray(schema.oneOf) && schema.oneOf.length > 0) {
    const choices = schema.oneOf.flatMap((entry) => (
      isJSONObject(entry) && Object.hasOwn(entry, "const")
        ? [{
            value: entry.const,
            label: typeof entry.title === "string"
              ? entry.title
              : encodeFieldValue(entry.const),
          }]
        : []
    ));
    if (choices.length === schema.oneOf.length) return choices;
  }
  return undefined;
}

function parseFieldValue(field: InternalField, encoded: string): unknown {
  if (field.choices) {
    const choice = field.choices.find((candidate) => candidate.encoded === encoded);
    if (!choice) throw new Error(`Invalid choice for ${field.descriptor.path}`);
    return cloneJSONValue(choice.value);
  }

  if (field.descriptor.kind === "boolean") {
    if (encoded === "true") return true;
    if (encoded === "false") return false;
    throw new Error(`${field.descriptor.path} must be true or false`);
  }
  if (field.descriptor.kind === "integer" || field.descriptor.kind === "number") {
    let value: unknown;
    try {
      value = JSON.parse(encoded);
    } catch {
      throw new Error(`${field.descriptor.path} must be a valid number`);
    }
    if (typeof value !== "number" || !Number.isFinite(value)) {
      throw new Error(`${field.descriptor.path} must be a valid number`);
    }
    if (field.descriptor.kind === "integer" && !Number.isSafeInteger(value)) {
      throw new Error(`${field.descriptor.path} must be an integer`);
    }
    return value;
  }
  if (field.descriptor.kind === "json") {
    try {
      return JSON.parse(encoded);
    } catch {
      throw new Error(`${field.descriptor.path} must be valid JSON`);
    }
  }
  return encoded;
}

function validateConfiguration(schema: JSONObject, configuration: JSONObject): void {
  let errors;
  try {
    errors = [...Value.Errors(resolveSchemaReference(schema, schema) as never, configuration)];
  } catch (error) {
    throw new Error(`Cannot validate extension configuration: ${errorMessage(error)}`);
  }
  if (errors.length > 0) {
    const first = errors[0];
    const instancePath = first
      && "instancePath" in first
      && typeof first.instancePath === "string"
      ? first.instancePath
      : undefined;
    throw new Error(
      `Extension configuration is invalid: ${instancePath ? `${instancePath} ` : ""}${first?.message ?? "schema validation failed"}`,
    );
  }
}

function setConfigurationValue(
  configuration: JSONObject,
  segments: string[],
  value: unknown,
): void {
  let current = configuration;
  for (const segment of segments.slice(0, -1)) {
    const existing = Object.hasOwn(current, segment) ? current[segment] : undefined;
    if (existing === undefined) {
      const next: JSONObject = {};
      defineJSONProperty(current, segment, next);
      current = next;
      continue;
    }
    if (!isJSONObject(existing)) {
      throw new Error(`Configuration parent is not an object: ${segment}`);
    }
    current = existing;
  }
  const finalSegment = segments.at(-1);
  if (!finalSegment) throw new Error("Configuration path must not be empty");
  defineJSONProperty(current, finalSegment, value);
}

function removeConfigurationValue(
  configuration: JSONObject,
  segments: string[],
): void {
  let current = configuration;
  for (const segment of segments.slice(0, -1)) {
    const existing = Object.hasOwn(current, segment) ? current[segment] : undefined;
    if (existing === undefined) return;
    if (!isJSONObject(existing)) {
      throw new Error(`Configuration parent is not an object: ${segment}`);
    }
    current = existing;
  }
  const finalSegment = segments.at(-1);
  if (!finalSegment) throw new Error("Configuration path must not be empty");
  delete current[finalSegment];
}

function defineJSONProperty(target: JSONObject, key: string, value: unknown): void {
  Object.defineProperty(target, key, {
    value,
    configurable: true,
    enumerable: true,
    writable: true,
  });
}

async function readPackageManifest(
  installedPath: string | undefined,
): Promise<JSONObject | undefined> {
  if (!installedPath) return undefined;
  let root: string;
  try {
    root = await realpath(installedPath);
  } catch (error) {
    if (isMissingFile(error)) return undefined;
    throw error;
  }
  const packagePath = await existingPathWithin(
    root,
    "package.json",
    "Extension package manifest must stay within its package root",
  ).catch((error) => {
    if (isMissingFile(error)) return undefined;
    throw error;
  });
  if (!packagePath) return undefined;
  return parseJSONObject(await readFile(packagePath, "utf8"), "Extension package manifest");
}

async function existingPathWithin(
  root: string,
  path: string,
  message: string,
): Promise<string> {
  assertRelativePath(path, message);
  const candidate = resolve(root, path);
  assertPathWithin(root, candidate, message);
  const resolvedPath = await realpath(candidate);
  assertPathWithin(root, resolvedPath, message);
  return resolvedPath;
}

async function existingRealPath(path: string): Promise<string | undefined> {
  try {
    return await realpath(path);
  } catch (error) {
    if (isMissingFile(error)) return undefined;
    throw error;
  }
}

async function assertExistingAncestorWithin(root: string, path: string): Promise<void> {
  let candidate = path;
  while (true) {
    try {
      const resolvedCandidate = await realpath(candidate);
      assertPathWithin(
        root,
        resolvedCandidate,
        "Extension configuration directory must stay within the agent root",
      );
      return;
    } catch (error) {
      if (!isMissingFile(error)) throw error;
    }
    const parent = dirname(candidate);
    if (parent === candidate) {
      throw new Error("Extension configuration directory must stay within the agent root");
    }
    candidate = parent;
  }
}

function assertRelativePath(path: string, message: string): void {
  if (isAbsolute(path)) throw new Error(message);
}

function assertPathWithin(root: string, path: string, message: string): void {
  const child = relative(root, path);
  if (child === "" || (!child.startsWith("..") && !isAbsolute(child))) return;
  throw new Error(message);
}

function resolveSchemaReference(root: JSONObject, schema: JSONObject): JSONObject {
  const reference = schema.$ref;
  if (typeof reference !== "string" || !reference.startsWith("#/")) return schema;
  let current: unknown = root;
  for (const rawSegment of reference.slice(2).split("/")) {
    if (!isJSONObject(current)) {
      throw new Error(`Invalid local schema reference: ${reference}`);
    }
    const segment = rawSegment.replace(/~1/g, "/").replace(/~0/g, "~");
    current = current[segment];
  }
  if (!isJSONObject(current)) throw new Error(`Invalid local schema reference: ${reference}`);
  const siblings = { ...schema };
  delete siblings.$ref;
  return { ...current, ...siblings };
}

function configurationValue(
  configuration: unknown,
  name: string,
): { present: boolean; value?: unknown } {
  if (!isJSONObject(configuration) || !Object.hasOwn(configuration, name)) {
    return { present: false };
  }
  return { present: true, value: configuration[name] };
}

function schemaOrder(schema: JSONObject): number {
  const order = schema["x-pi-order"];
  return typeof order === "number" && Number.isFinite(order)
    ? order
    : Number.MAX_SAFE_INTEGER;
}

function schemaTitle(schema: JSONObject, fallback: string): string {
  return typeof schema.title === "string" && schema.title.trim().length > 0
    ? schema.title
    : fallback
      .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
      .replace(/[-_]+/g, " ")
      .replace(/^./, (character) => character.toUpperCase());
}

function isSecureSchema(schema: JSONObject): boolean {
  return schema.writeOnly === true
    || schema.format === "password"
    || schema["x-pi-secret"] === true;
}

function encodeFieldValue(value: unknown): string {
  if (typeof value === "string") return value;
  const encoded = JSON.stringify(value);
  return encoded === undefined ? "" : encoded;
}

function escapeJSONPointerSegment(segment: string): string {
  return segment.replace(/~/g, "~0").replace(/\//g, "~1");
}

function parseJSONObject(raw: string, label: string): JSONObject {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch (error) {
    throw new Error(`${label} must be valid JSON: ${errorMessage(error)}`);
  }
  if (!isJSONObject(value)) throw new Error(`${label} must be a JSON object`);
  return value;
}

function isJSONObject(value: unknown): value is JSONObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function cloneJSON(value: JSONObject): JSONObject {
  return JSON.parse(JSON.stringify(value)) as JSONObject;
}

function cloneJSONValue(value: unknown): unknown {
  return JSON.parse(JSON.stringify(value));
}

function isMissingFile(error: unknown): boolean {
  return (error as NodeJS.ErrnoException).code === "ENOENT";
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
