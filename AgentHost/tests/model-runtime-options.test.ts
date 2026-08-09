import { describe, expect, test } from "bun:test";
import { modelRuntimeOptions } from "../src/model-runtime-options.ts";

describe("model runtime options", () => {
  test("isolates app credentials without replacing Pi model configuration", () => {
    expect(modelRuntimeOptions({
      PI_WORK_AUTH_PATH: "/tmp/pi-work/auth.json",
      PI_CODING_AGENT_DIR: "/tmp/pi-cli",
    })).toEqual({ authPath: "/tmp/pi-work/auth.json" });
  });

  test("keeps Pi defaults when the native app does not provide a credential path", () => {
    expect(modelRuntimeOptions({})).toBeUndefined();
    expect(modelRuntimeOptions({ PI_WORK_AUTH_PATH: "  " })).toBeUndefined();
  });
});
