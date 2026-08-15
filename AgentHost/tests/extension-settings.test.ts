import { afterEach, describe, expect, test } from "bun:test";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  ExtensionSettingsCoordinator,
  type ExtensionSettingsPackageProvider,
} from "../src/extension-settings.ts";

const temporaryDirectories: string[] = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("ExtensionSettingsCoordinator", () => {
  test("lists every installed extension and maps a declared schema to generic fields", async () => {
    const fixture = createFixture();
    const coordinator = new ExtensionSettingsCoordinator(
      fixture.agentDirectory,
      fixture.packages,
    );

    const result = await coordinator.list();

    expect(result.extensions.map((extension) => extension.source)).toEqual([
      "npm:pi-no-settings",
      "npm:pi-schema-demo",
    ]);
    expect(result.extensions[0]).toMatchObject({
      source: "npm:pi-no-settings",
      configurable: false,
      fields: [],
    });

    const settings = result.extensions[1]!;
    expect(settings.configurable).toBe(true);
    expect(settings.fields.map((field) => [field.path, field.kind])).toEqual([
      ["/enabled", "boolean"],
      ["/mode", "choice"],
      ["/token", "secure"],
      ["/retries", "integer"],
      ["/network/endpoint", "text"],
      ["/targets", "json"],
    ]);
    expect(settings.fields.find((field) => field.path === "/enabled")).toMatchObject({
      title: "Enabled",
      value: "true",
      defaultValue: "true",
      hasValue: false,
      required: false,
      readOnly: false,
      advanced: false,
    });
    expect(settings.fields.find((field) => field.path === "/mode")).toMatchObject({
      value: "fast",
      options: [
        { value: "safe", label: "Safe" },
        { value: "fast", label: "Fast" },
      ],
    });
    expect(settings.fields.find((field) => field.path === "/token")).toMatchObject({
      kind: "secure",
      hasValue: true,
    });
    expect(settings.fields.find((field) => field.path === "/token")?.value).toBeUndefined();
    expect(settings.fields.find((field) => field.path === "/retries")?.required).toBe(true);
    expect(settings.fields.find((field) => field.path === "/network/endpoint")).toMatchObject({
      group: "Network",
      description: "Service endpoint",
    });
  });

  test("patches only declared fields while preserving secrets and unknown configuration", async () => {
    const fixture = createFixture();
    const coordinator = new ExtensionSettingsCoordinator(
      fixture.agentDirectory,
      fixture.packages,
    );

    const updated = await coordinator.update(
      "npm:pi-schema-demo",
      "user",
      [
        { path: "/mode", operation: "set", value: "safe" },
        { path: "/retries", operation: "set", value: "1" },
        { path: "/network/endpoint", operation: "set", value: "https://new.example.com" },
      ],
    );

    expect(updated.fields.find((field) => field.path === "/mode")?.value).toBe("safe");
    expect(JSON.parse(readFileSync(fixture.configurationPath, "utf8"))).toEqual({
      mode: "safe",
      token: "stored-secret",
      retries: 1,
      network: { endpoint: "https://new.example.com" },
      targets: ["docs", "issues"],
      futureOption: { nested: true },
    });
  });

  test("rejects invalid and undeclared changes without touching the file", async () => {
    const fixture = createFixture();
    const coordinator = new ExtensionSettingsCoordinator(
      fixture.agentDirectory,
      fixture.packages,
    );
    const before = readFileSync(fixture.configurationPath, "utf8");

    await expect(coordinator.update(
      "npm:pi-schema-demo",
      "user",
      [{ path: "/retries", operation: "set", value: "9" }],
    )).rejects.toThrow("retries");
    await expect(coordinator.update(
      "npm:pi-schema-demo",
      "user",
      [{ path: "/futureOption/nested", operation: "set", value: "false" }],
    )).rejects.toThrow("declared");

    expect(readFileSync(fixture.configurationPath, "utf8")).toBe(before);
  });

  test("validates the complete configuration before persisting cross-field changes", async () => {
    const fixture = createFixture();
    const coordinator = new ExtensionSettingsCoordinator(
      fixture.agentDirectory,
      fixture.packages,
    );
    const before = readFileSync(fixture.configurationPath, "utf8");

    await expect(coordinator.update(
      "npm:pi-schema-demo",
      "user",
      [{ path: "/mode", operation: "set", value: "safe" }],
    )).rejects.toThrow("configuration");

    expect(readFileSync(fixture.configurationPath, "utf8")).toBe(before);
  });

  test("removes explicit overrides and stored secrets without rewriting other fields", async () => {
    const fixture = createFixture();
    const coordinator = new ExtensionSettingsCoordinator(
      fixture.agentDirectory,
      fixture.packages,
    );

    const updated = await coordinator.update(
      "npm:pi-schema-demo",
      "user",
      [
        { path: "/mode", operation: "remove" },
        { path: "/token", operation: "remove" },
      ],
    );

    expect(updated.fields.find((field) => field.path === "/mode")).toMatchObject({
      value: "safe",
      hasValue: false,
    });
    expect(updated.fields.find((field) => field.path === "/token")?.hasValue).toBe(false);
    expect(JSON.parse(readFileSync(fixture.configurationPath, "utf8"))).toEqual({
      retries: 2,
      network: { endpoint: "https://old.example.com" },
      targets: ["docs", "issues"],
      futureOption: { nested: true },
    });
  });

  test("rejects schema and configuration paths outside their declared roots", async () => {
    const schemaFixture = createFixture();
    writeFileSync(join(schemaFixture.packageDirectory, "package.json"), JSON.stringify({
      name: "pi-schema-demo",
      pi: {
        extensions: ["./index.ts"],
        configuration: {
          schema: "../outside.schema.json",
          file: "configs/pi-schema-demo.json",
        },
      },
    }));
    await expect(new ExtensionSettingsCoordinator(
      schemaFixture.agentDirectory,
      schemaFixture.packages,
    ).list()).rejects.toThrow("package root");

    const configurationFixture = createFixture();
    writeFileSync(join(configurationFixture.packageDirectory, "package.json"), JSON.stringify({
      name: "pi-schema-demo",
      pi: {
        extensions: ["./index.ts"],
        configuration: {
          schema: "./settings.schema.json",
          file: "../outside.json",
        },
      },
    }));
    await expect(new ExtensionSettingsCoordinator(
      configurationFixture.agentDirectory,
      configurationFixture.packages,
    ).list()).rejects.toThrow("agent root");
  });

  test("adapts pi-web-access through the same generic field descriptor", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-web-access-settings-"));
    temporaryDirectories.push(root);
    const agentDirectory = join(root, "agent");
    const packageDirectory = join(root, "pi-web-access");
    mkdirSync(agentDirectory, { recursive: true });
    mkdirSync(packageDirectory, { recursive: true });
    writeFileSync(join(packageDirectory, "package.json"), JSON.stringify({
      name: "pi-web-access",
      pi: { extensions: ["./index.ts"] },
    }));
    writeFileSync(join(agentDirectory, "web-search.json"), JSON.stringify({
      provider: "exa",
      workflow: "summary-review",
    }));
    const packages: ExtensionSettingsPackageProvider = async () => ({
      packages: [{
        source: "npm:pi-web-access",
        scope: "user",
        filtered: false,
        installedPath: packageDirectory,
        enabled: true,
      }],
    });

    const result = await new ExtensionSettingsCoordinator(agentDirectory, packages).list();

    expect(result.extensions[0]).toMatchObject({
      source: "npm:pi-web-access",
      scope: "user",
      configurable: true,
    });
    expect(result.extensions[0]?.fields.find((field) => field.path === "/provider"))
      .toMatchObject({ kind: "text", value: "exa" });
    expect(result.extensions[0]?.fields.find((field) => field.path === "/workflow"))
      .toMatchObject({
        kind: "choice",
        value: "summary-review",
        options: [
          { value: "summary-review", label: "Summary review" },
          { value: "auto-summary", label: "Auto summary" },
          { value: "none", label: "None" },
        ],
      });
  });
});

function createFixture(): {
  agentDirectory: string;
  configurationPath: string;
  packageDirectory: string;
  packages: ExtensionSettingsPackageProvider;
} {
  const root = mkdtempSync(join(tmpdir(), "pi-work-extension-settings-"));
  temporaryDirectories.push(root);
  const agentDirectory = join(root, "agent");
  const packageDirectory = join(root, "pi-schema-demo");
  mkdirSync(packageDirectory, { recursive: true });
  mkdirSync(join(agentDirectory, "configs"), { recursive: true });

  writeFileSync(join(packageDirectory, "package.json"), JSON.stringify({
    name: "pi-schema-demo",
    pi: {
      extensions: ["./index.ts"],
      configuration: {
        schema: "./settings.schema.json",
        file: "configs/pi-schema-demo.json",
      },
    },
  }));
  writeFileSync(join(packageDirectory, "settings.schema.json"), JSON.stringify({
    $schema: "https://json-schema.org/draft/2020-12/schema",
    type: "object",
    minProperties: 2,
    required: ["retries"],
    if: {
      properties: { mode: { const: "safe" } },
      required: ["mode"],
    },
    then: {
      properties: { retries: { maximum: 1 } },
      required: ["retries"],
    },
    properties: {
      enabled: {
        type: "boolean",
        title: "Enabled",
        default: true,
        "x-pi-order": 1,
      },
      mode: {
        type: "string",
        title: "Mode",
        enum: ["safe", "fast"],
        "x-pi-enumNames": ["Safe", "Fast"],
        default: "safe",
        "x-pi-order": 2,
      },
      token: {
        type: "string",
        title: "API token",
        writeOnly: true,
        "x-pi-order": 3,
      },
      retries: {
        type: "integer",
        title: "Retries",
        minimum: 0,
        maximum: 5,
        "x-pi-order": 4,
      },
      network: {
        type: "object",
        title: "Network",
        "x-pi-order": 5,
        properties: {
          endpoint: {
            type: "string",
            title: "Endpoint",
            description: "Service endpoint",
            format: "uri",
          },
        },
      },
      targets: {
        type: "array",
        title: "Targets",
        items: { type: "string" },
        "x-pi-order": 6,
      },
    },
  }));

  const configurationPath = join(agentDirectory, "configs/pi-schema-demo.json");
  writeFileSync(configurationPath, JSON.stringify({
    mode: "fast",
    token: "stored-secret",
    retries: 2,
    network: { endpoint: "https://old.example.com" },
    targets: ["docs", "issues"],
    futureOption: { nested: true },
  }, null, 2));

  const packages: ExtensionSettingsPackageProvider = async () => ({
    packages: [
      {
        source: "npm:pi-no-settings",
        scope: "user",
        filtered: false,
        installedPath: join(root, "pi-no-settings"),
        enabled: true,
      },
      {
        source: "npm:pi-schema-demo",
        scope: "user",
        filtered: false,
        installedPath: packageDirectory,
        enabled: true,
      },
    ],
  });

  return { agentDirectory, configurationPath, packageDirectory, packages };
}
