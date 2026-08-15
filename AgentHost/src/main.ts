import packageMetadata from "../package.json";
import { extname, isAbsolute } from "node:path";
import { registerBunOAuthFlows } from "@earendil-works/pi-ai/bun-oauth";
import { getAgentDir, ModelRuntime } from "@earendil-works/pi-coding-agent";
import {
  flushRawStdout,
  takeOverStdout,
  writeRawStdout,
} from "../node_modules/@earendil-works/pi-coding-agent/dist/core/output-guard.js";
import {
  AgentSettingsCoordinator,
  agentDirectory,
  createAgentSettingsCoordinator,
  createAgentSettingsManager,
  type AgentSettingsPatch,
  type AgentTransport,
} from "./agent-settings.ts";
import {
  ExtensionPackagesCoordinator,
  createExtensionPackagesCoordinator,
  type ExtensionPackageScope,
} from "./extension-packages.ts";
import {
  ExtensionSettingsCoordinator,
  type ExtensionSettingsChange,
} from "./extension-settings.ts";
import {
  PROTOCOL_VERSION,
  PromptImagesError,
  createHostHelloRecord,
  encodeRecord,
  parsePromptImages,
  type HostRequest,
  type HostResponse,
} from "./protocol.ts";
import { createPiSessionHandle, type SessionProfile } from "./pi-session-handle.ts";
import { listAvailableModels } from "./model-catalog.ts";
import { modelRuntimeOptions } from "./model-runtime-options.ts";
import { installProviderAuthOverrides } from "./provider-auth-overrides.ts";
import { listProviderSnapshots } from "./provider-catalog.ts";
import {
  ProviderAuthCoordinator,
  ProviderAuthCoordinatorError,
} from "./provider-auth-coordinator.ts";
import { SessionCatalog } from "./session-catalog.ts";
import {
  SessionRegistry,
  SessionRegistryError,
  type SessionModelOption,
  type SessionThinkingLevel,
} from "./session-registry.ts";
import {
  AccessPolicyError,
  type AccessApprovalDecision,
  type AccessMode,
} from "./access-policy.ts";
import { inspectGitBranches } from "./git-branches.ts";

takeOverStdout();
registerBunOAuthFlows();

function writeHostRecord(record: unknown): void {
  writeRawStdout(encodeRecord(record));
}

const hostVersion = Bun.env.PI_WORK_HOST_VERSION ?? packageMetadata.version;
const piVersion = packageMetadata.dependencies["@earendil-works/pi-coding-agent"];
const sessionCatalog = new SessionCatalog();
let modelRuntimePromise: Promise<ModelRuntime> | undefined;
let providerAuthCoordinatorPromise: Promise<ProviderAuthCoordinator> | undefined;
let agentSettingsCoordinator: AgentSettingsCoordinator | undefined;
let extensionPackagesCoordinator: ExtensionPackagesCoordinator | undefined;
let extensionSettingsCoordinator: ExtensionSettingsCoordinator | undefined;
const sessionRegistry = new SessionRegistry((record) => {
  writeHostRecord({
    version: PROTOCOL_VERSION,
    kind: "event",
    ...record,
  });
});

class HostRequestError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

writeHostRecord(
  createHostHelloRecord({
    hostVersion,
    piVersion,
    capabilities: [
      "sessions.list",
      "models.list",
      "providers.list",
      "auth.start",
      "auth.respond",
      "auth.cancel",
      "auth.logout",
      "settings.get",
      "settings.update",
      "extensions.listInstalled",
      "extensions.install",
      "extensions.setEnabled",
      "extensions.update",
      "extensions.remove",
      "extensions.settings.list",
      "extensions.settings.update",
      "git.branches",
      "session.createDraft",
      "session.open",
      "session.exportHtml",
      "session.snapshot",
      "session.transcriptPage",
      "session.toolOutput",
      "session.commands",
      "session.rename",
      "session.setGitBranch",
      "session.setModel",
      "session.setThinkingLevel",
      "session.setModelOption",
      "session.setAccessMode",
      "session.resolveApproval",
      "session.prompt",
      "session.promptImages",
      "session.abort",
      "session.close",
      "session.delete",
    ],
  }),
);
await flushRawStdout();

async function handleRequest(request: HostRequest): Promise<HostResponse> {
  if (request.method === "settings.get") {
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: getAgentSettingsCoordinator().snapshot(),
    };
  }

  if (request.method === "settings.update") {
    const patch = parseAgentSettingsPatch(request.params?.patch);
    if (patch.defaultModel) {
      const model = (await getModelRuntime()).getModel(
        patch.defaultModel.provider,
        patch.defaultModel.modelId,
      );
      if (!model) {
        throw new HostRequestError(
          "model_not_found",
          `Model not found: ${patch.defaultModel.provider}/${patch.defaultModel.modelId}`,
        );
      }
    }
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: await getAgentSettingsCoordinator().update(patch),
    };
  }

  if (request.method === "extensions.listInstalled") {
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: await getExtensionPackagesCoordinator().list(),
    };
  }

  if (request.method === "extensions.install") {
    const source = parseCatalogExtensionSource(request.params);
    const snapshot = await getExtensionPackagesCoordinator().install(source);
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: {
        ...snapshot,
        reload: await sessionRegistry.reloadExtensions(),
      },
    };
  }

  if (request.method === "extensions.setEnabled") {
    const { source, scope } = parseExtensionPackageTarget(request.params);
    const enabled = request.params?.enabled;
    if (typeof enabled !== "boolean") {
      throw new Error("extensions.setEnabled requires a boolean enabled value");
    }
    const snapshot = await getExtensionPackagesCoordinator().setEnabled(
      source,
      scope,
      enabled,
    );
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: {
        ...snapshot,
        reload: await sessionRegistry.reloadExtensions(),
      },
    };
  }

  if (request.method === "extensions.update") {
    const { source } = parseExtensionPackageTarget(request.params);
    const snapshot = await getExtensionPackagesCoordinator().update(source);
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: {
        ...snapshot,
        reload: await sessionRegistry.reloadExtensions(),
      },
    };
  }

  if (request.method === "extensions.remove") {
    const { source, scope } = parseExtensionPackageTarget(request.params);
    const snapshot = await getExtensionPackagesCoordinator().remove(source, scope);
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: {
        ...snapshot,
        reload: await sessionRegistry.reloadExtensions(),
      },
    };
  }

  if (request.method === "extensions.settings.list") {
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: await getExtensionSettingsCoordinator().list(),
    };
  }

  if (request.method === "extensions.settings.update") {
    const { source, scope, changes } = parseExtensionSettingsUpdate(request.params);
    const settings = await getExtensionSettingsCoordinator().update(
      source,
      scope,
      changes,
    );
    await sessionRegistry.reloadExtensions();
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: settings,
    };
  }

  if (request.method === "sessions.list") {
    const cwd = request.params?.cwd;
    const sessionDirectory = request.params?.sessionDirectory;
    if (typeof cwd !== "string" || (sessionDirectory !== undefined && typeof sessionDirectory !== "string")) {
      throw new Error("sessions.list requires a string cwd and optional string sessionDirectory");
    }

    const sessions = await sessionCatalog.list(cwd, sessionDirectory);
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: { sessions },
    };
  }

  if (request.method === "git.branches") {
    const cwd = request.params?.cwd;
    if (typeof cwd !== "string") {
      throw new Error("git.branches requires a string cwd");
    }
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: await inspectGitBranches(cwd),
    };
  }

  if (request.method === "models.list") {
    const models = await listAvailableModels(await getModelRuntime());
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: { models },
    };
  }

  if (request.method === "providers.list") {
    const providers = await listProviderSnapshots(await getModelRuntime());
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: { providers },
    };
  }

  if (request.method === "auth.start") {
    const flowId = request.params?.flowId;
    const providerId = request.params?.providerId;
    const method = request.params?.method;
    if (
      typeof flowId !== "string"
      || typeof providerId !== "string"
      || (method !== "oauth" && method !== "api_key")
    ) {
      throw new Error("auth.start requires string flowId, providerId, and a valid method");
    }

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: (await getProviderAuthCoordinator()).start({ flowId, providerId, method }),
    };
  }

  if (request.method === "auth.respond") {
    const flowId = request.params?.flowId;
    const promptId = request.params?.promptId;
    const value = request.params?.value;
    if (typeof flowId !== "string" || typeof promptId !== "string" || typeof value !== "string") {
      throw new Error("auth.respond requires string flowId, promptId, and value");
    }

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: (await getProviderAuthCoordinator()).respond({ flowId, promptId, value }),
    };
  }

  if (request.method === "auth.cancel") {
    const flowId = request.params?.flowId;
    if (typeof flowId !== "string") {
      throw new Error("auth.cancel requires a string flowId");
    }

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: (await getProviderAuthCoordinator()).cancel(flowId),
    };
  }

  if (request.method === "auth.logout") {
    const providerId = request.params?.providerId;
    if (typeof providerId !== "string") {
      throw new Error("auth.logout requires a string providerId");
    }

    const runtime = await getModelRuntime();
    const before = (await listProviderSnapshots(runtime)).find((provider) => provider.id === providerId);
    if (!before) {
      throw new HostRequestError("provider_not_found", `Unknown provider: ${providerId}`);
    }
    await (await getProviderAuthCoordinator()).logout(providerId);
    const provider = (await listProviderSnapshots(runtime)).find((entry) => entry.id === providerId);
    if (!provider) {
      throw new HostRequestError("provider_not_found", `Unknown provider: ${providerId}`);
    }

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: {
        removed: before.status.canDisconnect,
        provider,
      },
    };
  }

  if (request.method === "session.createDraft") {
    const cwd = request.params?.cwd;
    const sessionDirectory = request.params?.sessionDirectory;
    const profile = request.params?.profile ?? "work";
    const accessMode = request.params?.accessMode;
    if (
      typeof cwd !== "string"
      || (sessionDirectory !== undefined && typeof sessionDirectory !== "string")
      || (profile !== "chat" && profile !== "work")
      || (accessMode !== undefined && !isAccessMode(accessMode))
    ) {
      throw new Error("session.createDraft requires a string cwd and optional string sessionDirectory");
    }

    await getExtensionPackagesCoordinator().list();
    const draft = sessionCatalog.createDraft(cwd, sessionDirectory);
    const handle = await createPiSessionHandle({
      sessionManager: draft.manager,
      profile: profile as SessionProfile,
      modelRuntime: await getModelRuntime(),
      accessMode: accessMode as AccessMode | undefined,
      agentDir: agentDirectory(Bun.env),
      settingsManager: createAgentSettingsManager(cwd, Bun.env),
    });
    sessionRegistry.register(handle);
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: { session: draft.summary },
    };
  }

  if (request.method === "session.open") {
    const path = request.params?.path;
    const sessionDirectory = request.params?.sessionDirectory;
    const profile = request.params?.profile;
    const accessMode = request.params?.accessMode;
    if (
      typeof path !== "string"
      || (sessionDirectory !== undefined && typeof sessionDirectory !== "string")
      || (profile !== "chat" && profile !== "work")
      || (accessMode !== undefined && !isAccessMode(accessMode))
    ) {
      throw new Error("session.open requires string path, optional sessionDirectory, and a valid profile");
    }

    await getExtensionPackagesCoordinator().list();
    const manager = sessionCatalog.open(path, sessionDirectory);
    const existing = sessionRegistry.descriptor(manager.getSessionId());
    if (existing) {
      return {
        version: PROTOCOL_VERSION,
        kind: "response",
        id: request.id,
        ok: true,
        result: {
          sessionId: existing.id,
          path: existing.path,
          cwd: existing.cwd,
        },
      };
    }
    const handle = await createPiSessionHandle({
      sessionManager: manager,
      profile,
      modelRuntime: await getModelRuntime(),
      accessMode: accessMode as AccessMode | undefined,
      agentDir: agentDirectory(Bun.env),
      settingsManager: createAgentSettingsManager(manager.getCwd(), Bun.env),
    });
    sessionRegistry.register(handle);
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: {
        sessionId: manager.getSessionId(),
        path: manager.getSessionFile(),
        cwd: manager.getCwd(),
      },
    };
  }

  if (request.method === "session.snapshot") {
    const sessionId = request.params?.sessionId;
    if (typeof sessionId !== "string") {
      throw new Error("session.snapshot requires a string sessionId");
    }

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: sessionRegistry.snapshot(sessionId),
    };
  }

  if (request.method === "session.exportHtml") {
    const sessionId = request.params?.sessionId;
    const path = request.params?.path;
    const sessionDirectory = request.params?.sessionDirectory;
    const profile = request.params?.profile;
    const outputPath = request.params?.outputPath;
    if (
      typeof sessionId !== "string"
      || typeof path !== "string"
      || (sessionDirectory !== undefined && typeof sessionDirectory !== "string")
      || (profile !== "chat" && profile !== "work")
      || typeof outputPath !== "string"
      || !isAbsolute(outputPath)
      || extname(outputPath).toLowerCase() !== ".html"
    ) {
      throw new Error(
        "session.exportHtml requires string sessionId/path, optional sessionDirectory, "
        + "a valid profile, and an absolute HTML outputPath",
      );
    }

    const existing = sessionRegistry.descriptor(sessionId);
    if (existing) {
      if (existing.path !== path) {
        throw new Error(`Session path does not match open session: ${sessionId}`);
      }
      return {
        version: PROTOCOL_VERSION,
        kind: "response",
        id: request.id,
        ok: true,
        result: await sessionRegistry.exportHtml(sessionId, outputPath),
      };
    }

    await getExtensionPackagesCoordinator().list();
    const manager = sessionCatalog.open(path, sessionDirectory);
    if (manager.getSessionId() !== sessionId) {
      throw new Error(`Session ID does not match file: ${sessionId}`);
    }
    const handle = await createPiSessionHandle({
      sessionManager: manager,
      profile,
      modelRuntime: await getModelRuntime(),
      agentDir: agentDirectory(Bun.env),
      settingsManager: createAgentSettingsManager(manager.getCwd(), Bun.env),
    });
    try {
      return {
        version: PROTOCOL_VERSION,
        kind: "response",
        id: request.id,
        ok: true,
        result: { sessionId, path: await handle.exportHtml(outputPath) },
      };
    } finally {
      handle.dispose();
    }
  }

  if (request.method === "session.transcriptPage") {
    const sessionId = request.params?.sessionId;
    const cursor = request.params?.cursor;
    const limit = request.params?.limit;
    if (
      typeof sessionId !== "string"
      || typeof cursor !== "string"
      || !Number.isSafeInteger(limit)
      || (limit as number) < 1
      || (limit as number) > 100
    ) {
      throw new Error(
        "session.transcriptPage requires string sessionId/cursor and an integer limit from 1 to 100",
      );
    }

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: sessionRegistry.transcriptPage(sessionId, cursor, limit as number),
    };
  }

  if (request.method === "session.toolOutput") {
    const sessionId = request.params?.sessionId;
    const toolCallId = request.params?.toolCallId;
    if (typeof sessionId !== "string" || typeof toolCallId !== "string") {
      throw new Error("session.toolOutput requires string sessionId and toolCallId");
    }
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: {
        sessionId,
        toolCallId,
        output: sessionRegistry.toolOutput(sessionId, toolCallId),
      },
    };
  }

  if (request.method === "session.rename") {
    const sessionId = request.params?.sessionId;
    const title = request.params?.title;
    if (typeof sessionId !== "string" || typeof title !== "string" || title.trim().length === 0) {
      throw new Error("session.rename requires a string sessionId and non-empty title");
    }

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: sessionRegistry.rename(sessionId, title.trim()),
    };
  }

  if (request.method === "session.setGitBranch") {
    const sessionId = request.params?.sessionId;
    const branch = request.params?.branch;
    if (typeof sessionId !== "string" || typeof branch !== "string" || !branch.trim()) {
      throw new Error("session.setGitBranch requires a string sessionId and non-empty branch");
    }
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: sessionRegistry.setGitBranch(sessionId, branch),
    };
  }

  if (request.method === "session.commands") {
    const sessionId = request.params?.sessionId;
    if (typeof sessionId !== "string") {
      throw new Error("session.commands requires a string sessionId");
    }
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: { commands: sessionRegistry.commands(sessionId) },
    };
  }

  if (request.method === "session.setModel") {
    const sessionId = request.params?.sessionId;
    const provider = request.params?.provider;
    const modelId = request.params?.modelId;
    if (typeof sessionId !== "string" || typeof provider !== "string" || typeof modelId !== "string") {
      throw new Error("session.setModel requires string sessionId, provider, and modelId");
    }

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: await sessionRegistry.setModel(sessionId, provider, modelId),
    };
  }

  if (request.method === "session.setThinkingLevel") {
    const sessionId = request.params?.sessionId;
    const thinkingLevel = request.params?.thinkingLevel;
    if (typeof sessionId !== "string" || !isThinkingLevel(thinkingLevel)) {
      throw new Error(
        "session.setThinkingLevel requires a string sessionId and valid thinkingLevel",
      );
    }

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: sessionRegistry.setThinkingLevel(sessionId, thinkingLevel),
    };
  }

  if (request.method === "session.setModelOption") {
    const sessionId = request.params?.sessionId;
    const option = request.params?.option;
    const enabled = request.params?.enabled;
    if (typeof sessionId !== "string" || !isModelOption(option) || typeof enabled !== "boolean") {
      throw new Error(
        "session.setModelOption requires a string sessionId, valid option, and boolean enabled",
      );
    }

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: await sessionRegistry.setModelOption(sessionId, option, enabled),
    };
  }

  if (request.method === "session.setAccessMode") {
    const sessionId = request.params?.sessionId;
    const accessMode = request.params?.accessMode;
    if (typeof sessionId !== "string" || !isAccessMode(accessMode) || accessMode === "none") {
      throw new Error("session.setAccessMode requires a string sessionId and a Work access mode");
    }

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: sessionRegistry.setAccessMode(sessionId, accessMode),
    };
  }

  if (request.method === "session.resolveApproval") {
    const sessionId = request.params?.sessionId;
    const requestId = request.params?.requestId;
    const decision = request.params?.decision;
    if (
      typeof sessionId !== "string"
      || typeof requestId !== "string"
      || !isApprovalDecision(decision)
    ) {
      throw new Error(
        "session.resolveApproval requires string sessionId, requestId, and a valid decision",
      );
    }

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: sessionRegistry.resolveApproval(sessionId, requestId, decision),
    };
  }

  if (request.method === "session.prompt") {
    const sessionId = request.params?.sessionId;
    const turnId = request.params?.turnId;
    const text = request.params?.text;
    if (typeof sessionId !== "string" || typeof turnId !== "string" || typeof text !== "string") {
      throw new Error("session.prompt requires string sessionId, turnId, and text");
    }
    const images = parsePromptImages(request.params?.images);

    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: sessionRegistry.prompt(sessionId, turnId, text, images),
    };
  }

  if (request.method === "session.abort") {
    const sessionId = request.params?.sessionId;
    if (typeof sessionId !== "string") {
      throw new Error("session.abort requires a string sessionId");
    }

    await sessionRegistry.abort(sessionId);
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: { aborted: true, sessionId },
    };
  }

  if (request.method === "session.close") {
    const sessionId = request.params?.sessionId;
    if (typeof sessionId !== "string") {
      throw new Error("session.close requires a string sessionId");
    }

    sessionRegistry.close(sessionId);
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: { closed: true, sessionId },
    };
  }

  if (request.method === "session.delete") {
    const sessionId = request.params?.sessionId;
    const cwd = request.params?.cwd;
    const sessionDirectory = request.params?.sessionDirectory;
    if (
      typeof sessionId !== "string"
      || typeof cwd !== "string"
      || (sessionDirectory !== undefined && typeof sessionDirectory !== "string")
    ) {
      throw new Error(
        "session.delete requires string sessionId, cwd, and optional sessionDirectory",
      );
    }

    const openSession = sessionRegistry.descriptor(sessionId);
    if (openSession && openSession.cwd !== cwd) {
      throw new Error(`Session does not belong to cwd: ${cwd}`);
    }
    if (openSession) sessionRegistry.close(sessionId);
    await sessionCatalog.delete(sessionId, cwd, sessionDirectory, openSession);
    return {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request.id,
      ok: true,
      result: { deleted: true, sessionId },
    };
  }

  throw new HostRequestError("method_not_found", `Unsupported method: ${request.method}`);
}

function getModelRuntime(): Promise<ModelRuntime> {
  modelRuntimePromise ??= ModelRuntime.create(modelRuntimeOptions(Bun.env)).then((runtime) => {
    installProviderAuthOverrides(runtime);
    return runtime;
  });
  return modelRuntimePromise;
}

function getProviderAuthCoordinator(): Promise<ProviderAuthCoordinator> {
  providerAuthCoordinatorPromise ??= getModelRuntime().then((runtime) => (
    new ProviderAuthCoordinator(runtime, (event) => {
      writeHostRecord({
        version: PROTOCOL_VERSION,
        kind: "event",
        ...event,
      });
    })
  ));
  return providerAuthCoordinatorPromise;
}

function getAgentSettingsCoordinator(): AgentSettingsCoordinator {
  agentSettingsCoordinator ??= createAgentSettingsCoordinator(
    Bun.env.HOME ?? process.cwd(),
    Bun.env,
  );
  return agentSettingsCoordinator;
}

function getExtensionPackagesCoordinator(): ExtensionPackagesCoordinator {
  extensionPackagesCoordinator ??= createExtensionPackagesCoordinator(
    Bun.env.HOME ?? process.cwd(),
    Bun.env,
  );
  return extensionPackagesCoordinator;
}

function getExtensionSettingsCoordinator(): ExtensionSettingsCoordinator {
  extensionSettingsCoordinator ??= new ExtensionSettingsCoordinator(
    agentDirectory(Bun.env) ?? getAgentDir(),
    () => getExtensionPackagesCoordinator().list(),
  );
  return extensionSettingsCoordinator;
}

function parseExtensionPackageTarget(
  params: Record<string, unknown> | undefined,
): { source: string; scope: ExtensionPackageScope } {
  const source = params?.source;
  const scope = params?.scope;
  if (typeof source !== "string" || source.trim().length === 0) {
    throw new Error("Extension package source must be a non-empty string");
  }
  if (scope !== "user" && scope !== "project") {
    throw new Error("Extension package scope must be user or project");
  }
  return { source, scope };
}

function parseExtensionSettingsUpdate(
  params: Record<string, unknown> | undefined,
): {
  source: string;
  scope: ExtensionPackageScope;
  changes: ExtensionSettingsChange[];
} {
  const { source, scope } = parseExtensionPackageTarget(params);
  const rawChanges = params?.changes;
  if (!Array.isArray(rawChanges) || rawChanges.length === 0) {
    throw new Error("extensions.settings.update requires at least one change");
  }
  const changes = rawChanges.map((raw): ExtensionSettingsChange => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw new Error("Each extension setting change must be an object");
    }
    const path = "path" in raw ? raw.path : undefined;
    const operation = "operation" in raw ? raw.operation : undefined;
    const value = "value" in raw ? raw.value : undefined;
    if (typeof path !== "string" || !path.startsWith("/") || path.length < 2) {
      throw new Error("Each extension setting change requires a JSON Pointer path");
    }
    if (operation === "remove") {
      if (value !== undefined) {
        throw new Error("A remove setting change must not include a value");
      }
      return { path, operation };
    }
    if (operation !== "set" || typeof value !== "string") {
      throw new Error("A set setting change requires a string value");
    }
    return { path, operation, value };
  });
  return { source, scope, changes };
}

function parseCatalogExtensionSource(
  params: Record<string, unknown> | undefined,
): string {
  const source = params?.source;
  if (typeof source !== "string"
    || !/^npm:(?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*$/i.test(source)) {
    throw new Error("Catalog extensions must use an npm source");
  }
  return source;
}

function isAccessMode(value: unknown): value is AccessMode {
  return value === "none" || value === "readOnly" || value === "ask" || value === "full";
}

function isThinkingLevel(value: unknown): value is SessionThinkingLevel {
  return value === "off"
    || value === "minimal"
    || value === "low"
    || value === "medium"
    || value === "high"
    || value === "xhigh"
    || value === "max";
}

function parseAgentSettingsPatch(value: unknown): AgentSettingsPatch {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("settings.update requires a settings patch object");
  }
  const raw = value as Record<string, unknown>;
  const patch: AgentSettingsPatch = {};
  if (raw.defaultModel !== undefined) {
    if (!raw.defaultModel || typeof raw.defaultModel !== "object" || Array.isArray(raw.defaultModel)) {
      throw new Error("defaultModel must contain provider and modelId");
    }
    const model = raw.defaultModel as Record<string, unknown>;
    if (typeof model.provider !== "string" || typeof model.modelId !== "string") {
      throw new Error("defaultModel must contain provider and modelId");
    }
    patch.defaultModel = { provider: model.provider, modelId: model.modelId };
  }
  if (raw.defaultThinkingLevel !== undefined) {
    if (!isThinkingLevel(raw.defaultThinkingLevel)) {
      throw new Error("defaultThinkingLevel is invalid");
    }
    patch.defaultThinkingLevel = raw.defaultThinkingLevel;
  }
  if (raw.transport !== undefined) {
    if (!isTransport(raw.transport)) throw new Error("transport is invalid");
    patch.transport = raw.transport;
  }
  if (raw.compactionEnabled !== undefined) {
    if (typeof raw.compactionEnabled !== "boolean") {
      throw new Error("compactionEnabled must be a boolean");
    }
    patch.compactionEnabled = raw.compactionEnabled;
  }
  if (raw.retryEnabled !== undefined) {
    if (typeof raw.retryEnabled !== "boolean") {
      throw new Error("retryEnabled must be a boolean");
    }
    patch.retryEnabled = raw.retryEnabled;
  }
  return patch;
}

function isTransport(value: unknown): value is AgentTransport {
  return value === "auto"
    || value === "sse"
    || value === "websocket"
    || value === "websocket-cached";
}

function isModelOption(value: unknown): value is SessionModelOption {
  return value === "fastMode" || value === "oneMillionContext";
}

function isApprovalDecision(value: unknown): value is AccessApprovalDecision {
  return value === "allowOnce" || value === "deny";
}

async function handleLine(line: string): Promise<void> {
  if (line.length === 0) return;

  let request: HostRequest | undefined;
  try {
    request = JSON.parse(line) as HostRequest;
    if (request.version !== PROTOCOL_VERSION || request.kind !== "request" || typeof request.id !== "string") {
      throw new Error("Invalid protocol request");
    }

    writeHostRecord(await handleRequest(request));
  } catch (error) {
    const response: HostResponse = {
      version: PROTOCOL_VERSION,
      kind: "response",
      id: request?.id ?? "",
      ok: false,
      error: {
        code: error instanceof HostRequestError
          || error instanceof PromptImagesError
          || error instanceof SessionRegistryError
          || error instanceof AccessPolicyError
          || error instanceof ProviderAuthCoordinatorError
          ? error.code
          : "invalid_request",
        message: error instanceof Error ? error.message : String(error),
      },
    };
    writeHostRecord(response);
  }
}

const decoder = new TextDecoder();
let inputBuffer = "";

for await (const chunk of Bun.stdin.stream()) {
  inputBuffer += decoder.decode(chunk, { stream: true });

  let newlineIndex = inputBuffer.indexOf("\n");
  while (newlineIndex >= 0) {
    let line = inputBuffer.slice(0, newlineIndex);
    inputBuffer = inputBuffer.slice(newlineIndex + 1);
    if (line.endsWith("\r")) line = line.slice(0, -1);
    await handleLine(line);
    newlineIndex = inputBuffer.indexOf("\n");
  }
}

sessionRegistry.closeAll();
await flushRawStdout();
