import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

export type PiWebAccessConfiguration = {
  provider: "auto" | "duckduckgo";
  workflow: "auto-summary" | "none";
};

export const defaultPiWebAccessConfiguration: PiWebAccessConfiguration = {
  provider: "auto",
  workflow: "auto-summary",
};

const defaultConfigurationFile = {
  ...defaultPiWebAccessConfiguration,
  fetchRouting: { allowRemoteHostedProviders: false },
};

export class PiWebAccessSettingsCoordinator {
  private readonly path: string;

  constructor(agentDirectory: string) {
    this.path = join(agentDirectory, "web-search.json");
  }

  async get(): Promise<PiWebAccessConfiguration> {
    const configuration = await this.readOrCreate();
    return {
      provider: configuration.provider === "duckduckgo" ? "duckduckgo" : "auto",
      workflow: configuration.workflow === "none" ? "none" : "auto-summary",
    };
  }

  async update(
    patch: Partial<PiWebAccessConfiguration>,
  ): Promise<PiWebAccessConfiguration> {
    const configuration = await this.readOrCreate();
    const next = {
      ...configuration,
      ...patch,
    };
    await this.write(next);
    return this.get();
  }

  private async readOrCreate(): Promise<Record<string, unknown>> {
    try {
      const raw = JSON.parse(await readFile(this.path, "utf8"));
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
        throw new Error("pi-web-access configuration must be a JSON object");
      }
      return raw as Record<string, unknown>;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      await this.write(defaultConfigurationFile);
      return { ...defaultConfigurationFile };
    }
  }

  private async write(configuration: Record<string, unknown>): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true });
    await writeFile(this.path, `${JSON.stringify(configuration, null, 2)}\n`, "utf8");
  }
}
