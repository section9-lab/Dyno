import { describe, expect, test } from "bun:test";

import {
  inspectGitBranches,
  type GitCommandRunner,
} from "../src/git-branches.ts";

describe("inspectGitBranches", () => {
  test("returns the current branch and local branches for a Git project", async () => {
    const calls: string[][] = [];
    const run: GitCommandRunner = async (_cwd, args) => {
      calls.push(args);
      if (args[0] === "rev-parse") {
        return { exitCode: 0, stdout: "true\n" };
      }
      if (args[0] === "symbolic-ref") {
        return { exitCode: 0, stdout: "feature/session-branch\n" };
      }
      return {
        exitCode: 0,
        stdout: "feature/session-branch\nmain\nrelease/1.0\n",
      };
    };

    await expect(inspectGitBranches("/tmp/project", run)).resolves.toEqual({
      available: true,
      currentBranch: "feature/session-branch",
      branches: ["feature/session-branch", "main", "release/1.0"],
    });
    expect(calls).toEqual([
      ["rev-parse", "--is-inside-work-tree"],
      ["symbolic-ref", "--quiet", "--short", "HEAD"],
      [
        "for-each-ref",
        "--sort=-committerdate",
        "--format=%(refname:short)",
        "refs/heads/",
      ],
    ]);
  });

  test("returns unavailable for a folder outside a Git repository", async () => {
    const run: GitCommandRunner = async () => ({ exitCode: 128, stdout: "" });

    await expect(inspectGitBranches("/tmp/folder", run)).resolves.toEqual({
      available: false,
      currentBranch: null,
      branches: [],
    });
  });

  test("keeps an unborn current branch selectable", async () => {
    const run: GitCommandRunner = async (_cwd, args) => {
      if (args[0] === "rev-parse") return { exitCode: 0, stdout: "true\n" };
      if (args[0] === "symbolic-ref") return { exitCode: 0, stdout: "main\n" };
      return { exitCode: 0, stdout: "" };
    };

    await expect(inspectGitBranches("/tmp/new-project", run)).resolves.toEqual({
      available: true,
      currentBranch: "main",
      branches: ["main"],
    });
  });

  test("returns unavailable when Git is not installed", async () => {
    const run: GitCommandRunner = async () => {
      throw new Error("ENOENT");
    };

    await expect(inspectGitBranches("/tmp/project", run)).resolves.toEqual({
      available: false,
      currentBranch: null,
      branches: [],
    });
  });
});
