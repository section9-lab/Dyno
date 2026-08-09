import type {
  AccessApprovalDecision,
  AccessApprovalRequest,
  AccessMode,
} from "./access-policy.ts";

export type SessionHandleEvent =
  | {
      type: "textDelta";
      delta: string;
    }
  | {
      type: "toolStarted";
      toolCallId: string;
      toolName: string;
      summary: string;
    }
  | {
      type: "toolUpdated";
      toolCallId: string;
      toolName: string;
      output: string;
    }
  | {
      type: "toolCompleted";
      toolCallId: string;
      toolName: string;
      output: string;
      isError: boolean;
    }
  | {
      type: "approvalRequested";
      approval: AccessApprovalRequest;
    };

export type SessionModel = {
  provider: string;
  id: string;
  name: string;
  contextWindow: number;
  maxTokens: number;
  reasoning: boolean;
  supportsImages: boolean;
  supportsFastMode: boolean;
};

export type SessionContextUsage = {
  tokens: number | null;
  contextWindow: number;
  percent: number | null;
};

export type SessionThinkingLevel =
  | "off"
  | "minimal"
  | "low"
  | "medium"
  | "high"
  | "xhigh"
  | "max";

export type SessionThinkingState = {
  thinkingLevel: SessionThinkingLevel;
  availableThinkingLevels: SessionThinkingLevel[];
};

export type SessionModelOption = "fastMode" | "oneMillionContext";

export type SessionModelOptionState = {
  supported: boolean;
  enabled: boolean;
};

export type SessionModelOptions = {
  fastMode: SessionModelOptionState;
  oneMillionContext: SessionModelOptionState;
};

export type SessionModelOptionSelection = {
  model: SessionModel;
  contextUsage?: SessionContextUsage;
  modelOptions: SessionModelOptions;
};

export type SessionMessageContent =
  | { type: "text"; text: string }
  | { type: "image"; mimeType: string }
  | { type: "toolCall"; id: string; name: string; argumentsSummary: string };

export type SessionMessage = {
  id: string;
  role: "user" | "assistant" | "tool" | "system";
  content: SessionMessageContent[];
  timestamp: string;
  provider?: string;
  model?: string;
  stopReason?: string;
  errorMessage?: string;
  toolCallId?: string;
  toolName?: string;
  isError?: boolean;
};

export type SessionSlashCommand = {
  name: string;
  description?: string;
  source: "extension" | "skill";
};

export type SessionHandleSnapshot = {
  session: {
    id: string;
    path: string;
    cwd: string;
    title: string;
  };
  messages: SessionMessage[];
  gitBranch?: string;
  model: SessionModel | null;
  contextUsage?: SessionContextUsage;
  thinkingLevel: SessionThinkingLevel;
  availableThinkingLevels: SessionThinkingLevel[];
  modelOptions: SessionModelOptions;
  accessMode: AccessMode;
  pendingApprovals: AccessApprovalRequest[];
};

export type SessionSnapshot = SessionHandleSnapshot & {
  state: "running" | "idle";
  sequence: number;
  turnId: string | null;
};

export interface SessionHandle {
  readonly sessionId: string;
  snapshot(): SessionHandleSnapshot;
  contextUsage(): SessionContextUsage | undefined;
  commands(): SessionSlashCommand[];
  rename(title: string): string;
  setGitBranch(branch: string): string;
  setModel(provider: string, modelId: string): Promise<SessionModel>;
  setThinkingLevel(level: SessionThinkingLevel): SessionThinkingState;
  setModelOption(
    option: SessionModelOption,
    enabled: boolean,
  ): Promise<SessionModelOptionSelection>;
  setAccessMode(mode: AccessMode): AccessMode;
  resolveApproval(requestId: string, decision: AccessApprovalDecision): void;
  prompt(text: string): Promise<void>;
  abort(): Promise<void>;
  reload(): Promise<void>;
  dispose(): void;
  subscribe(listener: (event: SessionHandleEvent) => void): () => void;
}

export type SessionRegistryEvent =
  | {
      event: "session.stateChanged";
      payload: {
        sessionId: string;
        sequence: number;
        turnId: string;
        state: "running" | "idle";
        contextUsage?: SessionContextUsage;
      };
    }
  | {
      event: "session.error";
      payload: {
        sessionId: string;
        sequence: number;
        turnId: string;
        code: "agent_error";
        message: string;
      };
    }
  | {
      event: "session.messageDelta";
      payload: {
        sessionId: string;
        sequence: number;
        turnId: string;
        delta: string;
      };
    }
  | {
      event: "session.toolStarted";
      payload: {
        sessionId: string;
        sequence: number;
        turnId: string;
        toolCallId: string;
        toolName: string;
        summary: string;
      };
    }
  | {
      event: "session.toolUpdated";
      payload: {
        sessionId: string;
        sequence: number;
        turnId: string;
        toolCallId: string;
        toolName: string;
        output: string;
      };
    }
  | {
      event: "session.toolCompleted";
      payload: {
        sessionId: string;
        sequence: number;
        turnId: string;
        toolCallId: string;
        toolName: string;
        output: string;
        isError: boolean;
      };
    }
  | {
      event: "session.approvalRequested";
      payload: {
        sessionId: string;
        sequence: number;
        turnId: string;
        requestId: string;
        toolCallId: string;
        toolName: string;
        summary: string;
      };
    };

export type PromptAccepted = {
  accepted: true;
  sessionId: string;
  turnId: string;
};

export class SessionRegistryError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

type ManagedSession = {
  handle: SessionHandle;
  sequence: number;
  activeTurnId?: string;
  reloadPending: boolean;
  reloading: boolean;
  unsubscribe: () => void;
  closed: boolean;
};

export class SessionRegistry {
  private readonly sessions = new Map<string, ManagedSession>();

  constructor(private readonly emit: (event: SessionRegistryEvent) => void) {}

  register(handle: SessionHandle): void {
    if (this.sessions.has(handle.sessionId)) {
      handle.dispose();
      throw new SessionRegistryError(
        "session_already_open",
        `Session is already open: ${handle.sessionId}`,
      );
    }
    const managed: ManagedSession = {
      handle,
      sequence: 0,
      reloadPending: false,
      reloading: false,
      unsubscribe: () => {},
      closed: false,
    };
    managed.unsubscribe = handle.subscribe((event) => this.consume(managed, event));
    this.sessions.set(handle.sessionId, managed);
  }

  snapshot(sessionId: string): SessionSnapshot {
    const managed = this.requireSession(sessionId);
    return {
      ...managed.handle.snapshot(),
      state: managed.activeTurnId ? "running" : "idle",
      sequence: managed.sequence,
      turnId: managed.activeTurnId ?? null,
    };
  }

  descriptor(sessionId: string): SessionHandleSnapshot["session"] | undefined {
    return this.sessions.get(sessionId)?.handle.snapshot().session;
  }

  commands(sessionId: string): SessionSlashCommand[] {
    return this.requireSession(sessionId).handle.commands();
  }

  rename(sessionId: string, title: string): { sessionId: string; title: string } {
    const managed = this.requireSession(sessionId);
    return { sessionId, title: managed.handle.rename(title) };
  }

  setGitBranch(
    sessionId: string,
    branch: string,
  ): { sessionId: string; branch: string } {
    const managed = this.requireSession(sessionId);
    return { sessionId, branch: managed.handle.setGitBranch(branch) };
  }

  async setModel(
    sessionId: string,
    provider: string,
    modelId: string,
  ): Promise<{
    sessionId: string;
    model: SessionModel;
    contextUsage?: SessionContextUsage;
    modelOptions: SessionModelOptions;
  } & SessionThinkingState> {
    const managed = this.requireSession(sessionId);
    const model = await managed.handle.setModel(provider, modelId);
    const snapshot = managed.handle.snapshot();
    return {
      sessionId,
      model,
      ...(snapshot.contextUsage ? { contextUsage: snapshot.contextUsage } : {}),
      thinkingLevel: snapshot.thinkingLevel,
      availableThinkingLevels: snapshot.availableThinkingLevels,
      modelOptions: snapshot.modelOptions,
    };
  }

  setThinkingLevel(
    sessionId: string,
    level: SessionThinkingLevel,
  ): { sessionId: string } & SessionThinkingState {
    const managed = this.requireSession(sessionId);
    return { sessionId, ...managed.handle.setThinkingLevel(level) };
  }

  async setModelOption(
    sessionId: string,
    option: SessionModelOption,
    enabled: boolean,
  ): Promise<{ sessionId: string } & SessionModelOptionSelection> {
    const managed = this.requireSession(sessionId);
    return {
      sessionId,
      ...await managed.handle.setModelOption(option, enabled),
    };
  }

  setAccessMode(
    sessionId: string,
    mode: AccessMode,
  ): { sessionId: string; accessMode: AccessMode } {
    const managed = this.requireSession(sessionId);
    return { sessionId, accessMode: managed.handle.setAccessMode(mode) };
  }

  resolveApproval(
    sessionId: string,
    requestId: string,
    decision: AccessApprovalDecision,
  ): { sessionId: string; requestId: string; decision: AccessApprovalDecision } {
    const managed = this.requireSession(sessionId);
    managed.handle.resolveApproval(requestId, decision);
    return { sessionId, requestId, decision };
  }

  prompt(sessionId: string, turnId: string, text: string): PromptAccepted {
    const managed = this.sessions.get(sessionId);
    if (!managed) {
      throw new SessionRegistryError("session_not_found", `Session not found: ${sessionId}`);
    }
    if (managed.activeTurnId || managed.reloading) {
      throw new SessionRegistryError("session_busy", `Session is already running: ${sessionId}`);
    }

    managed.activeTurnId = turnId;
    this.emitState(managed, turnId, "running");
    void managed.handle.prompt(text).then(async () => {
      if (managed.closed) return;
      managed.activeTurnId = undefined;
      if (managed.reloadPending) await this.reloadPendingSession(managed);
      if (managed.closed) return;
      this.emitState(managed, turnId, "idle");
    }).catch((error: unknown) => {
      if (managed.closed) return;
      managed.activeTurnId = undefined;
      managed.sequence += 1;
      this.emit({
        event: "session.error",
        payload: {
          sessionId,
          sequence: managed.sequence,
          turnId,
          code: "agent_error",
          message: error instanceof Error ? error.message : String(error),
        },
      });
    });

    return { accepted: true, sessionId, turnId };
  }

  async abort(sessionId: string): Promise<void> {
    const managed = this.sessions.get(sessionId);
    if (!managed) throw new Error(`Session not found: ${sessionId}`);
    await managed.handle.abort();
  }

  async reloadExtensions(): Promise<{ reloaded: string[]; deferred: string[] }> {
    const reloaded: string[] = [];
    const deferred: string[] = [];
    for (const managed of this.sessions.values()) {
      if (managed.activeTurnId || managed.reloading) {
        managed.reloadPending = true;
        deferred.push(managed.handle.sessionId);
        continue;
      }
      await this.reloadSession(managed);
      reloaded.push(managed.handle.sessionId);
    }
    return { reloaded, deferred };
  }

  close(sessionId: string): void {
    const managed = this.requireSession(sessionId);
    managed.closed = true;
    managed.unsubscribe();
    managed.handle.dispose();
    this.sessions.delete(sessionId);
  }

  private async reloadPendingSession(managed: ManagedSession): Promise<void> {
    while (managed.reloadPending && !managed.closed) {
      managed.reloadPending = false;
      await this.reloadSession(managed);
    }
  }

  private async reloadSession(managed: ManagedSession): Promise<void> {
    managed.reloading = true;
    try {
      await managed.handle.reload();
    } finally {
      managed.reloading = false;
    }
  }

  closeAll(): void {
    for (const sessionId of Array.from(this.sessions.keys())) {
      this.close(sessionId);
    }
  }

  private consume(managed: ManagedSession, event: SessionHandleEvent): void {
    const turnId = managed.activeTurnId;
    if (!turnId) return;

    if (event.type === "textDelta") {
      managed.sequence += 1;
      this.emit({
        event: "session.messageDelta",
        payload: {
          sessionId: managed.handle.sessionId,
          sequence: managed.sequence,
          turnId,
          delta: event.delta,
        },
      });
      return;
    }

    if (event.type === "toolStarted") {
      managed.sequence += 1;
      this.emit({
        event: "session.toolStarted",
        payload: {
          sessionId: managed.handle.sessionId,
          sequence: managed.sequence,
          turnId,
          toolCallId: event.toolCallId,
          toolName: event.toolName,
          summary: event.summary,
        },
      });
      return;
    }

    if (event.type === "toolUpdated") {
      managed.sequence += 1;
      this.emit({
        event: "session.toolUpdated",
        payload: {
          sessionId: managed.handle.sessionId,
          sequence: managed.sequence,
          turnId,
          toolCallId: event.toolCallId,
          toolName: event.toolName,
          output: event.output,
        },
      });
      return;
    }

    if (event.type === "toolCompleted") {
      managed.sequence += 1;
      this.emit({
        event: "session.toolCompleted",
        payload: {
          sessionId: managed.handle.sessionId,
          sequence: managed.sequence,
          turnId,
          toolCallId: event.toolCallId,
          toolName: event.toolName,
          output: event.output,
          isError: event.isError,
        },
      });
      return;
    }

    if (event.type === "approvalRequested") {
      managed.sequence += 1;
      this.emit({
        event: "session.approvalRequested",
        payload: {
          sessionId: managed.handle.sessionId,
          sequence: managed.sequence,
          turnId,
          requestId: event.approval.id,
          toolCallId: event.approval.toolCallId,
          toolName: event.approval.toolName,
          summary: event.approval.summary,
        },
      });
    }
  }

  private emitState(
    managed: ManagedSession,
    turnId: string,
    state: "running" | "idle",
  ): void {
    managed.sequence += 1;
    const contextUsage = state === "idle" ? managed.handle.contextUsage() : undefined;
    this.emit({
      event: "session.stateChanged",
      payload: {
        sessionId: managed.handle.sessionId,
        sequence: managed.sequence,
        turnId,
        state,
        ...(contextUsage ? { contextUsage } : {}),
      },
    });
  }

  private requireSession(sessionId: string): ManagedSession {
    const managed = this.sessions.get(sessionId);
    if (!managed) {
      throw new SessionRegistryError("session_not_found", `Session not found: ${sessionId}`);
    }
    return managed;
  }
}
