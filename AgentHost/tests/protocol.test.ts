import { describe, expect, test } from "bun:test";

import { createHostHelloRecord, encodeRecord } from "../src/protocol.ts";

describe("host protocol", () => {
  test("encodes the version handshake as one LF-terminated JSON record", () => {
    const line = encodeRecord(
      createHostHelloRecord({
        hostVersion: "0.1.0",
        piVersion: "0.83.0",
        capabilities: ["sessions.list", "session.createDraft"],
      }),
    );

    expect(line.endsWith("\n")).toBe(true);
    expect(line.slice(0, -1)).not.toContain("\n");
    expect(JSON.parse(line)).toEqual({
      version: 1,
      kind: "event",
      event: "host.hello",
      payload: {
        hostVersion: "0.1.0",
        piVersion: "0.83.0",
        capabilities: ["sessions.list", "session.createDraft"],
      },
    });
  });
});
