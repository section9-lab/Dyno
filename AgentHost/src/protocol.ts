import type { ImageContent } from "@earendil-works/pi-ai";

export const PROTOCOL_VERSION = 1 as const;

const maxPromptImageCount = 5;
const maxPromptImageBytes = Math.floor(4.5 * 1024 * 1024);
const maxPromptImagesBytes = 12 * 1024 * 1024;
const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

export class PromptImagesError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

type HostHelloPayload = {
  hostVersion: string;
  piVersion: string;
  capabilities: string[];
};

export type HostHelloRecord = {
  version: typeof PROTOCOL_VERSION;
  kind: "event";
  event: "host.hello";
  payload: HostHelloPayload;
};

export type HostRequest = {
  version: typeof PROTOCOL_VERSION;
  kind: "request";
  id: string;
  method: string;
  params?: Record<string, unknown>;
};

export type HostResponse = {
  version: typeof PROTOCOL_VERSION;
  kind: "response";
  id: string;
  ok: boolean;
  result?: unknown;
  error?: { code: string; message: string };
};

export function createHostHelloRecord(payload: HostHelloPayload): HostHelloRecord {
  return {
    version: PROTOCOL_VERSION,
    kind: "event",
    event: "host.hello",
    payload,
  };
}

export function encodeRecord(record: unknown): string {
  return `${JSON.stringify(record)}\n`;
}

export function parsePromptImages(value: unknown): ImageContent[] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) {
    throw new PromptImagesError("invalid_image", "Prompt images must be an array");
  }
  if (value.length > maxPromptImageCount) {
    throw new PromptImagesError(
      "too_many_images",
      `A prompt can include at most ${maxPromptImageCount} images`,
    );
  }

  let totalBytes = 0;
  return value.map((item): ImageContent => {
    if (!item || typeof item !== "object") {
      throw new PromptImagesError("invalid_image", "Prompt image must be an object");
    }
    const mimeType = "mimeType" in item ? item.mimeType : undefined;
    const data = "data" in item ? item.data : undefined;
    if (mimeType !== "image/png" && mimeType !== "image/jpeg") {
      throw new PromptImagesError(
        "invalid_image",
        "Prompt images must use image/png or image/jpeg",
      );
    }
    if (typeof data !== "string" || data.length === 0 || data.length % 4 !== 0) {
      throw new PromptImagesError("invalid_image", "Prompt image data is not valid base64");
    }

    const bytes = Buffer.from(data, "base64");
    if (bytes.toString("base64") !== data) {
      throw new PromptImagesError("invalid_image", "Prompt image data is not valid base64");
    }
    if (bytes.length > maxPromptImageBytes) {
      throw new PromptImagesError(
        "image_too_large",
        "Each prompt image must be at most 4.5 MiB",
      );
    }
    totalBytes += bytes.length;
    if (totalBytes > maxPromptImagesBytes) {
      throw new PromptImagesError(
        "images_too_large",
        "Prompt images must be at most 12 MiB in total",
      );
    }

    const matchesMimeType = mimeType === "image/png"
      ? bytes.subarray(0, pngSignature.length).equals(pngSignature)
      : bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
    if (!matchesMimeType) {
      throw new PromptImagesError(
        "invalid_image",
        `Prompt image data does not match ${mimeType}`,
      );
    }

    return { type: "image", mimeType, data };
  });
}
