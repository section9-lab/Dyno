import { describe, expect, test } from "bun:test";

import { listAvailableModels } from "../src/model-catalog.ts";

describe("model catalog", () => {
  test("returns only stable UI model fields from the Pi runtime", async () => {
    const runtime = {
      getAvailable: async () => [{
        id: "gpt-test",
        name: "GPT Test",
        api: "openai-responses" as const,
        provider: "openai",
        baseUrl: "https://private.example.com",
        reasoning: true,
        input: ["text", "image"] as ("text" | "image")[],
        cost: { input: 1, output: 2, cacheRead: 3, cacheWrite: 4 },
        contextWindow: 128_000,
        maxTokens: 16_384,
        headers: { Authorization: "private" },
      }],
    };

    expect(await listAvailableModels(runtime)).toEqual([{
      provider: "openai",
      id: "gpt-test",
      name: "GPT Test",
      contextWindow: 128_000,
      maxTokens: 16_384,
      reasoning: true,
      supportsImages: true,
      supportsFastMode: false,
    }]);
  });

  test("marks only eligible OAuth subscription models as Fast-capable", async () => {
    const runtime = {
      getAvailable: async () => [
        {
          id: "gpt-5.6-sol",
          name: "GPT-5.6 Sol",
          api: "openai-codex-responses" as const,
          provider: "openai-codex",
          baseUrl: "https://chatgpt.com/backend-api",
          reasoning: true,
          input: ["text", "image"] as ("text" | "image")[],
          cost: { input: 5, output: 30, cacheRead: 0.5, cacheWrite: 0 },
          contextWindow: 272_000,
          maxTokens: 128_000,
        },
        {
          id: "gpt-5.3-codex-spark",
          name: "GPT-5.3 Codex Spark",
          api: "openai-codex-responses" as const,
          provider: "openai-codex",
          baseUrl: "https://chatgpt.com/backend-api",
          reasoning: true,
          input: ["text"] as ("text" | "image")[],
          cost: { input: 1.75, output: 14, cacheRead: 0.175, cacheWrite: 0 },
          contextWindow: 128_000,
          maxTokens: 128_000,
        },
      ],
    };

    expect(
      (await listAvailableModels(runtime)).map((model) => ({
        id: model.id,
        supportsFastMode: model.supportsFastMode,
      })),
    ).toEqual([
      { id: "gpt-5.6-sol", supportsFastMode: true },
      { id: "gpt-5.3-codex-spark", supportsFastMode: false },
    ]);
  });
});
