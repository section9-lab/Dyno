import { describe, expect, test } from "bun:test";
import type { AuthPrompt, Provider } from "@earendil-works/pi-ai";

import { installProviderAuthOverrides } from "../src/provider-auth-overrides.ts";

function provider(id: string): Provider {
  return {
    id,
    name: id,
    auth: {
      apiKey: {
        name: `${id} auth`,
        login: async () => ({ type: "api_key" }),
        resolve: async ({ credential }) => credential
          ? { auth: { apiKey: credential.key }, env: credential.env, source: "stored credential" }
          : undefined,
      },
    },
    getModels: () => [],
    stream: (() => { throw new Error("not used"); }) as Provider["stream"],
    streamSimple: (() => { throw new Error("not used"); }) as Provider["streamSimple"],
  };
}

function runtimeWith(...providers: Provider[]) {
  const current = new Map(providers.map((item) => [item.id, item]));
  const registered: Provider[] = [];
  return {
    current,
    registered,
    getProvider: (providerId: string) => current.get(providerId),
    registerNativeProvider: (value: Provider) => {
      registered.push(value);
      current.set(value.id, value);
    },
  };
}

function interaction(responses: string[], prompts: AuthPrompt[]) {
  return {
    signal: new AbortController().signal,
    prompt: async (prompt: AuthPrompt) => {
      prompts.push(prompt);
      return responses.shift() ?? "";
    },
    notify: () => {},
  };
}

describe("provider authentication overrides", () => {
  test("stores the Azure API key with its resource endpoint", async () => {
    const runtime = runtimeWith(provider("azure-openai-responses"));
    installProviderAuthOverrides(runtime);

    const prompts: AuthPrompt[] = [];
    const login = runtime.current.get("azure-openai-responses")?.auth.apiKey?.login;
    const credential = await login?.(interaction([
      "azure-secret",
      "https://example-resource.openai.azure.com",
    ], prompts));

    expect(prompts.map((prompt) => prompt.type)).toEqual(["secret", "text"]);
    expect(credential).toEqual({
      type: "api_key",
      key: "azure-secret",
      env: { AZURE_OPENAI_BASE_URL: "https://example-resource.openai.azure.com" },
    });
  });

  test("rejects an insecure Azure resource endpoint before storing credentials", async () => {
    const runtime = runtimeWith(provider("azure-openai-responses"));
    installProviderAuthOverrides(runtime);

    const login = runtime.current.get("azure-openai-responses")?.auth.apiKey?.login;
    await expect(login?.(interaction([
      "azure-secret",
      "http://example-resource.openai.azure.com",
    ], []))).rejects.toThrow("Invalid Azure OpenAI resource URL");
  });

  test("persists the default AWS profile for the Bedrock credential chain", async () => {
    const original = provider("amazon-bedrock");
    const originalLogin = original.auth.apiKey?.login;
    if (original.auth.apiKey && originalLogin) {
      original.auth.apiKey.login = async (value) => {
        await value.prompt({
          type: "text",
          message: "Configure AWS credentials, then press Enter to continue",
        });
        return { type: "api_key" };
      };
    }
    const runtime = runtimeWith(original);
    installProviderAuthOverrides(runtime);

    const prompts: AuthPrompt[] = [];
    const login = runtime.current.get("amazon-bedrock")?.auth.apiKey?.login;
    const credential = await login?.(interaction([""], prompts));

    expect(prompts).toHaveLength(1);
    expect(credential).toEqual({
      type: "api_key",
      env: { AWS_PROFILE: "default" },
    });
  });

  test("preserves an ambient AWS credential chain without forcing the default profile", async () => {
    const original = provider("amazon-bedrock");
    const originalLogin = original.auth.apiKey?.login;
    if (original.auth.apiKey && originalLogin) {
      original.auth.apiKey.login = async (value) => {
        await value.prompt({
          type: "text",
          message: "Configure AWS credentials, then press Enter to continue",
        });
        return { type: "api_key" };
      };
    }
    const runtime = runtimeWith(original);
    installProviderAuthOverrides(runtime, {
      AWS_WEB_IDENTITY_TOKEN_FILE: "/var/run/secrets/aws-token",
    });

    const login = runtime.current.get("amazon-bedrock")?.auth.apiKey?.login;
    const credential = await login?.(interaction([""], []));

    expect(credential).toEqual({ type: "api_key" });
  });
});
