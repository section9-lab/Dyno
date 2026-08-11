import { describe, expect, test } from "bun:test";

import { createHostHelloRecord, encodeRecord } from "../src/protocol.ts";
import * as hostProtocol from "../src/protocol.ts";

type ParsedPromptImage = {
  type: "image";
  mimeType: string;
  data: string;
};

const parsePromptImages = (
  hostProtocol as unknown as {
    parsePromptImages?: (value: unknown) => ParsedPromptImage[];
  }
).parsePromptImages;

const pngData = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function promptImageFailure(value: unknown): { code: string; message: string } | undefined {
  if (!parsePromptImages) return undefined;
  try {
    parsePromptImages(value);
    return undefined;
  } catch (error) {
    if (!error || typeof error !== "object") return undefined;
    return {
      code: "code" in error ? String(error.code) : "",
      message: error instanceof Error ? error.message : "",
    };
  }
}

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

  test("parses an optional valid PNG prompt image", () => {
    expect(parsePromptImages?.([{ mimeType: "image/png", data: pngData }])).toEqual([{
      type: "image",
      mimeType: "image/png",
      data: pngData,
    }]);
    expect(parsePromptImages?.(undefined)).toEqual([]);
  });

  test("rejects unsupported prompt image MIME types", () => {
    expect(promptImageFailure([{ mimeType: "image/gif", data: pngData }])).toEqual({
      code: "invalid_image",
      message: "Prompt images must use image/png or image/jpeg",
    });
  });

  test("rejects prompt image data that does not match its MIME type", () => {
    expect(promptImageFailure([{
      mimeType: "image/jpeg",
      data: pngData,
    }])).toEqual({
      code: "invalid_image",
      message: "Prompt image data does not match image/jpeg",
    });
  });

  test("rejects malformed base64 prompt image data", () => {
    expect(promptImageFailure([{
      mimeType: "image/png",
      data: "not-base64",
    }])).toEqual({
      code: "invalid_image",
      message: "Prompt image data is not valid base64",
    });
  });

  test("rejects a prompt image larger than 4.5 MiB", () => {
    const data = Buffer.concat([
      pngSignature,
      Buffer.alloc(Math.floor(4.5 * 1024 * 1024)),
    ]).toString("base64");

    expect(promptImageFailure([{ mimeType: "image/png", data }])).toEqual({
      code: "image_too_large",
      message: "Each prompt image must be at most 4.5 MiB",
    });
  });

  test("rejects prompt images larger than 12 MiB in total", () => {
    const data = Buffer.concat([
      pngSignature,
      Buffer.alloc(4 * 1024 * 1024),
    ]).toString("base64");

    expect(promptImageFailure(Array.from({ length: 4 }, () => ({
      mimeType: "image/png",
      data,
    })))).toEqual({
      code: "images_too_large",
      message: "Prompt images must be at most 12 MiB in total",
    });
  });

  test("rejects more than five prompt images", () => {
    expect(promptImageFailure(Array.from({ length: 6 }, () => ({
      mimeType: "image/png",
      data: pngData,
    })))).toEqual({
      code: "too_many_images",
      message: "A prompt can include at most 5 images",
    });
  });
});
