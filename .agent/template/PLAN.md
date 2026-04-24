# Codex Execution Plans (ExecPlans) with Brainstorming

This document describes the requirements for an execution plan ("ExecPlan"), a design document that a coding agent can follow to deliver a working feature or system change. Treat the reader as a complete beginner to this repository: they have only the current working tree and the single ExecPlan file you provide. There is no memory of prior plans and no external context.

## 0. Brainstorming Ideas Into Designs (Required Pre‑ExecPlan Phase)

Brainstorming Ideas Into Designs.
Help turn ideas into fully formed designs and specs through natural collaborative dialogue.
Start by understanding the current project context, then ask questions one at a time to refine the idea.
Once you understand what you're building, present the design and get user approval.
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it.
This applies to EVERY project regardless of perceived simplicity.

Before you create or modify an ExecPlan, you MUST:

1. Explore the current project context (files, docs, recent changes).
2. Ask clarifying questions one at a time until the goal and constraints are clear.
3. Propose one or more design options and get explicit user approval of the chosen design.
4. Only after approval, proceed to author or update the ExecPlan described below.

## 1. How to use ExecPlans and this PLAN.md

When authoring an executable specification (ExecPlan), follow this PLAN.md _to the letter_. If it is not in your context, refresh your memory by reading the entire PLAN.md file. Be thorough in reading (and re‑reading) source material to produce an accurate specification. When creating a spec, start from the skeleton and flesh it out as you do your research.

When implementing an executable specification (ExecPlan), do not prompt the user for "next steps"; simply proceed to the next milestone. Keep all sections up to date, add or split entries in the list at every stopping point to affirmatively state the progress made and next steps. Resolve ambiguities autonomously, and commit frequently.

When discussing an executable specification (ExecPlan), record decisions in a log in the spec for posterity; it should be unambiguously clear why any change to the specification was made. ExecPlans are living documents, and it should always be possible to restart from _only_ the ExecPlan and no other work.

When researching a design with challenging requirements or significant unknowns, use milestones to implement proof of concepts, "toy implementations", etc., that allow validating whether the user's proposal is feasible. Read the source code of libraries by finding or acquiring them, research deeply, and include prototypes to guide a fuller implementation.

## 2. ExecPlan Skeleton (to be filled by the agent)

Every ExecPlan MUST at least include the following sections:

1. Context
   - What problem are we solving?
   - What files / systems are involved?
   - What prior designs or docs are relevant?

2. Goals and Non‑Goals
   - Explicitly list what success looks like.
   - Explicitly list what is out of scope.

3. Plan / Milestones
   - A numbered list of milestones, each small enough to implement and validate.
   - For each milestone, describe:
     - The concrete change to make.
     - How you will validate it (tests, manual steps, metrics).

4. Implementation Notes
   - Key design decisions and trade‑offs.
   - Risks and mitigation strategies.
   - Any external dependencies or follow‑up work.

5. Validation
   - How to verify the whole change end‑to‑end.
   - Which tests or checks MUST pass before considering the plan done.

6. Log / Journal
   - As you work, append entries with:
     - Timestamp.
     - What milestone you worked on.
     - What changed and why.
     - Any surprises or deviations from the original plan.

## 3. Non‑Negotiable Requirements

NON‑NEGOTIABLE REQUIREMENTS:

- Every ExecPlan must be fully self‑contained.
  - Self‑contained means that in its current form it contains all information needed for an agent to understand and execute the plan, given only the current working tree and this plan file.
- ExecPlans MUST NOT reference prior, superseded specs as required reading.
- ExecPlans MUST be kept up to date as work progresses.
- ExecPlans MUST always reflect the actual state of the work and the next steps.

