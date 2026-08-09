import { describe, expect, test } from "bun:test";

import { listProviderSnapshots } from "../src/provider-catalog.ts";

describe("provider catalog", () => {
  test("returns interactive methods and non-secret authentication status", async () => {
    const runtime = {
      getProviders: () => [
        {
          id: "anthropic",
          name: "Anthropic",
          auth: {
            apiKey: { name: "Anthropic API key", login: async () => ({ type: "api_key" }) },
            oauth: {
              name: "Anthropic Pro/Max",
              loginLabel: "Sign in with Claude",
              login: async () => ({ type: "oauth" }),
            },
          },
        },
        {
          id: "cc-switch",
          name: "CC Switch",
          auth: { apiKey: { name: "External configuration" } },
        },
      ],
      listCredentials: async () => [{ providerId: "anthropic", type: "oauth" as const }],
      getProviderAuthStatus: (providerId: string) => providerId === "anthropic"
        ? { configured: true, source: "stored" as const }
        : { configured: true, source: "models_json_key" as const },
      getModels: (providerId?: string) => providerId === "anthropic"
        ? [{ id: "claude-test", provider: "anthropic" }]
        : providerId === "cc-switch"
          ? [{ id: "cc-test", provider: "cc-switch" }]
          : [],
      getAvailableSnapshot: () => [{ id: "claude-test", provider: "anthropic" }],
    };

    expect(await listProviderSnapshots(runtime)).toEqual([
      {
        id: "anthropic",
        name: "Anthropic",
        methods: [
          { type: "oauth", name: "Anthropic Pro/Max", loginLabel: "Sign in with Claude" },
          { type: "api_key", name: "Anthropic API key" },
        ],
        status: {
          configured: true,
          source: "stored",
          credentialType: "oauth",
          canDisconnect: true,
        },
        models: { total: 1, available: 1 },
      },
      {
        id: "cc-switch",
        name: "CC Switch",
        methods: [],
        status: {
          configured: true,
          source: "models_json_key",
          credentialType: null,
          canDisconnect: false,
        },
        models: { total: 1, available: 0 },
      },
    ]);

    expect(JSON.stringify(await listProviderSnapshots(runtime))).not.toContain("secret");
  });
});
