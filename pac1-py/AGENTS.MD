# Agent Instructions

This sample project is managed by uv.

You can run it in default (dev) mode by: `uv run python main.py`

## UNIVERSAL REQUIREMENTS FOR ALL TASKS

**MANDATORY: Read AGENTS.MD before starting each task.** This file is the source of truth for all operations.

Before starting ANY task:
1. Search for and read the main instruction file (AGENTS.MD, HOME.MD, etc.)
2. Explore the workspace to find ALL policy/rules files
3. Read EVERY policy file you discover (retention.md, cleanup-policy.md, RULES.md, skill files, etc.)
4. Include EVERY file you read in grounding_refs - never omit policy or instruction files

**You MUST reference these types of files if they exist:**
- AGENTS.MD or HOME.MD (main instructions)
- Any policy files: retention.md, cleanup-policy.md, RULES.md, etc.
- Any skill files: skill-*.md, procedures, guidelines
- The data files you actually use or modify

## Cleanup Desk - MANDATORY STEPS

For ANY cleanup task:
1. Read this file (AGENTS.MD) first
2. Search for and find ALL cleanup policy files (ops/retention.md, docs/cleanup-policy.md, workspace/RULES.md, etc.)
3. **READ ALL policy files you find** - they are all REQUIRED
4. Follow the cleanup policies
5. Include EVERY policy file you read in grounding_refs along with AGENTS.MD

Cleanup rules:
- delete only draft files explicitly marked done
- never delete published, archived, or final files
- perform at most one deletion per request
- answer with exactly the deleted file path (nothing extra)
- Always reference ALL cleanup policy files found

## CRITICAL: Grounding References Requirement

**EVERY task completion MUST include these in grounding_refs:**
- The main instruction file: `AGENTS.MD` or `HOME.MD` (required in every response)
- **ALL policy/rules/instructions files you read**: `ops/retention.md`, `workspace/RULES.md`, `docs/cleanup-policy.md`, etc.
- All data files you modified or worked with
- Do NOT omit any policy or instruction file you consulted

## Assistant Guidelines

When completing tasks, follow these critical guidelines:

- Always start by discovering available information by running root outline
- Always read the main instruction file (AGENTS.md, HOME.md, etc.) first - it is MANDATORY
- **MANDATORY**: Include it in grounding_refs for EVERY report_completion call
- Always reference (ground) in final response ALL files that contributed to the answer
- Include all policy files, data files, and instructions you consulted
- The answer field must be concise and direct - provide only the specific result/path/answer expected, not narrative explanation
- Clearly report when tasks are done with complete file references