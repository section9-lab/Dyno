import type {
  AuthEvent,
  AuthInteraction,
  AuthPrompt,
  AuthType,
} from "@earendil-works/pi-ai";

export type ProviderAuthCoordinatorEvent =
  | {
      event: "auth.prompt";
      payload: {
        flowId: string;
        providerId: string;
        sequence: number;
        promptId: string;
        type: AuthPrompt["type"];
        message: string;
        placeholder?: string;
        allowsEmpty?: boolean;
        options?: readonly { id: string; label: string; description?: string }[];
      };
    }
  | {
      event: "auth.promptCancelled";
      payload: {
        flowId: string;
        providerId: string;
        sequence: number;
        promptId: string;
      };
    }
  | {
      event: "auth.notice";
      payload: {
        flowId: string;
        providerId: string;
        sequence: number;
        notice: AuthEvent;
      };
    }
  | {
      event: "auth.finished";
      payload: {
        flowId: string;
        providerId: string;
        sequence: number;
        outcome: "succeeded" | "cancelled" | "failed";
        error?: { code: string; message: string };
      };
    }
  | {
      event: "models.changed";
      payload: {
        reason: "authentication";
        providerId: string;
      };
    };

type AuthRuntime = {
  login(providerId: string, type: AuthType, interaction: AuthInteraction): Promise<unknown>;
  logout(providerId: string): Promise<void>;
  refresh?(options: {
    allowNetwork: boolean;
    force: boolean;
    providers: readonly string[];
    signal: AbortSignal;
  }): Promise<{ errors?: ReadonlyMap<string, Error> }>;
};

type ActivePrompt = {
  id: string;
  prompt: AuthPrompt;
  resolve(value: string): void;
  reject(error: Error): void;
  removeAbortListener(): void;
};

type ActiveFlow = {
  id: string;
  providerId: string;
  method: AuthType;
  sequence: number;
  controller: AbortController;
  prompt?: ActivePrompt;
};

export class ProviderAuthCoordinatorError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
  }
}

export class ProviderAuthCoordinator {
  private active?: ActiveFlow;

  constructor(
    private readonly runtime: AuthRuntime,
    private readonly emit: (event: ProviderAuthCoordinatorEvent) => void,
  ) {}

  start(input: {
    flowId: string;
    providerId: string;
    method: AuthType;
  }): { accepted: true; flowId: string } {
    if (this.active) {
      throw new ProviderAuthCoordinatorError("auth_busy", "Another authentication flow is active");
    }

    const flow: ActiveFlow = {
      id: input.flowId,
      providerId: input.providerId,
      method: input.method,
      sequence: 0,
      controller: new AbortController(),
    };
    this.active = flow;
    void this.run(flow);
    return { accepted: true, flowId: flow.id };
  }

  respond(input: {
    flowId: string;
    promptId: string;
    value: string;
  }): { accepted: true } {
    const flow = this.requireFlow(input.flowId);
    const pending = flow.prompt;
    if (!pending || pending.id !== input.promptId) {
      throw new ProviderAuthCoordinatorError("prompt_not_found", "Authentication prompt is no longer active");
    }
    if (
      pending.prompt.type === "select"
      && !pending.prompt.options.some((option) => option.id === input.value)
    ) {
      throw new ProviderAuthCoordinatorError("invalid_response", "Unknown authentication option");
    }

    flow.prompt = undefined;
    pending.removeAbortListener();
    pending.resolve(input.value);
    return { accepted: true };
  }

  cancel(flowId: string): { cancelRequested: true } {
    const flow = this.requireFlow(flowId);
    flow.controller.abort();
    return { cancelRequested: true };
  }

  async logout(providerId: string): Promise<void> {
    await this.runtime.logout(providerId);
    this.emit({
      event: "models.changed",
      payload: { reason: "authentication", providerId },
    });
  }

  private requireFlow(flowId: string): ActiveFlow {
    if (!this.active || this.active.id !== flowId) {
      throw new ProviderAuthCoordinatorError("flow_not_found", "Authentication flow is no longer active");
    }
    return this.active;
  }

  private async run(flow: ActiveFlow): Promise<void> {
    const interaction: AuthInteraction = {
      signal: flow.controller.signal,
      prompt: (prompt) => this.requestPrompt(flow, prompt),
      notify: (notice) => {
        this.emit({
          event: "auth.notice",
          payload: {
            flowId: flow.id,
            providerId: flow.providerId,
            sequence: ++flow.sequence,
            notice,
          },
        });
      },
    };

    try {
      await this.runtime.login(flow.providerId, flow.method, interaction);
      await this.refreshDynamicCatalog(flow);
      this.emit({
        event: "models.changed",
        payload: { reason: "authentication", providerId: flow.providerId },
      });
      this.emitFinished(flow, "succeeded");
    } catch (error) {
      if (flow.controller.signal.aborted || isAbortError(error)) {
        this.emitFinished(flow, "cancelled");
      } else {
        this.emitFinished(flow, "failed", authenticationError(error));
      }
    } finally {
      this.rejectPendingPrompt(flow, abortError());
      if (this.active === flow) this.active = undefined;
    }
  }

  private requestPrompt(flow: ActiveFlow, prompt: AuthPrompt): Promise<string> {
    if (flow.prompt) {
      return Promise.reject(new ProviderAuthCoordinatorError(
        "prompt_already_active",
        "Provider requested overlapping authentication prompts",
      ));
    }

    return new Promise<string>((resolve, reject) => {
      const promptId = crypto.randomUUID();
      const onAbort = () => {
        if (flow.prompt?.id !== promptId) return;
        flow.prompt = undefined;
        this.emit({
          event: "auth.promptCancelled",
          payload: {
            flowId: flow.id,
            providerId: flow.providerId,
            sequence: ++flow.sequence,
            promptId,
          },
        });
        reject(abortError());
      };
      const signals = [flow.controller.signal, prompt.signal].filter(
        (signal): signal is AbortSignal => signal !== undefined,
      );
      const removeAbortListener = () => {
        for (const signal of signals) signal.removeEventListener("abort", onAbort);
      };
      for (const signal of signals) signal.addEventListener("abort", onAbort, { once: true });

      flow.prompt = { id: promptId, prompt, resolve, reject, removeAbortListener };
      this.emit({
        event: "auth.prompt",
        payload: {
          flowId: flow.id,
          providerId: flow.providerId,
          sequence: ++flow.sequence,
          promptId,
          type: prompt.type,
          message: prompt.message,
          ...(prompt.type !== "select" && prompt.placeholder
            ? { placeholder: prompt.placeholder }
            : {}),
          ...(allowsEmptyResponse(flow.providerId, prompt)
            ? { allowsEmpty: true }
            : {}),
          ...(prompt.type === "select" ? { options: prompt.options } : {}),
        },
      });

      if (signals.some((signal) => signal.aborted)) onAbort();
    });
  }

  private async refreshDynamicCatalog(flow: ActiveFlow): Promise<void> {
    if (flow.providerId !== "radius" || !this.runtime.refresh) return;
    try {
      const result = await this.runtime.refresh({
        allowNetwork: true,
        force: true,
        providers: [flow.providerId],
        signal: flow.controller.signal,
      });
      flow.controller.signal.throwIfAborted();
      if (result.errors?.has(flow.providerId)) this.emitCatalogRefreshWarning(flow);
    } catch {
      flow.controller.signal.throwIfAborted();
      this.emitCatalogRefreshWarning(flow);
    }
  }

  private emitCatalogRefreshWarning(flow: ActiveFlow): void {
    this.emit({
      event: "auth.notice",
      payload: {
        flowId: flow.id,
        providerId: flow.providerId,
        sequence: ++flow.sequence,
        notice: {
          type: "info",
          message: "Credentials were saved, but the Radius model catalog could not be refreshed.",
        },
      },
    });
  }

  private rejectPendingPrompt(flow: ActiveFlow, error: Error): void {
    const pending = flow.prompt;
    if (!pending) return;
    flow.prompt = undefined;
    pending.removeAbortListener();
    pending.reject(error);
  }

  private emitFinished(
    flow: ActiveFlow,
    outcome: "succeeded" | "cancelled" | "failed",
    error?: { code: string; message: string },
  ): void {
    this.emit({
      event: "auth.finished",
      payload: {
        flowId: flow.id,
        providerId: flow.providerId,
        sequence: ++flow.sequence,
        outcome,
        ...(error ? { error } : {}),
      },
    });
  }
}

function abortError(): Error {
  return new DOMException("Authentication cancelled", "AbortError");
}

function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === "AbortError";
}

function allowsEmptyResponse(providerId: string, prompt: AuthPrompt): boolean {
  if (prompt.type !== "text") return false;
  if (providerId === "github-copilot") {
    return prompt.message.toLowerCase().includes("blank for github.com");
  }
  return providerId === "amazon-bedrock"
    && prompt.message.toLowerCase().includes("press enter");
}

function authenticationError(error: unknown): { code: string; message: string } {
  const message = error instanceof Error ? error.message.toLowerCase() : "";
  if (/expired|device (?:code|authorization|flow).*(?:timeout|timed out)/u.test(message)) {
    return {
      code: "auth_expired",
      message: "The authentication request expired. Start again to get a new code.",
    };
  }
  if (/fetch|network|econn|enotfound|eai_again|socket|timed?\s*out|timeout/u.test(message)) {
    return {
      code: "auth_network_failed",
      message: "Could not reach the authentication service. Check your connection and try again.",
    };
  }
  if (/invalid.*(?:url|domain|host)|base url.*required|configuration|missing|required/u.test(message)) {
    return {
      code: "auth_invalid_configuration",
      message: "The authentication settings are incomplete or invalid. Review them and try again.",
    };
  }
  if (/access.denied|\bdenied\b|unauthorized|forbidden|invalid_grant|invalid.*(?:token|code|credential)|\b40[13]\b/u.test(message)) {
    return {
      code: "auth_rejected",
      message: "The authentication service rejected these credentials. Review them and try again.",
    };
  }
  if (/eaddrinuse|callback.*(?:failed|error)|listen.*(?:failed|error)/u.test(message)) {
    return {
      code: "auth_callback_failed",
      message: "The browser callback could not be received. Try again or use the manual-code option.",
    };
  }
  return {
    code: "login_failed",
    message: "Authentication could not be completed. Check your connection or credentials, then try again.",
  };
}
