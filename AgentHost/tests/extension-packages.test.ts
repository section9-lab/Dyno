import { describe, expect, test } from "bun:test";
import type { ResolvedPaths } from "@earendil-works/pi-coding-agent";

import {
  ExtensionPackagesCoordinator,
  type ExtensionPackageManager,
} from "../src/extension-packages.ts";

function resolvedPaths(
  extensions: ResolvedPaths["extensions"],
): ResolvedPaths {
  return { extensions, skills: [], prompts: [], themes: [] };
}

describe("ExtensionPackagesCoordinator", () => {
  test("lists only configured packages that expose extension resources", async () => {
    let missingSourceAction: "install" | "skip" | "error" | undefined;
    const manager: ExtensionPackageManager = {
      listConfiguredPackages: () => [
        {
          source: "npm:pi-tools",
          scope: "user",
          filtered: false,
          installedPath: "/tmp/pi-tools",
        },
        {
          source: "npm:pi-theme",
          scope: "user",
          filtered: false,
          installedPath: "/tmp/pi-theme",
        },
      ],
      resolve: async (onMissing) => {
        missingSourceAction = await onMissing?.("npm:missing");
        return resolvedPaths([
          {
            path: "/tmp/pi-tools/extensions/index.ts",
            enabled: true,
            metadata: {
              source: "npm:pi-tools",
              scope: "user",
              origin: "package",
            },
          },
        ]);
      },
      installAndPersist: async () => {},
      update: async () => {},
      removeAndPersist: async () => true,
    };

    const coordinator = new ExtensionPackagesCoordinator(manager);

    expect(await coordinator.list()).toEqual({
      packages: [{
        source: "npm:pi-tools",
        scope: "user",
        filtered: false,
        installedPath: "/tmp/pi-tools",
        enabled: true,
      }],
    });
    expect(missingSourceAction).toBe("skip");
  });

  test("updates and removes the selected package through Pi's package manager", async () => {
    const calls: string[] = [];
    let configured = true;
    const manager: ExtensionPackageManager = {
      listConfiguredPackages: () => configured
        ? [{
            source: "npm:pi-tools",
            scope: "user",
            filtered: true,
            installedPath: "/tmp/pi-tools",
          }]
        : [],
      resolve: async () => resolvedPaths(configured
        ? [{
            path: "/tmp/pi-tools/extensions/index.ts",
            enabled: false,
            metadata: {
              source: "npm:pi-tools",
              scope: "user",
              origin: "package",
            },
          }]
        : []),
      installAndPersist: async () => {},
      update: async (source) => { calls.push(`update:${source}`); },
      removeAndPersist: async (source, options) => {
        calls.push(`remove:${source}:${options?.local === true ? "project" : "user"}`);
        configured = false;
        return true;
      },
    };
    const coordinator = new ExtensionPackagesCoordinator(manager);

    expect(await coordinator.update("npm:pi-tools")).toMatchObject({
      packages: [{ source: "npm:pi-tools", enabled: false }],
    });
    expect(await coordinator.remove("npm:pi-tools", "user")).toEqual({ packages: [] });
    expect(calls).toEqual([
      "update:npm:pi-tools",
      "remove:npm:pi-tools:user",
    ]);
  });

  test("installs a user-scoped npm extension and persists it", async () => {
    const calls: string[] = [];
    let configured = false;
    const manager: ExtensionPackageManager = {
      listConfiguredPackages: () => configured
        ? [{
            source: "npm:pi-tools",
            scope: "user",
            filtered: false,
            installedPath: "/tmp/pi-tools",
          }]
        : [],
      resolve: async () => resolvedPaths(configured
        ? [{
            path: "/tmp/pi-tools/extensions/index.ts",
            enabled: true,
            metadata: {
              source: "npm:pi-tools",
              scope: "user",
              origin: "package",
            },
          }]
        : []),
      installAndPersist: async (source, options) => {
        calls.push(`install:${source}:${options?.local === true ? "project" : "user"}`);
        configured = true;
      },
      update: async () => {},
      removeAndPersist: async () => true,
    };

    const coordinator = new ExtensionPackagesCoordinator(manager);

    expect(await coordinator.install("npm:pi-tools")).toMatchObject({
      packages: [{ source: "npm:pi-tools", enabled: true }],
    });
    expect(calls).toEqual(["install:npm:pi-tools:user"]);
  });

  test("disables and enables an installed package without uninstalling it", async () => {
    let packages: Array<string | {
      source: string;
      extensions?: string[];
      skills?: string[];
      prompts?: string[];
      themes?: string[];
    }> = ["npm:pi-tools"];
    const settings = {
      getPackages: (_scope: "user" | "project") => packages,
      setPackages: (
        _scope: "user" | "project",
        next: typeof packages,
      ) => { packages = next; },
      flush: async () => {},
    };
    const manager: ExtensionPackageManager = {
      listConfiguredPackages: () => [{
        source: "npm:pi-tools",
        scope: "user",
        filtered: typeof packages[0] === "object",
        installedPath: "/tmp/pi-tools",
      }],
      resolve: async () => resolvedPaths([{
        path: "/tmp/pi-tools/extensions/index.ts",
        enabled: typeof packages[0] === "string",
        metadata: {
          source: "npm:pi-tools",
          scope: "user",
          origin: "package",
        },
      }]),
      installAndPersist: async () => {},
      update: async () => {},
      removeAndPersist: async () => true,
    };
    const coordinator = new ExtensionPackagesCoordinator(manager, settings);

    expect(await coordinator.setEnabled("npm:pi-tools", "user", false)).toMatchObject({
      packages: [{ source: "npm:pi-tools", enabled: false }],
    });
    expect(packages).toEqual([{
      source: "npm:pi-tools",
      extensions: [],
      skills: [],
      prompts: [],
      themes: [],
    }]);

    expect(await coordinator.setEnabled("npm:pi-tools", "user", true)).toMatchObject({
      packages: [{ source: "npm:pi-tools", enabled: true }],
    });
    expect(packages).toEqual(["npm:pi-tools"]);
  });
});
