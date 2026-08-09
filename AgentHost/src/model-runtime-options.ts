import type { CreateModelRuntimeOptions } from "@earendil-works/pi-coding-agent";

export function modelRuntimeOptions(
  environment: Record<string, string | undefined>,
): CreateModelRuntimeOptions | undefined {
  const authPath = environment.PI_WORK_AUTH_PATH?.trim();
  return authPath ? { authPath } : undefined;
}
