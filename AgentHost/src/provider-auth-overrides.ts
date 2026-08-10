import type {
  ApiKeyCredential,
  Provider,
  ProviderAuthInteraction,
} from "@earendil-works/pi-ai";

type ProviderRegistrationRuntime = {
  getProvider(providerId: string): Provider | undefined;
  registerNativeProvider(provider: Provider): void;
};

type ProviderEnvironment = Record<string, string | undefined>;

export function installProviderAuthOverrides(
  runtime: ProviderRegistrationRuntime,
  environment: ProviderEnvironment = Bun.env,
): void {
  installAzureOpenAIOverride(runtime);
  installAmazonBedrockOverride(runtime, environment);
}

function installAzureOpenAIOverride(runtime: ProviderRegistrationRuntime): void {
  const provider = runtime.getProvider("azure-openai-responses");
  const apiKey = provider?.auth.apiKey;
  if (!provider || !apiKey) return;

  runtime.registerNativeProvider({
    ...provider,
    auth: {
      ...provider.auth,
      apiKey: {
        ...apiKey,
        login: azureOpenAILogin,
      },
    },
  });
}

async function azureOpenAILogin(
  interaction: ProviderAuthInteraction,
): Promise<ApiKeyCredential> {
  interaction.signal.throwIfAborted();
  const key = (await interaction.prompt({
    type: "secret",
    message: "Enter Azure OpenAI API key",
  })).trim();
  interaction.signal.throwIfAborted();
  const baseURL = normalizeAzureOpenAIBaseURL(await interaction.prompt({
    type: "text",
    message: "Enter Azure OpenAI resource URL",
    placeholder: "https://your-resource.openai.azure.com",
  }));
  interaction.signal.throwIfAborted();
  return {
    type: "api_key",
    key,
    env: { AZURE_OPENAI_BASE_URL: baseURL },
  };
}

function normalizeAzureOpenAIBaseURL(value: string): string {
  const trimmed = value.trim();
  try {
    const url = new URL(trimmed);
    if (url.protocol !== "https:" || !url.hostname || url.username || url.password) {
      throw new Error();
    }
    url.hash = "";
    return url.toString().replace(/\/+$/u, "");
  } catch {
    throw new Error("Invalid Azure OpenAI resource URL");
  }
}

function installAmazonBedrockOverride(
  runtime: ProviderRegistrationRuntime,
  environment: ProviderEnvironment,
): void {
  const provider = runtime.getProvider("amazon-bedrock");
  const apiKey = provider?.auth.apiKey;
  const login = apiKey?.login;
  if (!provider || !apiKey || !login) return;

  runtime.registerNativeProvider({
    ...provider,
    auth: {
      ...provider.auth,
      apiKey: {
        ...apiKey,
        login: async (interaction) => {
          const credential = await login(interaction);
          if (
            credential.key
            || credential.env?.AWS_PROFILE
            || hasAmbientAmazonBedrockCredentials(environment)
          ) return credential;
          return {
            ...credential,
            env: {
              ...credential.env,
              AWS_PROFILE: "default",
            },
          };
        },
      },
    },
  });
}

function hasAmbientAmazonBedrockCredentials(environment: ProviderEnvironment): boolean {
  return Boolean(
    environment.AWS_BEARER_TOKEN_BEDROCK
    || environment.AWS_PROFILE
    || (environment.AWS_ACCESS_KEY_ID && environment.AWS_SECRET_ACCESS_KEY)
    || environment.AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
    || environment.AWS_CONTAINER_CREDENTIALS_FULL_URI
    || environment.AWS_WEB_IDENTITY_TOKEN_FILE,
  );
}
