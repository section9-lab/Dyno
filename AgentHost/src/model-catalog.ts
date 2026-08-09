import type { ModelRuntime } from "@earendil-works/pi-coding-agent";

import type { SessionModel } from "./session-registry.ts";

type PiModel = Awaited<ReturnType<ModelRuntime["getAvailable"]>>[number];

const fastModeModelIds = new Set([
  "gpt-5.4",
  "gpt-5.4-mini",
  "gpt-5.4-nano",
  "gpt-5.4-pro",
  "gpt-5.5",
  "gpt-5.5-pro",
  "gpt-5.6-luna",
  "gpt-5.6-sol",
  "gpt-5.6-terra",
]);

export function supportsFastMode(model: PiModel | undefined): boolean {
  if (!model || !fastModeModelIds.has(model.id)) return false;
  return (model.provider === "openai" && model.api === "openai-responses")
    || (model.provider === "openai-codex" && model.api === "openai-codex-responses");
}

export async function listAvailableModels(
  runtime: Pick<ModelRuntime, "getAvailable">,
): Promise<SessionModel[]> {
  return (await runtime.getAvailable()).map(normalizeModel);
}

export function normalizeModel(model: PiModel): SessionModel {
  return {
    provider: model.provider,
    id: model.id,
    name: model.name,
    contextWindow: model.contextWindow,
    maxTokens: model.maxTokens,
    reasoning: model.reasoning,
    supportsImages: model.input.includes("image"),
    supportsFastMode: supportsFastMode(model),
  };
}
