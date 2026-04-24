# Repo Agents Instructions

This repository uses a two‑phase workflow:

1. Brainstorming Ideas Into Designs (pre‑implementation)
2. ExecPlans (design → implementation)

## 1. Brainstorming Ideas Into Designs (Pre‑Implementation Phase)

Brainstorming Ideas Into Designs.
Help turn ideas into fully formed designs and specs through natural collaborative dialogue.
Start by understanding the current project context, then ask questions one at a time to refine the idea.
Once you understand what you're building, present the design and get user approval.
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it.
This applies to EVERY project regardless of perceived simplicity.

When starting ANY new task (feature, refactor, config, documentation structure, etc.) you MUST:

1. Explore the current project context (files, docs, recent changes).
2. Ask clarifying questions one at a time until the goal and constraints are clear.
3. Propose one or more design options with trade‑offs and a recommendation.
4. Present a concise design/spec and get explicit user approval before any implementation.

## 2. ExecPlans (Design → Implementation Phase)

When writing complex features or significant refactors, AFTER the design has been approved,
use an ExecPlan (as described in .agent/template/PLAN.md) from design to implementation.

ExecPlans are living documents that:
- Are fully self‑contained (no external memory beyond the working tree and the plan file itself).
- Contain milestones, validation steps, and logs of decisions.
- Allow a coding agent to continue work or restart from ONLY the ExecPlan + repo state.

Agents MUST:
- Always follow the Brainstorming phase BEFORE creating or modifying ExecPlans.
- Then follow the ExecPlan rules in .agent/template/PLAN.md _to the letter_ during implementation.
