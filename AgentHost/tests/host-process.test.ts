import { describe, expect, test } from "bun:test";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SessionManager } from "@earendil-works/pi-coding-agent";

Bun.env.PI_WORK_SKIP_REQUIRED_EXTENSION_INSTALL = "1";

function appendTestAssistant(manager: SessionManager, text: string, timestamp: number): void {
  manager.appendMessage({
    role: "assistant",
    content: [{ type: "text", text }],
    api: "openai-completions",
    provider: "openai",
    model: "test-model",
    usage: {
      input: 1,
      output: 1,
      cacheRead: 0,
      cacheWrite: 0,
      totalTokens: 2,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
    },
    stopReason: "stop",
    timestamp,
  });
}

async function readJSONLine(reader: ReadableStreamDefaultReader<Uint8Array>): Promise<unknown> {
  const decoder = new TextDecoder();
  let buffered = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      throw new Error("Host stdout closed before a complete JSONL record was received");
    }

    buffered += decoder.decode(value, { stream: true });
    const newlineIndex = buffered.indexOf("\n");
    if (newlineIndex >= 0) {
      return JSON.parse(buffered.slice(0, newlineIndex));
    }
  }
}

class JSONLineReader {
  private readonly decoder = new TextDecoder();
  private buffered = "";

  constructor(private readonly reader: ReadableStreamDefaultReader<Uint8Array>) {}

  async read(): Promise<unknown> {
    while (true) {
      const newlineIndex = this.buffered.indexOf("\n");
      if (newlineIndex >= 0) {
        const line = this.buffered.slice(0, newlineIndex);
        this.buffered = this.buffered.slice(newlineIndex + 1);
        return JSON.parse(line);
      }

      const { done, value } = await this.reader.read();
      if (done) throw new Error("Host stdout closed before a complete JSONL record was received");
      this.buffered += this.decoder.decode(value, { stream: true });
    }
  }
}

describe("agent host process", () => {
  test("lists local Git branches without changing the working tree", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-git-branches-test-"));
    const repository = join(root, "repository");
    mkdirSync(repository);
    Bun.spawnSync(["git", "init", "-b", "main"], { cwd: repository });
    Bun.spawnSync([
      "git",
      "-c",
      "user.name=Pi Work Tests",
      "-c",
      "user.email=tests@example.com",
      "commit",
      "--allow-empty",
      "-m",
      "Initial commit",
    ], { cwd: repository });
    Bun.spawnSync(["git", "branch", "feature/session-picker"], { cwd: repository });

    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      const hello = await lines.read() as { payload: { capabilities: string[] } };
      expect(hello.payload.capabilities).toEqual(expect.arrayContaining([
        "git.branches",
        "session.setGitBranch",
      ]));

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "git-branches-one",
        method: "git.branches",
        params: { cwd: repository },
      })}\n`);
      await child.stdin.flush();

      expect(await lines.read()).toMatchObject({
        id: "git-branches-one",
        ok: true,
        result: {
          available: true,
          currentBranch: "main",
          branches: expect.arrayContaining(["main", "feature/session-picker"]),
        },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("reads and updates isolated desktop-agent settings", async () => {
    const agentDirectory = mkdtempSync(join(tmpdir(), "pi-work-settings-host-test-"));
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: { ...Bun.env, PI_WORK_AGENT_DIR: agentDirectory },
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      const hello = await lines.read() as { payload: { capabilities: string[] } };
      expect(hello.payload.capabilities).toEqual(expect.arrayContaining([
        "settings.get",
        "settings.update",
        "extensions.listInstalled",
        "extensions.install",
        "extensions.setEnabled",
        "extensions.update",
        "extensions.remove",
        "extensions.settings.list",
        "extensions.settings.update",
      ]));

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "settings-get-one",
        method: "settings.get",
        params: {},
      })}\n`);
      await child.stdin.flush();
      expect(await lines.read()).toMatchObject({
        id: "settings-get-one",
        ok: true,
        result: {
          defaultThinkingLevel: "off",
          transport: "auto",
          compactionEnabled: true,
          retryEnabled: true,
        },
      });

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "settings-update-one",
        method: "settings.update",
        params: {
          patch: {
            defaultThinkingLevel: "high",
            transport: "sse",
            compactionEnabled: false,
            retryEnabled: false,
          },
        },
      })}\n`);
      await child.stdin.flush();
      expect(await lines.read()).toMatchObject({
        id: "settings-update-one",
        ok: true,
        result: {
          defaultThinkingLevel: "high",
          transport: "sse",
          compactionEnabled: false,
          retryEnabled: false,
        },
      });
      expect(JSON.parse(readFileSync(join(agentDirectory, "settings.json"), "utf8")))
        .toMatchObject({
          defaultThinkingLevel: "high",
          transport: "sse",
          compaction: { enabled: false },
          retry: { enabled: false },
        });

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "extensions-list-one",
        method: "extensions.listInstalled",
        params: {},
      })}\n`);
      await child.stdin.flush();
      expect(await lines.read()).toEqual({
        version: 1,
        kind: "response",
        id: "extensions-list-one",
        ok: true,
        result: { packages: [] },
      });

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "extension-settings-list-one",
        method: "extensions.settings.list",
        params: {},
      })}\n`);
      await child.stdin.flush();
      expect(await lines.read()).toEqual({
        version: 1,
        kind: "response",
        id: "extension-settings-list-one",
        ok: true,
        result: { extensions: [] },
      });

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "extension-settings-update-missing",
        method: "extensions.settings.update",
        params: {
          source: "npm:missing",
          scope: "user",
          changes: [{ path: "/enabled", operation: "set", value: "true" }],
        },
      })}\n`);
      await child.stdin.flush();
      expect(await lines.read()).toMatchObject({
        id: "extension-settings-update-missing",
        ok: false,
        error: {
          code: "invalid_request",
          message: "No matching installed extension found: npm:missing (user)",
        },
      });

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "extensions-install-invalid",
        method: "extensions.install",
        params: { source: "git:example.com/unsafe/repository" },
      })}\n`);
      await child.stdin.flush();
      expect(await lines.read()).toMatchObject({
        id: "extensions-install-invalid",
        ok: false,
        error: {
          code: "invalid_request",
          message: "Catalog extensions must use an npm source",
        },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(agentDirectory, { recursive: true, force: true });
    }
  });

  test("keeps package manager output off protocol stdout", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-package-output-test-"));
    const agentDirectory = join(root, "Agent");
    const fakeBun = join(root, "bun");
    writeFileSync(fakeBun, "#!/bin/sh\necho package-manager-output\nexit 7\n");
    chmodSync(fakeBun, 0o755);
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: {
        ...Bun.env,
        PI_WORK_AGENT_DIR: agentDirectory,
        PI_WORK_BUN_PATH: fakeBun,
      },
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "install-with-output",
        method: "extensions.install",
        params: { source: "npm:fixture-extension" },
      })}\n`);
      await child.stdin.flush();

      expect(await lines.read()).toMatchObject({
        id: "install-with-output",
        ok: false,
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("advertises provider authentication capabilities", async () => {
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    const hello = await readJSONLine(child.stdout.getReader()) as {
      payload: { capabilities: string[] };
    };
    expect(hello.payload.capabilities).toEqual(expect.arrayContaining([
      "providers.list",
      "auth.start",
      "auth.respond",
      "auth.cancel",
      "auth.logout",
    ]));

    child.stdin.end();
    expect(await child.exited).toBe(0);
  });

  test("lists provider authentication methods without credentials", async () => {
    const agentDirectory = mkdtempSync(join(tmpdir(), "pi-work-auth-catalog-test-"));
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: { ...Bun.env, PI_CODING_AGENT_DIR: agentDirectory },
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "providers-one",
        method: "providers.list",
        params: {},
      })}\n`);
      await child.stdin.flush();

      const response = await lines.read() as {
        ok: boolean;
        result?: { providers: Array<{ id: string; methods: Array<{ type: string }> }> };
      };
      expect(response.ok).toBe(true);
      expect(response.result?.providers.find((provider) => provider.id === "openai-codex"))
        .toMatchObject({ methods: [{ type: "oauth" }] });
      expect(JSON.stringify(response)).not.toContain("access");
      expect(JSON.stringify(response)).not.toContain("refresh");
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(agentDirectory, { recursive: true, force: true });
    }
  });

  test("accepts authentication work without blocking later stdin requests", async () => {
    const agentDirectory = mkdtempSync(join(tmpdir(), "pi-work-auth-start-test-"));
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: { ...Bun.env, PI_CODING_AGENT_DIR: agentDirectory },
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "auth-start-one",
        method: "auth.start",
        params: {
          flowId: "flow-one",
          providerId: "missing-provider",
          method: "oauth",
        },
      })}\n`);
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "providers-after-auth",
        method: "providers.list",
        params: {},
      })}\n`);
      await child.stdin.flush();

      const records: any[] = [];
      while (
        !records.some((record) => record.event === "auth.finished")
        || !records.some((record) => record.id === "providers-after-auth")
      ) {
        records.push(await lines.read());
      }

      expect(records).toContainEqual({
        version: 1,
        kind: "response",
        id: "auth-start-one",
        ok: true,
        result: { accepted: true, flowId: "flow-one" },
      });
      expect(records.some((record) => (
        record.kind === "response"
        && record.id === "providers-after-auth"
        && record.ok === true
      ))).toBe(true);
      expect(records.some((record) => (
        record.event === "auth.finished"
        && record.payload?.flowId === "flow-one"
        && record.payload?.outcome === "failed"
      ))).toBe(true);
    } finally {
      child.stdin.end();
      child.kill();
      await child.exited;
      rmSync(agentDirectory, { recursive: true, force: true });
    }
  });

  test("accepts an API key prompt response without echoing the secret", async () => {
    const agentDirectory = mkdtempSync(join(tmpdir(), "pi-work-auth-prompt-test-"));
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: { ...Bun.env, PI_CODING_AGENT_DIR: agentDirectory },
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "auth-api-key-start",
        method: "auth.start",
        params: {
          flowId: "flow-api-key",
          providerId: "anthropic",
          method: "api_key",
        },
      })}\n`);
      await child.stdin.flush();

      let prompt: any;
      for (let index = 0; index < 3; index += 1) {
        const record: any = await lines.read();
        if (record.event === "auth.prompt") prompt = record;
        if (prompt) break;
      }
      expect(prompt).toMatchObject({
        event: "auth.prompt",
        payload: {
          flowId: "flow-api-key",
          providerId: "anthropic",
          type: "secret",
        },
      });

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "auth-api-key-response",
        method: "auth.respond",
        params: {
          flowId: "flow-api-key",
          promptId: prompt.payload.promptId,
          value: "test-secret-value",
        },
      })}\n`);
      await child.stdin.flush();

      const records: any[] = [];
      while (!records.some((record) => record.id === "auth-api-key-response")) {
        records.push(await lines.read());
      }
      expect(records).toContainEqual({
        version: 1,
        kind: "response",
        id: "auth-api-key-response",
        ok: true,
        result: { accepted: true },
      });
      expect(JSON.stringify(records)).not.toContain("test-secret-value");
    } finally {
      child.stdin.end();
      child.kill();
      await child.exited;
      rmSync(agentDirectory, { recursive: true, force: true });
    }
  }, 15_000);

  test("cancels an authentication prompt through the host protocol", async () => {
    const agentDirectory = mkdtempSync(join(tmpdir(), "pi-work-auth-cancel-test-"));
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: { ...Bun.env, PI_CODING_AGENT_DIR: agentDirectory },
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "auth-cancel-start",
        method: "auth.start",
        params: {
          flowId: "flow-cancel",
          providerId: "anthropic",
          method: "api_key",
        },
      })}\n`);
      await child.stdin.flush();

      const initial: any[] = [];
      while (
        !initial.some((record) => record.event === "auth.prompt")
        || !initial.some((record) => record.id === "auth-cancel-start")
      ) {
        initial.push(await lines.read());
      }

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "auth-cancel-response",
        method: "auth.cancel",
        params: { flowId: "flow-cancel" },
      })}\n`);
      await child.stdin.flush();

      const records: any[] = [];
      while (!records.some((record) => record.id === "auth-cancel-response")) {
        records.push(await lines.read());
      }
      expect(records.find((record) => record.id === "auth-cancel-response")).toEqual({
        version: 1,
        kind: "response",
        id: "auth-cancel-response",
        ok: true,
        result: { cancelRequested: true },
      });
      while (!records.some((record) => record.event === "auth.finished")) {
        records.push(await lines.read());
      }
      expect(records.some((record) => record.event === "auth.promptCancelled")).toBe(true);
      expect(records.find((record) => record.event === "auth.finished")).toMatchObject({
        payload: { flowId: "flow-cancel", outcome: "cancelled" },
      });
    } finally {
      child.stdin.end();
      child.kill();
      await child.exited;
      rmSync(agentDirectory, { recursive: true, force: true });
    }
  });

  test("returns an authoritative provider snapshot after logout", async () => {
    const agentDirectory = mkdtempSync(join(tmpdir(), "pi-work-auth-logout-test-"));
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: {
        ...Bun.env,
        PI_CODING_AGENT_DIR: agentDirectory,
        ANTHROPIC_API_KEY: "",
        ANTHROPIC_AUTH_TOKEN: "",
      },
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "auth-logout-one",
        method: "auth.logout",
        params: { providerId: "anthropic" },
      })}\n`);
      await child.stdin.flush();

      const records: any[] = [];
      while (!records.some((record) => record.id === "auth-logout-one")) {
        records.push(await lines.read());
      }
      expect(records.find((record) => record.id === "auth-logout-one")).toMatchObject({
        version: 1,
        kind: "response",
        ok: true,
        result: {
          removed: false,
          provider: {
            id: "anthropic",
            status: { configured: false, canDisconnect: false },
          },
        },
      });
      expect(records.some((record) => record.event === "models.changed")).toBe(true);
    } finally {
      child.stdin.end();
      child.kill();
      await child.exited;
      rmSync(agentDirectory, { recursive: true, force: true });
    }
  });

  test("writes the version handshake before accepting requests", async () => {
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: {
        ...Bun.env,
        PI_WORK_HOST_VERSION: "0.1.0-test",
      },
    });

    const reader = child.stdout.getReader();
    const hello = await readJSONLine(reader);

    expect(hello).toEqual({
      version: 1,
      kind: "event",
      event: "host.hello",
      payload: {
        hostVersion: "0.1.0-test",
        piVersion: "0.84.1",
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
      },
    });

    child.stdin.end();
    expect(await child.exited).toBe(0);
  });

  test("serves session list requests while stdin remains open", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-process-test-"));
    const cwd = join(root, "project");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });

    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const reader = child.stdout.getReader();
      await readJSONLine(reader);
      child.stdin.write(
        `${JSON.stringify({
          version: 1,
          kind: "request",
          id: "list-1",
          method: "sessions.list",
          params: { cwd, sessionDirectory },
        })}\n`,
      );
      await child.stdin.flush();

      const response = await Promise.race([
        readJSONLine(reader),
        Bun.sleep(500).then(() => {
          throw new Error("Timed out waiting for sessions.list response");
        }),
      ]);

      expect(response).toEqual({
        version: 1,
        kind: "response",
        id: "list-1",
        ok: true,
        result: { sessions: [] },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("creates a native draft without adding empty history", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-create-test-"));
    const cwd = join(root, "project");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });

    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const reader = child.stdout.getReader();
      await readJSONLine(reader);
      child.stdin.write(
        `${JSON.stringify({
          version: 1,
          kind: "request",
          id: "create-1",
          method: "session.createDraft",
          params: { cwd, sessionDirectory },
        })}\n`,
      );
      await child.stdin.flush();

      const response = (await readJSONLine(reader)) as {
        result: { session: { id: string; path: string } };
      };
      expect(response).toMatchObject({
        version: 1,
        kind: "response",
        id: "create-1",
        ok: true,
        result: {
          session: {
            cwd,
            title: "New Session",
            messageCount: 0,
          },
        },
      });
      expect(response.result.session.id).not.toBeEmpty();
      expect(existsSync(response.result.session.path)).toBe(false);
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("returns a typed error for an unsupported method", async () => {
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const reader = child.stdout.getReader();
      await readJSONLine(reader);
      child.stdin.write(
        `${JSON.stringify({
          version: 1,
          kind: "request",
          id: "unknown-1",
          method: "unknown.method",
          params: {},
        })}\n`,
      );
      await child.stdin.flush();

      expect(await readJSONLine(reader)).toEqual({
        version: 1,
        kind: "response",
        id: "unknown-1",
        ok: false,
        error: {
          code: "method_not_found",
          message: "Unsupported method: unknown.method",
        },
      });
    } finally {
      child.stdin.end();
      await child.exited;
    }
  });

  test("accepts a prompt without waiting for the agent run to settle", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-prompt-test-"));
    const cwd = join(root, "chat");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "create-prompt-session",
        method: "session.createDraft",
        params: { cwd, sessionDirectory, profile: "chat" },
      })}\n`);
      await child.stdin.flush();
      const created = (await lines.read()) as {
        result: { session: { id: string } };
      };

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "prompt-one",
        method: "session.prompt",
        params: {
          sessionId: created.result.session.id,
          turnId: "turn-one",
          text: "Hello",
        },
      })}\n`);
      await child.stdin.flush();

      let response: unknown;
      for (let index = 0; index < 6; index += 1) {
        const record = await Promise.race([
          lines.read(),
          Bun.sleep(2000).then(() => {
            throw new Error("Timed out waiting for session.prompt response");
          }),
        ]) as { kind?: string; id?: string };
        if (record.kind === "response" && record.id === "prompt-one") {
          response = record;
          break;
        }
      }

      expect(response).toEqual({
        version: 1,
        kind: "response",
        id: "prompt-one",
        ok: true,
        result: {
          accepted: true,
          sessionId: created.result.session.id,
          turnId: "turn-one",
        },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  }, 15_000);

  test("rejects invalid prompt images through the host protocol", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-prompt-image-test-"));
    const cwd = join(root, "chat");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "create-image-session",
        method: "session.createDraft",
        params: { cwd, sessionDirectory, profile: "chat" },
      })}\n`);
      await child.stdin.flush();
      const created = (await lines.read()) as {
        result: { session: { id: string } };
      };

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "prompt-invalid-image",
        method: "session.prompt",
        params: {
          sessionId: created.result.session.id,
          turnId: "turn-one",
          text: "Inspect this",
          images: [{ mimeType: "image/gif", data: "R0lGODlh" }],
        },
      })}\n`);
      await child.stdin.flush();

      let response: unknown;
      for (let index = 0; index < 6; index += 1) {
        const record = await lines.read() as { kind?: string; id?: string };
        if (record.kind === "response" && record.id === "prompt-invalid-image") {
          response = record;
          break;
        }
      }

      expect(response).toEqual({
        version: 1,
        kind: "response",
        id: "prompt-invalid-image",
        ok: false,
        error: {
          code: "invalid_image",
          message: "Prompt images must use image/png or image/jpeg",
        },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  }, 15_000);

  test("serves abort requests after accepting a prompt", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-abort-test-"));
    const cwd = join(root, "chat");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "create-abort-session",
        method: "session.createDraft",
        params: { cwd, sessionDirectory, profile: "chat" },
      })}\n`);
      await child.stdin.flush();
      const created = (await lines.read()) as {
        result: { session: { id: string } };
      };

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "prompt-before-abort",
        method: "session.prompt",
        params: {
          sessionId: created.result.session.id,
          turnId: "turn-one",
          text: "Hello",
        },
      })}\n`);
      await child.stdin.flush();

      for (let index = 0; index < 6; index += 1) {
        const record = await lines.read() as { kind?: string; id?: string };
        if (record.kind === "response" && record.id === "prompt-before-abort") break;
      }

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "abort-one",
        method: "session.abort",
        params: { sessionId: created.result.session.id },
      })}\n`);
      await child.stdin.flush();

      let response: unknown;
      for (let index = 0; index < 6; index += 1) {
        const record = await Promise.race([
          lines.read(),
          Bun.sleep(2000).then(() => {
            throw new Error("Timed out waiting for session.abort response");
          }),
        ]) as { kind?: string; id?: string };
        if (record.kind === "response" && record.id === "abort-one") {
          response = record;
          break;
        }
      }

      expect(response).toEqual({
        version: 1,
        kind: "response",
        id: "abort-one",
        ok: true,
        result: {
          aborted: true,
          sessionId: created.result.session.id,
        },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("opens an existing native Pi session idempotently", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-open-process-test-"));
    const cwd = join(root, "project");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });
    const manager = SessionManager.create(cwd, sessionDirectory, { id: "session-one" });
    manager.appendMessage({
      role: "user",
      content: "Resume this work",
      timestamp: Date.now(),
    });
    manager.appendMessage({
      role: "assistant",
      content: [{ type: "text", text: "Ready" }],
      api: "openai-completions",
      provider: "openai",
      model: "test-model",
      usage: {
        input: 1,
        output: 1,
        cacheRead: 0,
        cacheWrite: 0,
        totalTokens: 2,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
      },
      stopReason: "stop",
      timestamp: Date.now(),
    });
    const sessionPath = manager.getSessionFile()!;
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "open-one",
        method: "session.open",
        params: { path: sessionPath, sessionDirectory, profile: "work" },
      })}\n`);
      await child.stdin.flush();

      expect(await lines.read()).toEqual({
        version: 1,
        kind: "response",
        id: "open-one",
        ok: true,
        result: {
          sessionId: "session-one",
          path: sessionPath,
          cwd,
        },
      });

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "open-two",
        method: "session.open",
        params: { path: sessionPath, sessionDirectory, profile: "work" },
      })}\n`);
      await child.stdin.flush();

      expect(await lines.read()).toEqual({
        version: 1,
        kind: "response",
        id: "open-two",
        ok: true,
        result: {
          sessionId: "session-one",
          path: sessionPath,
          cwd,
        },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("exports an unopened native Pi session to HTML", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-export-process-test-"));
    const cwd = join(root, "project");
    const sessionDirectory = join(root, "sessions");
    const outputPath = join(root, "session-report.html");
    mkdirSync(cwd, { recursive: true });
    mkdirSync(sessionDirectory, { recursive: true });
    const manager = SessionManager.create(cwd, sessionDirectory, { id: "session-export" });
    manager.appendMessage({
      role: "user",
      content: "Export this report",
      timestamp: Date.now(),
    });
    appendTestAssistant(manager, "Report ready", Date.now() + 1);
    const sessionPath = manager.getSessionFile()!;
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      const hello = await lines.read() as { payload: { capabilities: string[] } };
      expect(hello.payload.capabilities).toContain("session.exportHtml");

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "export-one",
        method: "session.exportHtml",
        params: {
          sessionId: "session-export",
          path: sessionPath,
          sessionDirectory,
          profile: "work",
          outputPath,
        },
      })}\n`);
      await child.stdin.flush();

      expect(await lines.read()).toEqual({
        version: 1,
        kind: "response",
        id: "export-one",
        ok: true,
        result: { sessionId: "session-export", path: outputPath },
      });
      expect(existsSync(outputPath)).toBe(true);
      const html = readFileSync(outputPath, "utf8");
      const encodedSession = html.match(
        /<script id="session-data" type="application\/json">([^<]+)<\/script>/,
      )?.[1];
      expect(encodedSession).toBeDefined();
      const exportedSession = Buffer.from(encodedSession!, "base64").toString("utf8");
      expect(exportedSession).toContain("Export this report");
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("returns a normalized snapshot for an open Pi session", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-snapshot-test-"));
    const cwd = join(root, "project");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });
    const manager = SessionManager.create(cwd, sessionDirectory, { id: "session-snapshot" });
    manager.appendMessage({
      role: "user",
      content: "Resume this work",
      timestamp: Date.parse("2026-08-09T00:00:00.000Z"),
    });
    appendTestAssistant(manager, "Ready", Date.parse("2026-08-09T00:00:01.000Z"));
    manager.appendSessionInfo("Snapshot session");
    const sessionPath = manager.getSessionFile()!;
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "open-for-snapshot",
        method: "session.open",
        params: { path: sessionPath, sessionDirectory, profile: "work" },
      })}\n`);
      await child.stdin.flush();
      expect(await lines.read()).toMatchObject({ ok: true });

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "snapshot-one",
        method: "session.snapshot",
        params: { sessionId: "session-snapshot" },
      })}\n`);
      await child.stdin.flush();

      expect(await lines.read()).toMatchObject({
        version: 1,
        kind: "response",
        id: "snapshot-one",
        ok: true,
        result: {
          session: {
            id: "session-snapshot",
            path: sessionPath,
            cwd,
            title: "Snapshot session",
          },
          messages: [{
            id: "session-snapshot:1786233600000:0",
            role: "user",
            content: [{ type: "text", text: "Resume this work" }],
            timestamp: "2026-08-09T00:00:00.000Z",
          }, {
            id: "session-snapshot:1786233601000:1",
            role: "assistant",
            content: [{ type: "text", text: "Ready" }],
            timestamp: "2026-08-09T00:00:01.000Z",
            provider: "openai",
            model: "test-model",
            stopReason: "stop",
          }],
          state: "idle",
          sequence: 0,
          turnId: null,
          accessMode: "full",
          pendingApprovals: [],
        },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("loads an earlier transcript page for an open Pi session", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-history-page-test-"));
    const cwd = join(root, "project");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });
    const manager = SessionManager.create(cwd, sessionDirectory, { id: "session-history" });
    const firstTimestamp = Date.parse("2026-08-09T00:00:00.000Z");
    for (let turn = 0; turn < 21; turn += 1) {
      manager.appendMessage({
        role: "user",
        content: `Message ${turn * 2}`,
        timestamp: firstTimestamp + turn * 2,
      });
      if (turn < 20) {
        appendTestAssistant(manager, `Message ${turn * 2 + 1}`, firstTimestamp + turn * 2 + 1);
      }
    }
    const sessionPath = manager.getSessionFile()!;
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "open-for-history",
        method: "session.open",
        params: { path: sessionPath, sessionDirectory, profile: "work" },
      })}\n`);
      await child.stdin.flush();
      const opened = await lines.read() as {
        ok: boolean;
        result: { sessionId: string };
      };
      expect(opened).toMatchObject({ ok: true });

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "snapshot-history",
        method: "session.snapshot",
        params: { sessionId: opened.result.sessionId },
      })}\n`);
      await child.stdin.flush();
      const snapshot = await lines.read() as {
        ok: boolean;
        result: {
          messages: Array<{ content: unknown }>;
          history: { nextCursor: string; hasMore: boolean };
        };
      };
      expect(snapshot).toMatchObject({ ok: true });
      expect(snapshot.result.messages).toHaveLength(40);
      expect(snapshot.result.history.hasMore).toBe(true);

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "history-page-one",
        method: "session.transcriptPage",
        params: {
          sessionId: opened.result.sessionId,
          cursor: snapshot.result.history.nextCursor,
          limit: 40,
        },
      })}\n`);
      await child.stdin.flush();

      expect(await lines.read()).toMatchObject({
        version: 1,
        kind: "response",
        id: "history-page-one",
        ok: true,
        result: {
          sessionId: opened.result.sessionId,
          messages: [{ content: [{ type: "text", text: "Message 0" }] }],
          nextCursor: null,
          hasMore: false,
        },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("renames an open Pi session persistently", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-rename-test-"));
    const cwd = join(root, "project");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });
    const manager = SessionManager.create(cwd, sessionDirectory, { id: "session-rename" });
    const renameTimestamp = Date.now();
    manager.appendMessage({ role: "user", content: "Hello", timestamp: renameTimestamp });
    appendTestAssistant(manager, "Ready", renameTimestamp + 1);
    const sessionPath = manager.getSessionFile()!;
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "open-for-rename",
        method: "session.open",
        params: { path: sessionPath, sessionDirectory, profile: "work" },
      })}\n`);
      await child.stdin.flush();
      await lines.read();

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "rename-one",
        method: "session.rename",
        params: { sessionId: "session-rename", title: "Renamed session" },
      })}\n`);
      await child.stdin.flush();

      expect(await lines.read()).toEqual({
        version: 1,
        kind: "response",
        id: "rename-one",
        ok: true,
        result: { sessionId: "session-rename", title: "Renamed session" },
      });
      expect(SessionManager.open(sessionPath, sessionDirectory).getSessionName()).toBe("Renamed session");
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("closes only the in-memory handle and keeps Pi history", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-close-test-"));
    const cwd = join(root, "project");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });
    const manager = SessionManager.create(cwd, sessionDirectory, { id: "session-close" });
    const closeTimestamp = Date.now();
    manager.appendMessage({ role: "user", content: "Keep me", timestamp: closeTimestamp });
    appendTestAssistant(manager, "Ready", closeTimestamp + 1);
    const sessionPath = manager.getSessionFile()!;
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "open-for-close",
        method: "session.open",
        params: { path: sessionPath, sessionDirectory, profile: "work" },
      })}\n`);
      await child.stdin.flush();
      await lines.read();

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "close-one",
        method: "session.close",
        params: { sessionId: "session-close" },
      })}\n`);
      await child.stdin.flush();
      expect(await lines.read()).toEqual({
        version: 1,
        kind: "response",
        id: "close-one",
        ok: true,
        result: { closed: true, sessionId: "session-close" },
      });

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "snapshot-after-close",
        method: "session.snapshot",
        params: { sessionId: "session-close" },
      })}\n`);
      await child.stdin.flush();
      expect(await lines.read()).toMatchObject({
        id: "snapshot-after-close",
        ok: false,
        error: { code: "session_not_found" },
      });
      expect(existsSync(sessionPath)).toBe(true);
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("deletes an open Pi session and its persisted history", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-delete-test-"));
    const cwd = join(root, "project");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });
    const manager = SessionManager.create(cwd, sessionDirectory, { id: "session-delete" });
    const deleteTimestamp = Date.now();
    manager.appendMessage({ role: "user", content: "Delete me", timestamp: deleteTimestamp });
    appendTestAssistant(manager, "Ready", deleteTimestamp + 1);
    const sessionPath = manager.getSessionFile()!;
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "open-for-delete",
        method: "session.open",
        params: { path: sessionPath, sessionDirectory, profile: "work" },
      })}\n`);
      await child.stdin.flush();
      await lines.read();

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "delete-one",
        method: "session.delete",
        params: { sessionId: "session-delete", cwd, sessionDirectory },
      })}\n`);
      await child.stdin.flush();

      expect(await lines.read()).toEqual({
        version: 1,
        kind: "response",
        id: "delete-one",
        ok: true,
        result: { deleted: true, sessionId: "session-delete" },
      });
      expect(existsSync(sessionPath)).toBe(false);

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "snapshot-after-delete",
        method: "session.snapshot",
        params: { sessionId: "session-delete" },
      })}\n`);
      await child.stdin.flush();
      expect(await lines.read()).toMatchObject({
        id: "snapshot-after-delete",
        ok: false,
        error: { code: "session_not_found" },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("lists available models through the shared Pi model runtime", async () => {
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "models-one",
        method: "models.list",
        params: {},
      })}\n`);
      await child.stdin.flush();

      const response = await Promise.race([
        lines.read(),
        Bun.sleep(5000).then(() => { throw new Error("Timed out waiting for models.list"); }),
      ]) as { ok: boolean; result: { models: unknown[] } };
      expect(response.ok).toBe(true);
      expect(Array.isArray(response.result.models)).toBe(true);
      for (const model of response.result.models) {
        expect(model).toMatchObject({
          provider: expect.any(String),
          id: expect.any(String),
          name: expect.any(String),
          contextWindow: expect.any(Number),
          maxTokens: expect.any(Number),
          reasoning: expect.any(Boolean),
          supportsImages: expect.any(Boolean),
          supportsFastMode: expect.any(Boolean),
        });
      }
    } finally {
      child.stdin.end();
      await child.exited;
    }
  });

  test("returns a stable error when selecting an unknown model", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-model-test-"));
    const cwd = join(root, "project");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "create-for-model",
        method: "session.createDraft",
        params: { cwd, sessionDirectory, profile: "chat" },
      })}\n`);
      await child.stdin.flush();
      const created = await lines.read() as { result: { session: { id: string } } };

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "set-missing-model",
        method: "session.setModel",
        params: {
          sessionId: created.result.session.id,
          provider: "missing-provider",
          modelId: "missing-model",
        },
      })}\n`);
      await child.stdin.flush();

      expect(await lines.read()).toEqual({
        version: 1,
        kind: "response",
        id: "set-missing-model",
        ok: false,
        error: {
          code: "model_not_found",
          message: "Model not found: missing-provider/missing-model",
        },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("sets thinking level on an open Pi session", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-thinking-test-"));
    const cwd = join(root, "project");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "create-for-thinking",
        method: "session.createDraft",
        params: { cwd, sessionDirectory, profile: "chat" },
      })}\n`);
      await child.stdin.flush();
      const created = await lines.read() as { result: { session: { id: string } } };

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "set-thinking",
        method: "session.setThinkingLevel",
        params: {
          sessionId: created.result.session.id,
          thinkingLevel: "high",
        },
      })}\n`);
      await child.stdin.flush();

      expect(await lines.read()).toMatchObject({
        version: 1,
        kind: "response",
        id: "set-thinking",
        ok: true,
        result: {
          sessionId: created.result.session.id,
          thinkingLevel: expect.any(String),
          availableThinkingLevels: expect.any(Array),
        },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("changes the access mode of an open Work session", async () => {
    const root = mkdtempSync(join(tmpdir(), "pi-work-host-access-test-"));
    const cwd = join(root, "project");
    const sessionDirectory = join(root, "sessions");
    mkdirSync(cwd, { recursive: true });
    const child = Bun.spawn({
      cmd: [process.execPath, "run", join(import.meta.dir, "../src/main.ts")],
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      const lines = new JSONLineReader(child.stdout.getReader());
      await lines.read();
      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "create-for-access",
        method: "session.createDraft",
        params: { cwd, sessionDirectory, profile: "work" },
      })}\n`);
      await child.stdin.flush();
      const created = await lines.read() as { result: { session: { id: string } } };

      child.stdin.write(`${JSON.stringify({
        version: 1,
        kind: "request",
        id: "set-access",
        method: "session.setAccessMode",
        params: {
          sessionId: created.result.session.id,
          accessMode: "full",
        },
      })}\n`);
      await child.stdin.flush();

      expect(await lines.read()).toEqual({
        version: 1,
        kind: "response",
        id: "set-access",
        ok: true,
        result: {
          sessionId: created.result.session.id,
          accessMode: "full",
        },
      });
    } finally {
      child.stdin.end();
      await child.exited;
      rmSync(root, { recursive: true, force: true });
    }
  });
});
