import {
  DefaultPackageManager,
  getAgentDir,
  type PackageManager,
} from "@earendil-works/pi-coding-agent";

import {
  agentDirectory,
  createAgentSettingsManager,
} from "./agent-settings.ts";

export type ExtensionPackageScope = "user" | "project";

export type InstalledExtensionPackage = {
  source: string;
  scope: ExtensionPackageScope;
  filtered: boolean;
  installedPath?: string;
  enabled: boolean;
};

export type InstalledExtensionPackagesSnapshot = {
  packages: InstalledExtensionPackage[];
};

export type ExtensionPackageManager = Pick<
  PackageManager,
  | "listConfiguredPackages"
  | "resolve"
  | "installAndPersist"
  | "update"
  | "removeAndPersist"
>;

type ExtensionPackageSource = string | {
  source: string;
  extensions?: string[];
  skills?: string[];
  prompts?: string[];
  themes?: string[];
};

export type ExtensionPackageSettings = {
  getPackages(scope: ExtensionPackageScope): ExtensionPackageSource[];
  setPackages(scope: ExtensionPackageScope, packages: ExtensionPackageSource[]): void;
  flush(): Promise<void>;
};

export class ExtensionPackagesCoordinator {
  constructor(
    private readonly packageManager: ExtensionPackageManager,
    private readonly settings?: ExtensionPackageSettings,
  ) {}

  async list(): Promise<InstalledExtensionPackagesSnapshot> {
    const configured = this.packageManager.listConfiguredPackages();
    const resolved = await this.packageManager.resolve(async () => "skip");

    return {
      packages: configured.flatMap((pkg) => {
        const resources = resolved.extensions.filter((resource) => (
          resource.metadata.origin === "package"
          && resource.metadata.source === pkg.source
          && resource.metadata.scope === pkg.scope
        ));
        if (resources.length === 0) return [];

        return [{
          source: pkg.source,
          scope: pkg.scope,
          filtered: pkg.filtered,
          installedPath: pkg.installedPath,
          enabled: resources.some((resource) => resource.enabled),
        }];
      }).sort((left, right) => left.source.localeCompare(right.source)),
    };
  }

  async install(source: string): Promise<InstalledExtensionPackagesSnapshot> {
    await this.packageManager.installAndPersist(source, { local: false });
    return this.list();
  }

  async setEnabled(
    source: string,
    scope: ExtensionPackageScope,
    enabled: boolean,
  ): Promise<InstalledExtensionPackagesSnapshot> {
    if (!this.settings) throw new Error("Extension package settings are unavailable");
    const packages = this.settings.getPackages(scope);
    const index = packages.findIndex((pkg) => (
      (typeof pkg === "string" ? pkg : pkg.source) === source
    ));
    if (index < 0) throw new Error(`No matching extension package found: ${source}`);

    const next = [...packages];
    next[index] = enabled
      ? source
      : {
          source,
          extensions: [],
          skills: [],
          prompts: [],
          themes: [],
        };
    this.settings.setPackages(scope, next);
    await this.settings.flush();
    return this.list();
  }

  async update(source: string): Promise<InstalledExtensionPackagesSnapshot> {
    await this.packageManager.update(source);
    return this.list();
  }

  async remove(
    source: string,
    scope: ExtensionPackageScope,
  ): Promise<InstalledExtensionPackagesSnapshot> {
    const removed = await this.packageManager.removeAndPersist(source, {
      local: scope === "project",
    });
    if (!removed) throw new Error(`No matching extension package found: ${source}`);
    return this.list();
  }
}

export function createExtensionPackagesCoordinator(
  cwd: string,
  environment: Record<string, string | undefined>,
): ExtensionPackagesCoordinator {
  const resolvedAgentDirectory = agentDirectory(environment) ?? getAgentDir();
  const settingsManager = createAgentSettingsManager(cwd, environment);
  return new ExtensionPackagesCoordinator(
    new DefaultPackageManager({
      cwd,
      agentDir: resolvedAgentDirectory,
      settingsManager,
    }),
    {
      getPackages: (scope) => (
        scope === "user"
          ? settingsManager.getGlobalSettings().packages ?? []
          : settingsManager.getProjectSettings().packages ?? []
      ),
      setPackages: (scope, packages) => {
        if (scope === "user") settingsManager.setPackages(packages);
        else settingsManager.setProjectPackages(packages);
      },
      flush: () => settingsManager.flush(),
    },
  );
}
