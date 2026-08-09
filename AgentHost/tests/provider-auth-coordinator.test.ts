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
});
