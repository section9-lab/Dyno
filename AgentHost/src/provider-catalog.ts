export type ProviderAuthMethod = {
  type: "oauth" | "api_key";
  name: string;
  loginLabel?: string;
};

export type ProviderAuthSource =
  | "stored"
  | "runtime"
  | "environment"
  | "fallback"
  | "models_json_key"
  | "models_json_command";

export type ProviderSnapshot = {
  id: string;
  name: string;
  methods: ProviderAuthMethod[];
  status: {
    configured: boolean;
    source: ProviderAuthSource | null;
    credentialType: "oauth" | "api_key" | null;
    canDisconnect: boolean;
    label?: string;
  };
  models: {
    total: number;
    available: number;
  };
};

type CatalogProvider = {
  id: string;
  name: string;
  auth: {
    oauth?: { name: string; loginLabel?: string; login: unknown };
    apiKey?: { name: string; login?: unknown };
  };
};

type ProviderCatalogRuntime = {
  getProviders(): readonly CatalogProvider[];
  listCredentials(): Promise<readonly {
    providerId: string;
    type: "oauth" | "api_key";
  }[]>;
  getProviderAuthStatus(providerId: string): {
    configured: boolean;
    source?: ProviderAuthSource;
    label?: string;
  };
  getModels(providerId?: string): readonly { provider: string }[];
  getAvailableSnapshot(): readonly { provider: string }[];
};

export async function listProviderSnapshots(
  runtime: ProviderCatalogRuntime,
): Promise<ProviderSnapshot[]> {
  const credentials = new Map(
    (await runtime.listCredentials()).map((entry) => [entry.providerId, entry.type]),
  );
  const available = runtime.getAvailableSnapshot();

  return runtime.getProviders().map((provider) => {
    const status = runtime.getProviderAuthStatus(provider.id);
    const credentialType = credentials.get(provider.id) ?? null;
    const methods: ProviderAuthMethod[] = [];

    if (provider.auth.oauth) {
      methods.push({
        type: "oauth",
        name: provider.auth.oauth.name,
        ...(provider.auth.oauth.loginLabel
          ? { loginLabel: provider.auth.oauth.loginLabel }
          : {}),
      });
    }
    if (provider.auth.apiKey?.login) {
      methods.push({ type: "api_key", name: provider.auth.apiKey.name });
    }

    return {
      id: provider.id,
      name: provider.name,
      methods,
      status: {
        configured: status.configured,
        source: status.source ?? null,
        credentialType,
        canDisconnect: status.source === "stored" && credentialType !== null,
        ...(status.label ? { label: status.label } : {}),
      },
      models: {
        total: runtime.getModels(provider.id).length,
        available: available.filter((model) => model.provider === provider.id).length,
      },
    };
  });
}
