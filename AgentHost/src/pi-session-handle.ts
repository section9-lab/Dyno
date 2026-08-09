import {
  createAgentSession,
  type AgentSession,
  type AgentSessionEvent,
  type CreateAgentSessionOptions,
  type ModelRuntime,
  type SessionManager,
  type SettingsManager,
} from "@earendil-works/pi-coding-agent";

import {
  AccessController,
  activeToolsForMode,
  createPolicyControlledTools,
  type AccessApprovalDecision,
  type AccessMode,
} from "./access-policy.ts";
import {
  SessionRegistryError,
  type SessionHandle,
  type SessionHandleEvent,
  type SessionHandleSnapshot,
  type SessionContextUsage,
  type SessionMessage,
  type SessionMessageContent,
  type SessionModel,
  type SessionModelOption,
  type SessionModelOptions,
  type SessionModelOptionSelection,
  type SessionSlashCommand,
  type SessionThinkingLevel,
  type SessionThinkingState,
} from "./session-registry.ts";
import { normalizeModel, supportsFastMode } from "./model-catalog.ts";
import { webFetchTool } from "./web-fetch-tool.ts";

type PiAgentSession = Pick<
  AgentSession,
  | "sessionId"
  | "messages"
  | "model"
  | "getContextUsage"
  | "thinkingLevel"
  | "setModel"
  | "setThinkingLevel"
  | "getAvailableThinkingLevels"
  | "getAllTools"
  | "setActiveToolsByName"
  | "extensionRunner"
  | "resourceLoader"
  | "prompt"
  | "abort"
  | "reload"
  | "dispose"
  | "subscribe"
> & {
  agent: Pick<AgentSession["agent"], "streamFunction">;
  modelRuntime: Pick<ModelRuntime, "getModel">;
};
type CreateSession = (options: CreateAgentSessionOptions) => Promise<{ session: PiAgentSession }>;

type PiModel = NonNullable<AgentSession["model"]>;

const oneMillionContextWindow = 1_050_000;
const gitBranchEntryType = "pi-work.git-branch";

function selectedGitBranch(sessionManager: SessionManager): string | undefined {
  const entries = sessionManager.getEntries();
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const entry = entries[index];
    if (entry.type !== "custom" || entry.customType !== gitBranchEntryType) continue;
    const data = entry.data;
    if (!data || typeof data !== "object" || !("branch" in data)) continue;
    const branch = (data as { branch?: unknown }).branch;
    if (typeof branch === "string" && branch.length > 0) return branch;
  }
  return undefined;
}

function oneMillionContextConfiguration(
  model: PiModel | undefined,
): { shortContextWindow: number; longContextWindow: number } | undefined {
  if (!model || model.provider !== "openai" || model.api !== "openai-responses") {
    return undefined;
  }
  const shortContextTier = model.cost.tiers?.find((tier) => (
    tier.inputTokensAbove > 0 && tier.inputTokensAbove < oneMillionContextWindow
  ));
  if (!shortContextTier) return undefined;
  return {
    shortContextWindow: shortContextTier.inputTokensAbove,
    longContextWindow: oneMillionContextWindow,
  };
}

export type SessionProfile = "chat" | "work";

export async function createPiSessionHandle(
  options: {
    sessionManager: SessionManager;
    profile: SessionProfile;
    modelRuntime?: ModelRuntime;
    accessMode?: AccessMode;
    agentDir?: string;
    settingsManager?: SettingsManager;
  },
  createSession: CreateSession = createAgentSession,
): Promise<PiSessionHandle> {
  const createOptions: CreateAgentSessionOptions = {
    cwd: options.sessionManager.getCwd(),
    sessionManager: options.sessionManager,
    modelRuntime: options.modelRuntime,
    agentDir: options.agentDir,
    settingsManager: options.settingsManager,
  };
  const accessMode: AccessMode = options.profile === "chat"
    ? "none"
    : (options.accessMode ?? "ask");
  const accessController = new AccessController({
    cwd: options.sessionManager.getCwd(),
    mode: accessMode,
  });
  if (options.profile === "chat") {
    createOptions.tools = [webFetchTool.name];
    createOptions.customTools = [webFetchTool];
  } else {
    createOptions.customTools = [
      ...createPolicyControlledTools(
        options.sessionManager.getCwd(),
        accessController,
      ),
      webFetchTool,
    ];
  }

  const { session } = await createSession(createOptions);
  const extensionToolNames = options.profile === "work"
    ? session.getAllTools()
      .filter(({ sourceInfo }) => sourceInfo.source !== "builtin" && sourceInfo.source !== "sdk")
      .map(({ name }) => name)
    : [];
  const alwaysActiveToolNames = [webFetchTool.name, ...extensionToolNames];
  session.setActiveToolsByName([
    ...activeToolsForMode(accessMode),
    ...alwaysActiveToolNames,
  ]);
  return new PiSessionHandle(
    session,
    options.sessionManager,
    accessController,
    [webFetchTool.name],
    options.profile === "work",
  );
}

export class PiSessionHandle implements SessionHandle {
  private fastModeEnabled = false;

  constructor(
    private readonly session: PiAgentSession,
    private readonly sessionManager: SessionManager,
    private readonly accessController = new AccessController({
      cwd: sessionManager.getCwd(),
      mode: "full",
    }),
    private readonly alwaysActiveToolNames: readonly string[] = [],
    private readonly includeExtensionTools = false,
  ) {
    const streamFunction = session.agent.streamFunction;
    session.agent.streamFunction = (model, context, streamOptions) => {
      const branch = selectedGitBranch(this.sessionManager);
      const nextContext = branch
        ? {
            ...context,
            systemPrompt: `${context.systemPrompt}\n\nThe user selected ${JSON.stringify(branch)} as this session's target Git branch in pi-work. You are responsible for checking and managing the Git working state.`,
          }
        : context;
      if (!supportsFastMode(model)) {
        return streamFunction(model, nextContext, streamOptions);
      }
      const options = {
        ...streamOptions,
        serviceTier: this.fastModeEnabled ? "priority" : "default",
      };
      return streamFunction(model, nextContext, options);
    };
  }

  get sessionId(): string {
    return this.session.sessionId;
  }

  snapshot(): SessionHandleSnapshot {
    const messages = normalizeAgentMessages(this.sessionId, this.session.messages);
    const explicitTitle = this.sessionManager.getSessionName()?.trim();
    const firstUserText = messages.find((message) => message.role === "user")?.content
      .filter((content): content is Extract<SessionMessageContent, { type: "text" }> => (
        content.type === "text"
      ))
      .map((content) => content.text)
      .join(" ")
      .trim();

    const contextUsage = this.contextUsage();
    const gitBranch = selectedGitBranch(this.sessionManager);
    return {
      session: {
        id: this.sessionId,
        path: this.sessionManager.getSessionFile() ?? "",
        cwd: this.sessionManager.getCwd(),
        title: explicitTitle || firstUserText || "New Session",
      },
      messages,
      ...(gitBranch ? { gitBranch } : {}),
      model: this.session.model ? normalizeModel(this.session.model) : null,
      ...(contextUsage ? { contextUsage } : {}),
      thinkingLevel: this.session.thinkingLevel,
      availableThinkingLevels: this.session.getAvailableThinkingLevels(),
      modelOptions: this.modelOptions(),
      accessMode: this.accessController.mode,
      pendingApprovals: this.accessController.pendingApprovals(),
    };
  }

  contextUsage(): SessionContextUsage | undefined {
    const usage = this.session.getContextUsage();
    if (!usage) return undefined;
    return {
      tokens: usage.tokens,
      contextWindow: usage.contextWindow,
      percent: usage.percent,
    };
  }

  commands(): SessionSlashCommand[] {
    const extensions = this.session.extensionRunner.getRegisteredCommands().map((command) => ({
      name: command.invocationName,
      description: command.description,
      source: "extension" as const,
    }));
    const skills = this.session.resourceLoader.getSkills().skills.map((skill) => ({
      name: `skill:${skill.name}`,
      description: skill.description,
      source: "skill" as const,
    }));
    return [...extensions, ...skills];
  }

  rename(title: string): string {
    this.sessionManager.appendSessionInfo(title);
    return title;
  }

  setGitBranch(branch: string): string {
    const selectedBranch = branch.trim();
    if (!selectedBranch) {
      throw new SessionRegistryError("git_branch_invalid", "Git branch cannot be empty");
    }
    if (normalizeAgentMessages(this.sessionId, this.session.messages).length > 0) {
      throw new SessionRegistryError(
        "git_branch_locked",
        "Git branch can only be selected before the conversation starts",
      );
    }
    this.sessionManager.appendCustomEntry(gitBranchEntryType, { branch: selectedBranch });
    return selectedBranch;
  }

  async setModel(provider: string, modelId: string): Promise<SessionModel> {
    const model = this.session.modelRuntime.getModel(provider, modelId);
    if (!model) {
      throw new SessionRegistryError(
        "model_not_found",
        `Model not found: ${provider}/${modelId}`,
      );
    }
    try {
      await this.session.setModel(model);
    } catch (error) {
      throw new SessionRegistryError(
        "model_unavailable",
        error instanceof Error ? error.message : String(error),
      );
    }
    this.fastModeEnabled = false;
    return normalizeModel(model);
  }

  setThinkingLevel(level: SessionThinkingLevel): SessionThinkingState {
    this.session.setThinkingLevel(level);
    return {
      thinkingLevel: this.session.thinkingLevel,
      availableThinkingLevels: this.session.getAvailableThinkingLevels(),
    };
  }

  async setModelOption(
    option: SessionModelOption,
    enabled: boolean,
  ): Promise<SessionModelOptionSelection> {
    if (option === "fastMode") {
      if (!supportsFastMode(this.session.model)) {
        throw new SessionRegistryError(
          "model_option_unsupported",
          "The selected model does not support Fast mode",
        );
      }
      this.fastModeEnabled = enabled;
      return this.modelOptionSelection();
    }

    const configuration = oneMillionContextConfiguration(this.session.model);
    if (!configuration || !this.session.model) {
      throw new SessionRegistryError(
        "model_option_unsupported",
        "The selected model does not support a 1M context window",
      );
    }
    const model: PiModel = {
      ...this.session.model,
      contextWindow: enabled
        ? configuration.longContextWindow
        : configuration.shortContextWindow,
    };
    try {
      await this.session.setModel(model);
    } catch (error) {
      throw new SessionRegistryError(
        "model_unavailable",
        error instanceof Error ? error.message : String(error),
      );
    }
    return this.modelOptionSelection();
  }

  private modelOptions(): SessionModelOptions {
    const model = this.session.model;
    const contextConfiguration = oneMillionContextConfiguration(model);
    return {
      fastMode: {
        supported: supportsFastMode(model),
        enabled: supportsFastMode(model) && this.fastModeEnabled,
      },
      oneMillionContext: {
        supported: contextConfiguration !== undefined,
        enabled: contextConfiguration !== undefined
          && (model?.contextWindow ?? 0) >= contextConfiguration.longContextWindow,
      },
    };
  }

  private modelOptionSelection(): SessionModelOptionSelection {
    const model = this.session.model;
    if (!model) {
      throw new SessionRegistryError("model_unavailable", "No model is selected");
    }
    const contextUsage = this.contextUsage();
    return {
      model: normalizeModel(model),
      ...(contextUsage ? { contextUsage } : {}),
      modelOptions: this.modelOptions(),
    };
  }

  setAccessMode(mode: AccessMode): AccessMode {
    this.accessController.setMode(mode);
    this.refreshActiveTools();
    return mode;
  }

  resolveApproval(requestId: string, decision: AccessApprovalDecision): void {
    this.accessController.resolve(requestId, decision);
  }

  async prompt(text: string): Promise<void> {
    await this.session.prompt(text);
    const lastMessage = this.session.messages.at(-1);
    if (lastMessage?.role === "assistant" && lastMessage.stopReason === "error") {
      throw new Error(lastMessage.errorMessage || "Model request failed");
    }
  }

  abort(): Promise<void> {
    this.accessController.cancelAll();
    return this.session.abort();
  }

  async reload(): Promise<void> {
    await this.session.reload();
    this.refreshActiveTools();
  }

  dispose(): void {
    this.accessController.cancelAll();
    this.session.dispose();
  }

  subscribe(listener: (event: SessionHandleEvent) => void): () => void {
    const unsubscribeSession = this.session.subscribe((event) => {
      const normalized = normalizeAgentSessionEvent(event);
      if (normalized) listener(normalized);
    });
    const unsubscribeApprovals = this.accessController.subscribe((approval) => {
      listener({ type: "approvalRequested", approval });
    });
    return () => {
      unsubscribeSession();
      unsubscribeApprovals();
    };
  }

  private refreshActiveTools(): void {
    const extensionToolNames = this.includeExtensionTools
      ? this.session.getAllTools()
        .filter(({ sourceInfo }) => sourceInfo.source !== "builtin" && sourceInfo.source !== "sdk")
        .map(({ name }) => name)
      : [];
    this.session.setActiveToolsByName([
      ...activeToolsForMode(this.accessController.mode),
      ...this.alwaysActiveToolNames,
      ...extensionToolNames,
    ]);
  }
}

export function normalizeAgentMessages(
  sessionId: string,
  messages: ReadonlyArray<AgentSession["messages"][number]>,
): SessionMessage[] {
  return messages.flatMap((message, index): SessionMessage[] => {
    const timestampValue = Number.isFinite(message.timestamp) ? message.timestamp : 0;
    const base = {
      id: `${sessionId}:${timestampValue}:${index}`,
      timestamp: new Date(timestampValue).toISOString(),
    };

    if (message.role === "user") {
      return [{
        ...base,
        role: "user",
        content: normalizeContent(message.content),
      }];
    }

    if (message.role === "assistant") {
      return [{
        ...base,
        role: "assistant",
        content: normalizeContent(message.content),
        provider: message.provider,
        model: message.model,
        stopReason: message.stopReason,
        ...(message.errorMessage ? { errorMessage: message.errorMessage } : {}),
      }];
    }

    if (message.role === "toolResult") {
      return [{
        ...base,
        role: "tool",
        content: normalizeToolResultContent(message.content),
        toolCallId: message.toolCallId,
        toolName: message.toolName,
        isError: message.isError,
      }];
    }

    if (message.role === "custom") {
      if (!message.display) return [];
      return [{
        ...base,
        role: "system",
        content: normalizeContent(message.content),
      }];
    }

    if (message.role === "bashExecution") {
      const output = message.output ? `\n${message.output}` : "";
      return [{
        ...base,
        role: "system",
        content: [{ type: "text", text: `$ ${message.command}${output}` }],
      }];
    }

    if (message.role === "branchSummary" || message.role === "compactionSummary") {
      return [{
        ...base,
        role: "system",
        content: [{ type: "text", text: message.summary }],
      }];
    }

    return [];
  });
}

function normalizeContent(content: unknown): SessionMessageContent[] {
  if (typeof content === "string") return [{ type: "text", text: content }];
  if (!Array.isArray(content)) return [];

  return content.flatMap((item): SessionMessageContent[] => {
    if (!item || typeof item !== "object" || !("type" in item)) return [];
    if (item.type === "text" && "text" in item && typeof item.text === "string") {
      return [{ type: "text", text: item.text }];
    }
    if (item.type === "image" && "mimeType" in item && typeof item.mimeType === "string") {
      return [{ type: "image", mimeType: item.mimeType }];
    }
    if (
      item.type === "toolCall"
      && "id" in item
      && typeof item.id === "string"
      && "name" in item
      && typeof item.name === "string"
    ) {
      return [{
        type: "toolCall",
        id: item.id,
        name: item.name,
        argumentsSummary: safeJSONStringify("arguments" in item ? item.arguments : {}),
      }];
    }
    return [];
  });
}

function normalizeToolResultContent(content: unknown): SessionMessageContent[] {
  return normalizeContent(content).map((item) => {
    if (item.type !== "text") return item;
    return { ...item, text: stripTerminalFormatting(item.text) };
  });
}

function safeJSONStringify(value: unknown): string {
  try {
    return JSON.stringify(value) ?? "{}";
  } catch {
    return "{}";
  }
}

export function normalizeAgentSessionEvent(event: AgentSessionEvent): SessionHandleEvent | undefined {
  if (
    event.type === "message_update"
    && event.assistantMessageEvent.type === "text_delta"
  ) {
    return {
      type: "textDelta",
      delta: event.assistantMessageEvent.delta,
    };
  }

  if (event.type === "tool_execution_start") {
    return {
      type: "toolStarted",
      toolCallId: event.toolCallId,
      toolName: event.toolName,
      summary: JSON.stringify(event.args),
    };
  }

  if (event.type === "tool_execution_update") {
    return {
      type: "toolUpdated",
      toolCallId: event.toolCallId,
      toolName: event.toolName,
      output: normalizeToolOutput(event.partialResult),
    };
  }

  if (event.type === "tool_execution_end") {
    return {
      type: "toolCompleted",
      toolCallId: event.toolCallId,
      toolName: event.toolName,
      output: normalizeToolOutput(event.result),
      isError: event.isError,
    };
  }

  return undefined;
}

function normalizeToolOutput(result: unknown): string {
  if (result && typeof result === "object" && "content" in result) {
    const content = normalizeContent(result.content);
    const text = content.map((item) => {
      if (item.type === "text") return item.text;
      if (item.type === "image") return `[image · ${item.mimeType}]`;
      return `${item.name} ${item.argumentsSummary}`;
    }).join("\n");
    if (text) return stripTerminalFormatting(text);
  }
  return stripTerminalFormatting(safeJSONStringify(result));
}

function stripTerminalFormatting(value: string): string {
  return value
    .replace(/\u001B(?:\][^\u0007]*(?:\u0007|\u001B\\)|\[[0-?]*[ -/]*[@-~])/g, "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n");
}
