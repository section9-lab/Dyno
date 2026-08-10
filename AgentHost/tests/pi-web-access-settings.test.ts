import { afterEach, describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  defaultPiWebAccessConfiguration,
  PiWebAccessSettingsCoordinator,
} from "../src/pi-web-access-settings.ts";

const temporaryDirectories: string[] = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("PiWebAccessSettingsCoordinator", () => {
  test("creates a safe zero-configuration default on first use", async () => {
    const agentDirectory = mkdtempSync(join(tmpdir(), "pi-work-web-search-"));
    temporaryDirectories.push(agentDirectory);
    const coordinator = new PiWebAccessSettingsCoordinator(agentDirectory);

    expect(await coordinator.get()).toEqual(defaultPiWebAccessConfiguration);
    expect(existsSync(join(agentDirectory, "web-search.json"))).toBe(true);
    expect(JSON.parse(readFileSync(join(agentDirectory, "web-search.json"), "utf8"))).toEqual({
      provider: "auto",
      workflow: "auto-summary",
      fetchRouting: { allowRemoteHostedProviders: false },
    });
  });
});
