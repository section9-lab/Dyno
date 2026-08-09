import { describe, expect, test } from "bun:test";

import {
  SessionRegistry,
  SessionRegistryError,
  type SessionHandle,
  type SessionHandleEvent,
  type SessionModelOption,
  type SessionModelOptions,
  type SessionRegistryEvent,
  type SessionThinkingLevel,
} from "../src/session-registry.ts";

class ControllableSession implements SessionHandle {
  readonly prompts: string[] = [];
  abortCount = 0;
  disposeCount = 0;
  reloadCount = 0;
  title = "New Session";
  gitBranch: string | undefined;
  accessMode: "none" | "readOnly" | "ask" | "full" = "ask";
  thinkingLevel: SessionThinkingLevel = "high";
  availableThinkingLevels: SessionThinkingLevel[] = ["off", "low", "high", "max"];
  modelOptions: SessionModelOptions = {
    fastMode: { supported: true, enabled: false },
    oneMillionContext: { supported: true, enabled: false },
  };
  readonly approvalResolutions: Array<{ requestId: string; decision: "allowOnce" | "deny" }> = [];
  selectedModel = {
    provider: "openai",
    id: "gpt-test",
    name: "GPT Test",
    contextWindow: 128_000,
    maxTokens: 16_384,
    reasoning: true,
    supportsImages: true,
    supportsFastMode: false,
  };
  currentContextUsage = {
    tokens: 32_000,
    contextWindow: 128_000,
    percent: 25,
  };
  readonly availableCommands = [
    {
      name: "review",
      description: "Review the current changes",
      source: "extension" as const,
    },
    {
      name: "skill:ego-browser",
      description: "Browse and interact with websites",
      source: "skill" as const,
    },
  ];

  private finishPrompt: (() => void) | undefined;
  private rejectPrompt: ((error: Error) => void) | undefined;
  private readonly listeners = new Set<(event: SessionHandleEvent) => void>();

  get listenerCount(): number {
    return this.listeners.size;
  }

  constructor(readonly sessionId: string) {}

  snapshot() {
    return {
      session: {
        id: this.sessionId,
        path: `/tmp/${this.sessionId}.jsonl`,
        cwd: "/tmp/project",
        title: this.title,
      },
      messages: [{
        id: "message-one",
        role: "user" as const,
        content: [{ type: "text" as const, text: "Hello" }],
        timestamp: "2026-08-09T00:00:00.000Z",
      }],
      ...(this.gitBranch ? { gitBranch: this.gitBranch } : {}),
      model: this.selectedModel,
      contextUsage: this.currentContextUsage,
      thinkingLevel: this.thinkingLevel,
      availableThinkingLevels: this.availableThinkingLevels,
      modelOptions: this.modelOptions,
      accessMode: this.accessMode,
      pendingApprovals: [],
    };
  }

  contextUsage() {
    return this.currentContextUsage;
  }

  commands() {
    return this.availableCommands;
  }

  rename(title: string): string {
    this.title = title;
    return title;
  }

  setGitBranch(branch: string): string {
    this.gitBranch = branch;
    return branch;
  }

  async setModel(provider: string, modelId: string) {
    this.selectedModel = {
      ...this.selectedModel,
      provider,
      id: modelId,
      name: modelId,
    };
    return this.selectedModel;
  }

  setThinkingLevel(level: SessionThinkingLevel) {
    this.thinkingLevel = level;
    return {
      thinkingLevel: this.thinkingLevel,
      availableThinkingLevels: this.availableThinkingLevels,
    };
  }

  async setModelOption(option: SessionModelOption, enabled: boolean) {
    this.modelOptions = {
      ...this.modelOptions,
      [option]: { supported: true, enabled },
    };
    return {
      model: this.selectedModel,
      contextUsage: this.currentContextUsage,
      modelOptions: this.modelOptions,
    };
  }

  setAccessMode(mode: "none" | "readOnly" | "ask" | "full") {
    this.accessMode = mode;
    return mode;
  }

  resolveApproval(requestId: string, decision: "allowOnce" | "deny"): void {
    this.approvalResolutions.push({ requestId, decision });
  }

  prompt(text: string): Promise<void> {
    this.prompts.push(text);
    return new Promise((resolve, reject) => {
      this.finishPrompt = resolve;
      this.rejectPrompt = reject;
    });
  }

  async abort(): Promise<void> {
    this.abortCount += 1;
  }

  async reload(): Promise<void> {
    this.reloadCount += 1;
  }

  dispose(): void {
    this.disposeCount += 1;
  }

  subscribe(listener: (event: SessionHandleEvent) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  settle(): void {
    this.finishPrompt?.();
  }

  fail(error: Error): void {
    this.rejectPrompt?.(error);
  }

  emitText(delta: string): void {
    for (const listener of this.listeners) listener({ type: "textDelta", delta });
  }

  emitToolStarted(): void {
    for (const listener of this.listeners) {
      listener({
        type: "toolStarted",
        toolCallId: "tool-one",
        toolName: "read",
        summary: '{"path":"README.md"}',
      });
    }
  }

  emitToolUpdated(): void {
    for (const listener of this.listeners) {
      listener({
        type: "toolUpdated",
        toolCallId: "tool-one",
        toolName: "read",
        output: "First line",
      });
    }
  }

  emitToolCompleted(): void {
    for (const listener of this.listeners) {
      listener({
        type: "toolCompleted",
        toolCallId: "tool-one",
        toolName: "read",
        output: "README contents",
        isError: false,
      });
    }
  }

  emitApprovalRequested(): void {
    for (const listener of this.listeners) {
      listener({
        type: "approvalRequested",
        approval: {
          id: "approval-one",
          toolCallId: "tool-one",
          toolName: "bash",
          summary: "bun test",
        },
      });
    }
  }
}

describe("SessionRegistry", () => {
  test("returns slash commands for the requested live session", () => {
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry(() => {});
    registry.register(session);

    expect(registry.commands("session-one")).toEqual(session.availableCommands);
  });

  test("returns a normalized idle snapshot with the current sequence", () => {
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry(() => {});
    registry.register(session);

    expect(registry.snapshot("session-one")).toEqual({
      session: {
        id: "session-one",
        path: "/tmp/session-one.jsonl",
        cwd: "/tmp/project",
        title: "New Session",
      },
      messages: [{
        id: "message-one",
        role: "user",
        content: [{ type: "text", text: "Hello" }],
        timestamp: "2026-08-09T00:00:00.000Z",
      }],
      state: "idle",
      sequence: 0,
      turnId: null,
      model: session.selectedModel,
      contextUsage: session.currentContextUsage,
      thinkingLevel: "high",
      availableThinkingLevels: ["off", "low", "high", "max"],
      modelOptions: session.modelOptions,
      accessMode: "ask",
      pendingApprovals: [],
    });
  });

  test("includes the active turn in a running snapshot", () => {
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry(() => {});
    registry.register(session);
    registry.prompt("session-one", "turn-one", "Build the feature");

    expect(registry.snapshot("session-one")).toMatchObject({
      state: "running",
      sequence: 1,
      turnId: "turn-one",
    });
  });

  test("persists a renamed session title through its handle", () => {
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry(() => {});
    registry.register(session);

    expect(registry.rename("session-one", "Session integration")).toEqual({
      sessionId: "session-one",
      title: "Session integration",
    });
    expect(session.title).toBe("Session integration");
  });

  test("persists a selected Git branch through its handle", () => {
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry(() => {});
    registry.register(session);

    expect(registry.setGitBranch("session-one", "feature/session-picker")).toEqual({
      sessionId: "session-one",
      branch: "feature/session-picker",
    });
    expect(registry.snapshot("session-one").gitBranch).toBe("feature/session-picker");
  });

  test("sets a model only on the requested session", async () => {
    const first = new ControllableSession("session-one");
    const second = new ControllableSession("session-two");
    const registry = new SessionRegistry(() => {});
    registry.register(first);
    registry.register(second);

    const result = await registry.setModel("session-two", "anthropic", "claude-test");

    expect(result).toEqual({
      sessionId: "session-two",
      model: second.selectedModel,
      contextUsage: second.currentContextUsage,
      thinkingLevel: "high",
      availableThinkingLevels: ["off", "low", "high", "max"],
      modelOptions: second.modelOptions,
    });
    expect(first.selectedModel.id).toBe("gpt-test");
    expect(second.selectedModel.id).toBe("claude-test");
  });

  test("sets thinking level only on the requested session", () => {
    const first = new ControllableSession("session-one");
    const second = new ControllableSession("session-two");
    const registry = new SessionRegistry(() => {});
    registry.register(first);
    registry.register(second);

    expect(registry.setThinkingLevel("session-two", "max")).toEqual({
      sessionId: "session-two",
      thinkingLevel: "max",
      availableThinkingLevels: ["off", "low", "high", "max"],
    });
    expect(first.thinkingLevel).toBe("high");
    expect(second.thinkingLevel).toBe("max");
  });

  test("sets a model option only on the requested session", async () => {
    const first = new ControllableSession("session-one");
    const second = new ControllableSession("session-two");
    const registry = new SessionRegistry(() => {});
    registry.register(first);
    registry.register(second);

    expect(await registry.setModelOption("session-two", "fastMode", true)).toEqual({
      sessionId: "session-two",
      model: second.selectedModel,
      contextUsage: second.currentContextUsage,
      modelOptions: {
        fastMode: { supported: true, enabled: true },
        oneMillionContext: { supported: true, enabled: false },
      },
    });
    expect(first.modelOptions.fastMode.enabled).toBe(false);
    expect(second.modelOptions.fastMode.enabled).toBe(true);
  });

  test("sets access mode only on the requested session", () => {
    const first = new ControllableSession("session-one");
    const second = new ControllableSession("session-two");
    const registry = new SessionRegistry(() => {});
    registry.register(first);
    registry.register(second);

    expect(registry.setAccessMode("session-two", "full")).toEqual({
      sessionId: "session-two",
      accessMode: "full",
    });
    expect(first.accessMode).toBe("ask");
    expect(second.accessMode).toBe("full");
  });

  test("accepts a prompt before the underlying agent run settles", async () => {
    const events: SessionRegistryEvent[] = [];
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry((event) => events.push(event));
    registry.register(session);

    const result = registry.prompt("session-one", "turn-one", "Build the feature");

    expect(result).toEqual({
      accepted: true,
      sessionId: "session-one",
      turnId: "turn-one",
    });
    expect(session.prompts).toEqual(["Build the feature"]);
    expect(events[0]).toEqual({
      event: "session.stateChanged",
      payload: {
        sessionId: "session-one",
        sequence: 1,
        turnId: "turn-one",
        state: "running",
      },
    });

    session.settle();
    await Promise.resolve();

    expect(events.at(-1)).toEqual({
      event: "session.stateChanged",
      payload: {
        sessionId: "session-one",
        sequence: 2,
        turnId: "turn-one",
        state: "idle",
        contextUsage: session.currentContextUsage,
      },
    });
  });

  test("aborts only the requested session", async () => {
    const first = new ControllableSession("session-one");
    const second = new ControllableSession("session-two");
    const registry = new SessionRegistry(() => {});
    registry.register(first);
    registry.register(second);
    registry.prompt("session-one", "turn-one", "First task");
    registry.prompt("session-two", "turn-two", "Second task");

    await registry.abort("session-two");

    expect(first.abortCount).toBe(0);
    expect(second.abortCount).toBe(1);
  });

  test("reloads every idle session after extension configuration changes", async () => {
    const first = new ControllableSession("session-one");
    const second = new ControllableSession("session-two");
    const registry = new SessionRegistry(() => {});
    registry.register(first);
    registry.register(second);

    expect(await registry.reloadExtensions()).toEqual({
      reloaded: ["session-one", "session-two"],
      deferred: [],
    });
    expect(first.reloadCount).toBe(1);
    expect(second.reloadCount).toBe(1);
  });

  test("defers extension reload until a running turn becomes idle", async () => {
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry(() => {});
    registry.register(session);
    registry.prompt("session-one", "turn-one", "Keep working");

    expect(await registry.reloadExtensions()).toEqual({
      reloaded: [],
      deferred: ["session-one"],
    });
    expect(session.reloadCount).toBe(0);

    session.settle();
    await Bun.sleep(0);

    expect(session.reloadCount).toBe(1);
    expect(registry.snapshot("session-one").state).toBe("idle");
  });

  test("rejects a second prompt while the session is running", () => {
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry(() => {});
    registry.register(session);
    registry.prompt("session-one", "turn-one", "First task");

    expect(() => registry.prompt("session-one", "turn-two", "Second task")).toThrow(
      new SessionRegistryError("session_busy", "Session is already running: session-one"),
    );
  });

  test("emits a correlated error event when the agent run rejects", async () => {
    const events: SessionRegistryEvent[] = [];
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry((event) => events.push(event));
    registry.register(session);
    registry.prompt("session-one", "turn-one", "Build the feature");

    session.fail(new Error("No model configured"));
    await Bun.sleep(0);

    expect(events.at(-1)).toEqual({
      event: "session.error",
      payload: {
        sessionId: "session-one",
        sequence: 2,
        turnId: "turn-one",
        code: "agent_error",
        message: "No model configured",
      },
    });
  });

  test("adds session correlation to normalized text deltas", () => {
    const events: SessionRegistryEvent[] = [];
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry((event) => events.push(event));
    registry.register(session);
    registry.prompt("session-one", "turn-one", "Build the feature");

    session.emitText("Hello");

    expect(events.at(-1)).toEqual({
      event: "session.messageDelta",
      payload: {
        sessionId: "session-one",
        sequence: 2,
        turnId: "turn-one",
        delta: "Hello",
      },
    });
  });

  test("disposes a closed session", async () => {
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry(() => {});
    registry.register(session);

    await registry.close("session-one");

    expect(session.disposeCount).toBe(1);
  });

  test("unsubscribes from a closed session", () => {
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry(() => {});
    registry.register(session);
    expect(session.listenerCount).toBe(1);

    registry.close("session-one");

    expect(session.listenerCount).toBe(0);
  });

  test("adds session correlation to tool starts", () => {
    const events: SessionRegistryEvent[] = [];
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry((event) => events.push(event));
    registry.register(session);
    registry.prompt("session-one", "turn-one", "Read the file");

    session.emitToolStarted();

    expect(events.at(-1)).toEqual({
      event: "session.toolStarted",
      payload: {
        sessionId: "session-one",
        sequence: 2,
        turnId: "turn-one",
        toolCallId: "tool-one",
        toolName: "read",
        summary: '{"path":"README.md"}',
      },
    });
  });

  test("adds session correlation to tool completion", () => {
    const events: SessionRegistryEvent[] = [];
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry((event) => events.push(event));
    registry.register(session);
    registry.prompt("session-one", "turn-one", "Read the file");

    session.emitToolCompleted();

    expect(events.at(-1)).toEqual({
      event: "session.toolCompleted",
      payload: {
        sessionId: "session-one",
        sequence: 2,
        turnId: "turn-one",
        toolCallId: "tool-one",
        toolName: "read",
        output: "README contents",
        isError: false,
      },
    });
  });

  test("adds session correlation to tool progress", () => {
    const events: SessionRegistryEvent[] = [];
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry((event) => events.push(event));
    registry.register(session);
    registry.prompt("session-one", "turn-one", "Read the file");

    session.emitToolUpdated();

    expect(events.at(-1)).toEqual({
      event: "session.toolUpdated",
      payload: {
        sessionId: "session-one",
        sequence: 2,
        turnId: "turn-one",
        toolCallId: "tool-one",
        toolName: "read",
        output: "First line",
      },
    });
  });

  test("adds session correlation to approval requests", () => {
    const events: SessionRegistryEvent[] = [];
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry((event) => events.push(event));
    registry.register(session);
    registry.prompt("session-one", "turn-one", "Run the tests");

    session.emitApprovalRequested();

    expect(events.at(-1)).toEqual({
      event: "session.approvalRequested",
      payload: {
        sessionId: "session-one",
        sequence: 2,
        turnId: "turn-one",
        requestId: "approval-one",
        toolCallId: "tool-one",
        toolName: "bash",
        summary: "bun test",
      },
    });
  });

  test("resolves an approval only on the requested session", () => {
    const first = new ControllableSession("session-one");
    const second = new ControllableSession("session-two");
    const registry = new SessionRegistry(() => {});
    registry.register(first);
    registry.register(second);

    registry.resolveApproval("session-two", "approval-one", "allowOnce");

    expect(first.approvalResolutions).toEqual([]);
    expect(second.approvalResolutions).toEqual([{
      requestId: "approval-one",
      decision: "allowOnce",
    }]);
  });

  test("disposes every registered session during shutdown", () => {
    const first = new ControllableSession("session-one");
    const second = new ControllableSession("session-two");
    const registry = new SessionRegistry(() => {});
    registry.register(first);
    registry.register(second);

    registry.closeAll();

    expect(first.disposeCount).toBe(1);
    expect(second.disposeCount).toBe(1);
  });

  test("does not emit completion after a running session is closed", async () => {
    const events: SessionRegistryEvent[] = [];
    const session = new ControllableSession("session-one");
    const registry = new SessionRegistry((event) => events.push(event));
    registry.register(session);
    registry.prompt("session-one", "turn-one", "Build the feature");
    registry.close("session-one");

    session.settle();
    await Bun.sleep(0);

    expect(events).toHaveLength(1);
    expect(events[0]?.event).toBe("session.stateChanged");
  });

  test("rejects duplicate session registration", () => {
    const registry = new SessionRegistry(() => {});
    registry.register(new ControllableSession("session-one"));

    expect(() => registry.register(new ControllableSession("session-one"))).toThrow(
      new SessionRegistryError("session_already_open", "Session is already open: session-one"),
    );
  });

  test("disposes the rejected duplicate session handle", () => {
    const registry = new SessionRegistry(() => {});
    const duplicate = new ControllableSession("session-one");
    registry.register(new ControllableSession("session-one"));

    try {
      registry.register(duplicate);
    } catch {
      // The error is asserted separately; this test only covers cleanup.
    }

    expect(duplicate.disposeCount).toBe(1);
  });

  test("returns a stable error code for an unknown session", () => {
    const registry = new SessionRegistry(() => {});

    try {
      registry.prompt("missing", "turn-one", "Hello");
      throw new Error("Expected the prompt to fail");
    } catch (error) {
      expect(error).toBeInstanceOf(SessionRegistryError);
      expect(error).toMatchObject({
        code: "session_not_found",
        message: "Session not found: missing",
      });
    }
  });

  test("returns a stable error when closing an unknown session", () => {
    const registry = new SessionRegistry(() => {});

    try {
      registry.close("missing");
      throw new Error("Expected close to fail");
    } catch (error) {
      expect(error).toBeInstanceOf(SessionRegistryError);
      expect(error).toMatchObject({
        code: "session_not_found",
        message: "Session not found: missing",
      });
    }
  });
});
