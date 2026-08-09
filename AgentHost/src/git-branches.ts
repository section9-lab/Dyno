export type GitCommandResult = {
  exitCode: number;
  stdout: string;
};

export type GitCommandRunner = (
  cwd: string,
  args: string[],
) => Promise<GitCommandResult>;

export type GitBranchesSnapshot = {
  available: boolean;
  currentBranch: string | null;
  branches: string[];
};

const unavailableSnapshot: GitBranchesSnapshot = {
  available: false,
  currentBranch: null,
  branches: [],
};

const runGitCommand: GitCommandRunner = async (cwd, args) => {
  const process = Bun.spawn(["git", ...args], {
    cwd,
    stdout: "pipe",
    stderr: "ignore",
  });
  const [exitCode, stdout] = await Promise.all([
    process.exited,
    new Response(process.stdout).text(),
  ]);
  return { exitCode, stdout };
};

export async function inspectGitBranches(
  cwd: string,
  run: GitCommandRunner = runGitCommand,
): Promise<GitBranchesSnapshot> {
  try {
    const repository = await run(cwd, ["rev-parse", "--is-inside-work-tree"]);
    if (repository.exitCode !== 0 || repository.stdout.trim() !== "true") {
      return unavailableSnapshot;
    }

    const current = await run(cwd, ["symbolic-ref", "--quiet", "--short", "HEAD"]);
    const refs = await run(cwd, [
      "for-each-ref",
      "--sort=-committerdate",
      "--format=%(refname:short)",
      "refs/heads/",
    ]);
    if (refs.exitCode !== 0) return unavailableSnapshot;

    const currentBranch = current.exitCode === 0 ? current.stdout.trim() || null : null;
    const branches = refs.stdout
      .split(/\r?\n/)
      .map((branch) => branch.trim())
      .filter(Boolean);
    if (currentBranch && !branches.includes(currentBranch)) {
      branches.unshift(currentBranch);
    }

    return {
      available: true,
      currentBranch,
      branches,
    };
  } catch {
    return unavailableSnapshot;
  }
}
