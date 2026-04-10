# Sequential Task Automation Prompt

## Objective

Run the PAC1 benchmark tasks sequentially from **task 4 through task 40**. For each task, execute the test, validate success, and if it fails, fix the agent code and retry. Continue until all tasks pass or you've exhausted reasonable debugging attempts.

---

## Execution Protocol

### Phase 1: Task Execution

**For each task number (starting at 4, incrementing to 40):**

1. **Run the test:**
   ```bash
   ./run.sh <TASK_NUMBER>
   ```
   Where `<TASK_NUMBER>` starts at 4.

2. **Capture full output** — The output will contain:
   - Task description and instructions
   - Agent reasoning steps (auto-executed)
   - Tool calls and results
   - Final score and outcome
   - Error messages (if any)

### Phase 2: Success Validation

**Check the output for BOTH of these conditions:**

1. `FINAL: 100.0%` — Must see this line exactly
2. `Score: 1.00` — Must see this exact score

**If BOTH are present:**
- Log: ✓ Task N PASSED
- Move to task N+1
- Repeat Phase 1 with incremented task number

**If either is missing or the task shows errors:**
- Log: ✗ Task N FAILED or had errors
- Go to Phase 3 (Error Analysis)

### Phase 3: Error Analysis & Diagnosis

**When a task fails:**

1. **Extract error indicators** from output:
   - Look for lines containing: `error`, `fail`, `missing`, `denied`, `ERR`, `Score: 0.00`
   - Note file paths mentioned in error messages
   - Record the exact failure reason

2. **Common failure patterns to look for:**
   - `missing file delete '<path>'` — Agent didn't delete a required file
   - `missing file write '<path>'` — Agent didn't create/write a file with correct filename
   - `missing file delete '02_distill/threads/...'` — Agent skipped thread updates
   - `Code.NOT_FOUND` — Agent tried to operate on non-existent file
   - `parse error` — Response token overflow or LLM parsing issue
   - `OUTCOME_ERR_INTERNAL` — Task logic error
   - `Should write in thread document` — Agent skipped thread linking step

3. **Document the failure:**
   - Task number
   - Exact error message
   - What the task required
   - What the agent did instead

### Phase 4: Root Cause Analysis

**Based on the error pattern, identify the cause:**

#### If file deletion failed:
- Agent may have: searched for wrong filename, didn't try extensions, quit too early
- Check `system_prompt` in agent.py for deletion instruction clarity

#### If file write used wrong name:
- Agent abstracted/renamed the filename instead of preserving original
- Check if system prompt mentions: "CRITICAL: use EXACT original filename"

#### If thread update was skipped:
- Agent completed capture/distill but didn't update thread documents
- Check if system prompt mentions thread update as MANDATORY

#### If parse/token errors occurred:
- LLM response hit token limit or format error
- Check the log windowing and pruning logic in `run_agent()` function
- Verify `max_completion_tokens` budget is sufficient for response

#### If agent searched but found nothing:
- Lookup didn't include file extensions (.md)
- Agent didn't list directory to verify actual filenames
- Check system prompt for extension/listing guidance

### Phase 5: Agent Code Fixes

**Based on root cause, edit agent.py to fix:**

#### For filename preservation issues:
```
Location: system_prompt in agent.py
Change: Make "Never rename files" instruction more prominent
Example: Add explicit example showing wrong vs right filename
```

#### For missing thread updates:
```
Location: system_prompt in agent.py
Change: Add "MANDATORY: After creating card, update 1-2 threads"
```

#### For file lookup issues:
```
Location: system_prompt in agent.py
Change: Add "List directory first before assuming file doesn't exist"
Change: Add "Try with and without .md extension"
```

#### For parse/token errors:
```
Location: run_agent() function in agent.py
Change: Reduce windowing threshold (keep fewer messages)
Example: Change "if len(log) > 20" to "if len(log) > 16"
```

#### For early task completion (quit before finishing):
```
Location: run_agent() loop in agent.py
Change: Increase loop limit (currently 30 max steps)
Change: Make parse error recovery less aggressive (don't report completion on first error)
```

### Phase 6: Retry & Iterate

**After making fixes:**

1. Re-run the failed task:
   ```bash
   ./run.sh <TASK_NUMBER>
   ```

2. Check output again for `FINAL: 100.0%` and `Score: 1.00`

3. **If now passing:** Log ✓ and move to next task (task N+1)

4. **If still failing:**
   - Review the error again
   - Identify what changed (if anything) in the output
   - If error persists unchanged, you may need deeper debugging:
     - Add detailed logging to the agent
     - Check if system prompt changes are being applied
     - Verify the file/task expectations match what grader expects
   - Apply new fix and retry

5. **If you've retried 2-3 times with similar errors:**
   - Collect all the error messages
   - Summarize the pattern (e.g., "agent keeps naming files without dates")
   - Propose a larger prompt/logic restructuring instead of incremental fixes

### Phase 7: Loop Control

**Continue this process:**
- **Start:** Task 4
- **End:** Task 40 (or first task to reach `FINAL: 100.0%` and `Score: 1.00`)
- **Checkpoint:** After every 5 tasks passing, summarize progress

**Stop conditions:**
- All tasks 4-40 now report 100% and score 1.00 ✓
- A task fails and debugging reveals it requires a fundamental agent redesign (not just prompt tweaks)
- You've hit a known blocker that requires new system capability

---

## Key Principles

1. **Validate completely:** Don't assume partial success. Both `FINAL: 100.0%` AND `Score: 1.00` must be present.

2. **Read the full output:** Error messages often appear in the middle/end. Don't stop reading after the first error line.

3. **Preserve filenames aggressively:** The system now has explicit rules. If a task still fails on filename, make the prompt even more explicit.

4. **Check threading:** Many knowledge repo tasks require thread updates. If a card is created, verify a thread was also updated.

5. **Handle token limits gracefully:** If parse errors appear after many steps, the agent may be running out of response budget. Reduce context window size, not task complexity.

6. **Batch similar fixes:** If multiple tasks fail for the same reason (e.g., missing thread updates), fix the agent once and re-run all failed tasks.

---

## Progress Tracking Template

```
Task 4:  [  ] Run  [  ] Pass  [  ] Fix  [  ] Retry
Task 5:  [  ] Run  [  ] Pass  [  ] Fix  [  ] Retry
Task 6:  [  ] Run  [  ] Pass  [  ] Fix  [  ] Retry
...
Task 40: [  ] Run  [  ] Pass  [  ] Fix  [  ] Retry

Summary:
- Total passed: __/37 tasks
- Common failure pattern: ____________
- Last fix applied: ____________
```

---

## Quick Reference: Common Fixes

| Error | Likely Cause | Fix |
|-------|--------------|-----|
| `missing file delete '<path>'` | Didn't delete or searched wrong name | Add deletion guidance to prompt; mention .md extension |
| `missing file write '<path>'` | Created with wrong filename | Strengthen "CRITICAL: use EXACT original filename" rule |
| `Should write in thread` | Skipped thread update | Add "MANDATORY: update threads after card" to prompt |
| `parse error` x3+ | Token limit hit | Reduce context window `if len(log) > 20` → `if len(log) > 16` |
| `Code.NOT_FOUND` + `parse error` | File lookup failed then agent confused | Add "list dir first" guidance; prevent quit on first error |
| `OUTCOME_ERR_INTERNAL` | Agent crashed or errored | Review last few steps' tool calls for logic errors |
| `Score: 0.00` after write | File path/content wrong | Check system prompt for file naming + content rules |

---

## When to Ask for Help

- If a task fails and you can't identify the root cause from the error message
- If the same error persists after 3 prompt fix attempts
- If fixing one task breaks another task
- If agent behavior contradicts the system prompt (prompt not being followed)

In these cases, provide:
1. Task number and full error output
2. What the task requires (from task description)
3. What the agent did instead
4. What prompt/code changes have been tried
