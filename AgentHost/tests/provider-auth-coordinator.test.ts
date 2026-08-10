import { describe, expect, test } from "bun:test";

import {
  ProviderAuthCoordinator,
  type ProviderAuthCoordinatorEvent,
} from "../src/provider-auth-coordinator.ts";

describe("ProviderAuthCoordinator", () => {
  test("bridges a prompt response and emits completion without exposing credentials", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    const runtime = {
      login: async (_providerId: string, _type: "oauth" | "api_key", interaction: any) => {
        const method = await interaction.prompt({
          type: "select",
          message: "Choose a login method",
          options: [{ id: "browser", label: "Browser" }],
        });
        interaction.notify({ type: "progress", message: `Using ${method}` });
        return { type: "oauth", access: "do-not-emit", refresh: "do-not-emit", expires: 1 };
      },
      logout: async () => {},
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));

    expect(coordinator.start({
      flowId: "flow-one",
      providerId: "openai-codex",
      method: "oauth",
    })).toEqual({ accepted: true, flowId: "flow-one" });

    const prompt = events.find((event) => event.event === "auth.prompt");
    expect(prompt).toMatchObject({
      event: "auth.prompt",
      payload: {
        flowId: "flow-one",
        providerId: "openai-codex",
        sequence: 1,
        type: "select",
        message: "Choose a login method",
        options: [{ id: "browser", label: "Browser" }],
      },
    });

    const promptId = prompt?.event === "auth.prompt" ? prompt.payload.promptId : "";
    expect(coordinator.respond({
      flowId: "flow-one",
      promptId,
      value: "browser",
    })).toEqual({ accepted: true });

    await Bun.sleep(0);

    expect(events).toContainEqual({
      event: "models.changed",
      payload: { reason: "authentication", providerId: "openai-codex" },
    });
    expect(events.at(-1)).toMatchObject({
      event: "auth.finished",
      payload: { flowId: "flow-one", outcome: "succeeded" },
    });
    expect(JSON.stringify(events)).not.toContain("do-not-emit");
  });

  test("marks the GitHub Copilot host prompt as accepting the github.com default", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    let response: string | undefined;
    const runtime = {
      login: async (_providerId: string, _type: "oauth" | "api_key", interaction: any) => {
        response = await interaction.prompt({
          type: "text",
          message: "GitHub Enterprise URL/domain (blank for github.com)",
          placeholder: "company.ghe.com",
        });
        return { type: "oauth", access: "hidden", refresh: "hidden", expires: 1 };
      },
      logout: async () => {},
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));

    coordinator.start({ flowId: "flow-copilot", providerId: "github-copilot", method: "oauth" });

    const prompt = events.find((event) => event.event === "auth.prompt");
    expect(prompt).toMatchObject({
      event: "auth.prompt",
      payload: {
        providerId: "github-copilot",
        type: "text",
        allowsEmpty: true,
      },
    });

    coordinator.respond({
      flowId: "flow-copilot",
      promptId: prompt?.event === "auth.prompt" ? prompt.payload.promptId : "",
      value: "",
    });
    await Bun.sleep(0);

    expect(response).toBe("");
    expect(events.at(-1)).toMatchObject({
      event: "auth.finished",
      payload: { outcome: "succeeded" },
    });
  });

  test("marks the Bedrock credential-chain confirmation as accepting an empty response", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    let response: string | undefined;
    const runtime = {
      login: async (_providerId: string, _type: "oauth" | "api_key", interaction: any) => {
        response = await interaction.prompt({
          type: "text",
          message: "Configure AWS credentials, then press Enter to continue",
        });
        return { type: "api_key", env: { AWS_PROFILE: "default" } };
      },
      logout: async () => {},
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));

    coordinator.start({ flowId: "flow-bedrock", providerId: "amazon-bedrock", method: "api_key" });

    const prompt = events.find((event) => event.event === "auth.prompt");
    expect(prompt).toMatchObject({
      event: "auth.prompt",
      payload: {
        providerId: "amazon-bedrock",
        type: "text",
        allowsEmpty: true,
      },
    });

    coordinator.respond({
      flowId: "flow-bedrock",
      promptId: prompt?.event === "auth.prompt" ? prompt.payload.promptId : "",
      value: "",
    });
    await Bun.sleep(0);

    expect(response).toBe("");
    expect(events.at(-1)).toMatchObject({
      event: "auth.finished",
      payload: { outcome: "succeeded" },
    });
  });

  test("refreshes the Radius catalog from the network after login", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    const refreshes: unknown[] = [];
    const runtime = {
      login: async () => ({ type: "api_key", key: "hidden" }),
      logout: async () => {},
      refresh: async (options: unknown) => {
        refreshes.push(options);
        return { aborted: false, errors: new Map() };
      },
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));

    coordinator.start({ flowId: "flow-radius", providerId: "radius", method: "api_key" });
    await Bun.sleep(0);

    expect(refreshes).toHaveLength(1);
    expect(refreshes[0]).toMatchObject({
      allowNetwork: true,
      force: true,
      providers: ["radius"],
    });
    expect((refreshes[0] as { signal?: AbortSignal }).signal).toBeInstanceOf(AbortSignal);
    expect(events.at(-1)).toMatchObject({
      event: "auth.finished",
      payload: { outcome: "succeeded" },
    });
  });

  test("keeps a Radius flow cancelled when cancellation arrives during catalog refresh", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    let finishRefresh: ((value: { errors: Map<string, Error> }) => void) | undefined;
    const runtime = {
      login: async () => ({ type: "api_key", key: "hidden" }),
      logout: async () => {},
      refresh: async () => new Promise<{ errors: Map<string, Error> }>((resolve) => {
        finishRefresh = resolve;
      }),
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));

    coordinator.start({ flowId: "flow-radius-cancel", providerId: "radius", method: "api_key" });
    await Bun.sleep(0);
    coordinator.cancel("flow-radius-cancel");
    finishRefresh?.({ errors: new Map() });
    await Bun.sleep(0);

    expect(events.at(-1)).toMatchObject({
      event: "auth.finished",
      payload: { outcome: "cancelled" },
    });
  });

  test("cancels an active prompt and reports a cancelled flow", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    const runtime = {
      login: async (_providerId: string, _type: "oauth" | "api_key", interaction: any) => {
        await interaction.prompt({ type: "secret", message: "API key" });
        return { type: "api_key", key: "not-reached" };
      },
      logout: async () => {},
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));
    coordinator.start({ flowId: "flow-cancel", providerId: "anthropic", method: "api_key" });

    expect(coordinator.cancel("flow-cancel")).toEqual({ cancelRequested: true });
    await Bun.sleep(0);

    expect(events.some((event) => event.event === "auth.promptCancelled")).toBe(true);
    expect(events.at(-1)).toMatchObject({
      event: "auth.finished",
      payload: { flowId: "flow-cancel", outcome: "cancelled" },
    });
  });

  test("treats provider prompt cancellation as distinct from flow cancellation", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    const runtime = {
      login: async (_providerId: string, _type: "oauth" | "api_key", interaction: any) => {
        const promptAbort = new AbortController();
        const manualCode = interaction.prompt({
          type: "manual_code",
          message: "Paste the redirect URL",
          signal: promptAbort.signal,
        });
        interaction.notify({ type: "auth_url", url: "https://example.com/login" });
        promptAbort.abort();
        await expect(manualCode).rejects.toMatchObject({ name: "AbortError" });
        return { type: "oauth", access: "hidden", refresh: "hidden", expires: 1 };
      },
      logout: async () => {},
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));

    coordinator.start({ flowId: "flow-browser", providerId: "anthropic", method: "oauth" });
    await Bun.sleep(0);

    expect(events.some((event) => event.event === "auth.promptCancelled")).toBe(true);
    expect(events.at(-1)).toMatchObject({
      event: "auth.finished",
      payload: { flowId: "flow-browser", outcome: "succeeded" },
    });
  });

  test("logs out through the runtime and announces model availability changes", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    const loggedOut: string[] = [];
    const runtime = {
      login: async () => ({ type: "oauth" }),
      logout: async (providerId: string) => { loggedOut.push(providerId); },
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));

    await coordinator.logout("github-copilot");

    expect(loggedOut).toEqual(["github-copilot"]);
    expect(events).toEqual([{
      event: "models.changed",
      payload: { reason: "authentication", providerId: "github-copilot" },
    }]);
  });

  test("reports an actionable failure without exposing provider error details", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    const runtime = {
      login: async () => { throw new Error("secret provider response"); },
      logout: async () => {},
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));

    coordinator.start({ flowId: "flow-failed", providerId: "openai", method: "api_key" });
    await Bun.sleep(0);

    expect(events.at(-1)).toMatchObject({
      event: "auth.finished",
      payload: {
        outcome: "failed",
        error: {
          code: "login_failed",
          message: "Authentication could not be completed. Check your connection or credentials, then try again.",
        },
      },
    });
    expect(JSON.stringify(events)).not.toContain("secret provider response");
  });

  test("classifies network failures without exposing raw provider details", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    const runtime = {
      login: async () => { throw new Error("fetch failed: ECONNRESET secret-host.internal"); },
      logout: async () => {},
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));

    coordinator.start({ flowId: "flow-network", providerId: "openai", method: "oauth" });
    await Bun.sleep(0);

    expect(events.at(-1)).toMatchObject({
      event: "auth.finished",
      payload: {
        outcome: "failed",
        error: {
          code: "auth_network_failed",
          message: "Could not reach the authentication service. Check your connection and try again.",
        },
      },
    });
    expect(JSON.stringify(events)).not.toContain("secret-host.internal");
  });

  test("classifies invalid provider configuration without exposing its value", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    const runtime = {
      login: async () => { throw new Error("Invalid Azure OpenAI base URL: https://secret.invalid"); },
      logout: async () => {},
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));

    coordinator.start({
      flowId: "flow-configuration",
      providerId: "azure-openai-responses",
      method: "api_key",
    });
    await Bun.sleep(0);

    expect(events.at(-1)).toMatchObject({
      event: "auth.finished",
      payload: {
        outcome: "failed",
        error: {
          code: "auth_invalid_configuration",
          message: "The authentication settings are incomplete or invalid. Review them and try again.",
        },
      },
    });
    expect(JSON.stringify(events)).not.toContain("secret.invalid");
  });

  test("classifies a denied device authorization as rejected", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    const runtime = {
      login: async () => { throw new Error("Device authorization was denied by secret-account"); },
      logout: async () => {},
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));

    coordinator.start({ flowId: "flow-denied", providerId: "radius", method: "oauth" });
    await Bun.sleep(0);

    expect(events.at(-1)).toMatchObject({
      event: "auth.finished",
      payload: {
        outcome: "failed",
        error: {
          code: "auth_rejected",
          message: "The authentication service rejected these credentials. Review them and try again.",
        },
      },
    });
    expect(JSON.stringify(events)).not.toContain("secret-account");
  });

  test("classifies a device authorization timeout as expired", async () => {
    const events: ProviderAuthCoordinatorEvent[] = [];
    const runtime = {
      login: async () => { throw new Error("Device authorization timed out"); },
      logout: async () => {},
    };
    const coordinator = new ProviderAuthCoordinator(runtime, (event) => events.push(event));

    coordinator.start({ flowId: "flow-expired", providerId: "github-copilot", method: "oauth" });
    await Bun.sleep(0);

    expect(events.at(-1)).toMatchObject({
      event: "auth.finished",
      payload: {
        outcome: "failed",
        error: {
          code: "auth_expired",
          message: "The authentication request expired. Start again to get a new code.",
        },
      },
    });
  });
});
