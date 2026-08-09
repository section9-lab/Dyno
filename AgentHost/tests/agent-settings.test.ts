import { describe, expect, test } from "bun:test";
import { SettingsManager } from "@earendil-works/pi-coding-agent";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  AgentSettingsCoordinator,
  createAgentSettingsCoordinator,
  createAgentSettingsManager,
} from "../src/agent-settings.ts";

describe("AgentSettingsCoordinator", () => {
  test("returns the effective desktop-agent defaults", () => {
    const coordinator = new AgentSettingsCoordinator(SettingsManager.inMemory());

    expect(coordinator.snapshot()).toEqual({
      defaultModel: null,
      defaultThinkingLevel: "off",
      transport: "auto",
      compactionEnabled: true,
      retryEnabled: true,
    });
  });

  test("persists supported settings through Pi's SettingsManager", async () => {
    const settings = SettingsManager.inMemory();
    const coordinator = new AgentSettingsCoordinator(settings);

    await coordinator.update({
      defaultModel: { provider: "openai", modelId: "gpt-test" },
      defaultThinkingLevel: "high",
      transport: "sse",
      compactionEnabled: false,
      retryEnabled: false,
    });

    expect(coordinator.snapshot()).toEqual({
      defaultModel: { provider: "openai", modelId: "gpt-test" },
      defaultThinkingLevel: "high",
      transport: "sse",
      compactionEnabled: false,
      retryEnabled: false,
    });
  });

  test("writes desktop settings only inside pi-work's agent directory", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pi-work-agent-settings-"));
    try {
      const coordinator = createAgentSettingsCoordinator(
        "/tmp/project",
        { PI_WORK_AGENT_DIR: directory },
      );

      await coordinator.update({ retryEnabled: false });

      expect(JSON.parse(await readFile(join(directory, "settings.json"), "utf8"))).toEqual({
        retry: { enabled: false },
      });
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  test("configures Pi's package manager to use pi-work's bundled Bun", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pi-work-agent-bun-settings-"));
    try {
      const settings = createAgentSettingsManager(
        "/tmp/project",
        {
          PI_WORK_AGENT_DIR: directory,
          PI_WORK_BUN_PATH: "/Applications/PiWork.app/Contents/Helpers/Bun/arm64/bun",
        },
      );

      await settings.flush();

      expect(settings.getNpmCommand()).toEqual([
        "/Applications/PiWork.app/Contents/Helpers/Bun/arm64/bun",
      ]);
      expect(JSON.parse(await readFile(join(directory, "settings.json"), "utf8")))
        .toMatchObject({
          npmCommand: [
            "/Applications/PiWork.app/Contents/Helpers/Bun/arm64/bun",
          ],
        });
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });
});
