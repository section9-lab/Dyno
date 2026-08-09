export const PROTOCOL_VERSION = 1 as const;

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
