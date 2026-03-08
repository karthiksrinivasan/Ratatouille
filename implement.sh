#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Ratatouille Epic Implementation Orchestrator
#
# Drives Claude Code in non-interactive mode to implement each epic
# sequentially, with validation passes and context management.
#
# Usage:
#   ./implement.sh                  # Run all epics from the beginning
#   ./implement.sh --from 3         # Resume from epic 3
#   ./implement.sh --only 2         # Run only epic 2
#   ./implement.sh --from-task 4.6  # Resume from task 4.6 within epic 4
#   ./implement.sh --dry-run        # Show plan without executing
###############################################################################

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
EPICS_DIR="${PROJECT_ROOT}/epics"
STATE_DIR="${PROJECT_ROOT}/.epic-state"
LOG_DIR="${PROJECT_ROOT}/.epic-logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Epic execution order (respects dependency graph from index.md)
EPIC_ORDER=(1 2 3 4 5 6 7)

# CLI args
FROM_EPIC=1
FROM_TASK=""
ONLY_EPIC=""
DRY_RUN=false
MODEL="opus"

while [[ $# -gt 0 ]]; do
    case $1 in
        --from)      FROM_EPIC="$2"; shift 2 ;;
        --from-task) FROM_TASK="$2"; shift 2 ;;
        --only)      ONLY_EPIC="$2"; shift 2 ;;
        --dry-run)   DRY_RUN=true; shift ;;
        --model)     MODEL="$2"; shift 2 ;;
        --reset)     rm -rf "$STATE_DIR"; echo "State reset."; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# If --from-task is set, derive the epic number from it
if [[ -n "$FROM_TASK" ]]; then
    FROM_EPIC="${FROM_TASK%%.*}"
fi

mkdir -p "$STATE_DIR" "$LOG_DIR"

###############################################################################
# Helpers
###############################################################################

log()         { echo "[$(date '+%H:%M:%S')] $*"; }
log_section() { echo ""; echo "═══════════════════════════════════════════════════════"; echo "  $*"; echo "═══════════════════════════════════════════════════════"; }

get_epic_filename() {
    ls "$EPICS_DIR" | grep "^epic-${1}-" | head -1
}

# --- State: epic-level ---
mark_done()      { touch "${STATE_DIR}/epic-${1}.done"; }
mark_validated() { touch "${STATE_DIR}/epic-${1}.validated"; }
is_done()        { [[ -f "${STATE_DIR}/epic-${1}.done" ]]; }
is_validated()   { [[ -f "${STATE_DIR}/epic-${1}.validated" ]]; }

# --- State: task-level ---
# Stores completed task IDs (e.g. "2.1", "2.2") one per line
TASK_STATE_FILE() { echo "${STATE_DIR}/epic-${1}.tasks"; }

mark_task_done() {
    local epic=$1 task=$2
    echo "$task" >> "$(TASK_STATE_FILE "$epic")"
}

is_task_done() {
    local epic=$1 task=$2
    [[ -f "$(TASK_STATE_FILE "$epic")" ]] && grep -qxF "$task" "$(TASK_STATE_FILE "$epic")"
}

get_completed_tasks() {
    local epic=$1
    if [[ -f "$(TASK_STATE_FILE "$epic")" ]]; then
        cat "$(TASK_STATE_FILE "$epic")"
    fi
}

# Extract task IDs from an epic file (e.g. "2.1", "2.2", ...)
get_task_ids() {
    local epic_num=$1
    local epic_file="${EPICS_DIR}/$(get_epic_filename "$epic_num")"
    grep -oE "^### ${epic_num}\.[0-9]+" "$epic_file" | sed "s/^### //"
}

###############################################################################
# Preflight checks
###############################################################################

preflight() {
    log "Running preflight checks..."
    local failed=false

    # Claude CLI available
    if ! command -v claude &>/dev/null; then
        log "FATAL: 'claude' CLI not found in PATH"
        failed=true
    fi

    # Git available and in a repo
    if ! git rev-parse --git-dir &>/dev/null; then
        log "FATAL: not inside a git repository"
        failed=true
    fi

    # Working tree clean (unstaged + staged changes)
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        log "FATAL: git working tree is dirty — commit or stash changes before running"
        log "  Staged:   $(git diff --cached --name-only | wc -l | tr -d ' ') file(s)"
        log "  Unstaged: $(git diff --name-only | wc -l | tr -d ' ') file(s)"
        failed=true
    fi

    # Epic index exists
    if [[ ! -f "${EPICS_DIR}/index.md" ]]; then
        log "FATAL: epics/index.md not found"
        failed=true
    fi

    # CLAUDE.md exists
    if [[ ! -f "${PROJECT_ROOT}/CLAUDE.md" ]]; then
        log "WARNING: CLAUDE.md not found — Claude sessions won't have project conventions"
    fi

    # Python available (for build checks)
    if ! command -v python3 &>/dev/null; then
        log "WARNING: python3 not found — build checks will be skipped"
    fi

    # Verify all epic files exist
    for e in "${EPIC_ORDER[@]}"; do
        local fname
        fname=$(get_epic_filename "$e" 2>/dev/null || true)
        if [[ -z "$fname" ]]; then
            log "FATAL: no epic file found for epic ${e}"
            failed=true
        fi
    done

    if $failed; then
        log "Preflight checks failed. Aborting."
        exit 1
    fi

    log "Preflight checks passed."
}

###############################################################################
# Build / smoke check — verifies the backend can import after an epic
###############################################################################

run_build_check() {
    local epic_num=$1

    # Only run if backend directory and requirements.txt exist
    if [[ ! -d "${PROJECT_ROOT}/backend" ]]; then
        log "Build check: no backend/ directory yet — skipping (expected for early epics)"
        return 0
    fi

    if [[ ! -f "${PROJECT_ROOT}/backend/requirements.txt" ]]; then
        log "Build check: no requirements.txt yet — skipping"
        return 0
    fi

    log "Running build/smoke check after Epic ${epic_num}..."

    # Create/reuse a venv for checks
    local venv_dir="${PROJECT_ROOT}/.epic-venv"
    if [[ ! -d "$venv_dir" ]]; then
        python3 -m venv "$venv_dir" 2>/dev/null || {
            log "WARNING: could not create venv — skipping build check"
            return 0
        }
    fi

    # Install deps quietly
    (
        source "${venv_dir}/bin/activate"
        cd "${PROJECT_ROOT}/backend"
        pip install -r requirements.txt -q 2>&1 | tail -1
    ) || {
        log "WARNING: pip install failed — dependency issue detected"
        return 1
    }

    # Try importing the app
    (
        source "${venv_dir}/bin/activate"
        cd "${PROJECT_ROOT}/backend"
        python -c "from app.main import app; print('Smoke check: app imports OK')" 2>&1
    ) || {
        log "ERROR: app import failed after Epic ${epic_num} — broken imports detected"
        return 1
    }

    log "Build check passed."
    return 0
}

###############################################################################
# Build context prompt for implementation
###############################################################################

build_context() {
    local epic_num=$1
    local resume_task="${2:-}"  # Optional: task ID to resume from

    cat <<'CONTEXT_HEADER'
You are implementing a hackathon project called "Ratatouille" — a live cooking companion app.
You are working in a repository that has the full PRD, tech guide, and epic specifications.
The CLAUDE.md file in the project root has all conventions — you have already loaded it.

KEY RULES:
1. Read the epic file AND the referenced PRD/tech guide sections before writing any code.
2. Implement ALL tasks in the epic sequentially.
3. Use subagents (the Agent tool) to parallelize independent tasks within the epic.
4. After implementing each task, verify its acceptance criteria.
5. Write clean, production-quality code — not throwaway hackathon code.
6. Follow the project conventions in CLAUDE.md (async everywhere, Pydantic models, etc.)
7. Do NOT modify files from previous epics unless the current epic explicitly requires it (e.g., mounting a new router).
8. If a task requires infrastructure setup (GCP commands), create the code artifacts but note that GCP commands should be run separately.

GIT COMMIT WORKFLOW — THIS IS CRITICAL:
You MUST create a git commit after completing EACH individual task in the epic.
Follow this exact workflow for every task:

  1. Implement task N.M
  2. Verify its acceptance criteria
  3. Stage ONLY the files you created/modified for this task:
       git add <specific files>
  4. Commit with a conventional commit message following this format:
       feat(epic-N): task N.M — <short description>
     Example:
       feat(epic-2): task 2.1 — recipe CRUD endpoints
       feat(epic-2): task 2.2 — technique tag extraction via Gemini
  5. Move on to the next task

DO NOT batch multiple tasks into a single commit.
DO NOT use "git add -A" or "git add ." — always add specific files.
DO NOT skip commits — every task gets its own commit.
If a task modifies an existing file from a previous task in the same epic, that is fine — commit the updated file.

At the end of the epic, after all tasks are committed, create one final commit for any remaining cleanup:
  chore(epic-N): final cleanup and wiring

CONTEXT_HEADER

    echo ""
    echo "=== EPIC TO IMPLEMENT ==="
    echo "You are implementing Epic ${epic_num}."
    echo "Read the file: epics/$(get_epic_filename "$epic_num")"
    echo ""
    echo "=== AVAILABLE REFERENCE FILES ==="
    echo "- epics/index.md (architecture overview, conventions, project structure)"
    echo "- RATATOUILLE_HACKATHON_PRD.md (product requirements)"
    echo "- GOOGLE_CLOUD_TECH_GUIDE.md (implementation patterns)"
    echo ""

    # Handle task-level resume
    if [[ -n "$resume_task" ]]; then
        echo "=== RESUME POINT ==="
        echo "Tasks already completed in this epic (DO NOT re-implement these):"
        local completed
        completed=$(get_completed_tasks "$epic_num")
        if [[ -n "$completed" ]]; then
            echo "$completed" | while read -r t; do echo "  - Task $t (DONE)"; done
        fi
        echo ""
        echo "START from task ${resume_task}. Skip all tasks before it."
        echo "Read the existing code from earlier tasks to understand the current state."
        echo ""
    fi

    # Tell it about previously completed epics for context
    if [[ $epic_num -gt 1 ]]; then
        echo "=== PREVIOUSLY COMPLETED EPICS ==="
        for prev in $(seq 1 $((epic_num - 1))); do
            local prev_file
            prev_file=$(get_epic_filename "$prev" 2>/dev/null || true)
            if [[ -n "$prev_file" ]]; then
                echo "- Epic ${prev}: epics/${prev_file} (COMPLETED — read if you need context on what was built)"
            fi
        done
        echo ""
        echo "IMPORTANT: Before starting, read the existing codebase to understand what's already been built."
        echo "Use the Agent tool or Glob/Grep to explore the current project structure."
        echo ""
    fi

    echo "=== INSTRUCTIONS ==="
    echo "1. Start by reading epics/$(get_epic_filename "$epic_num") thoroughly."
    echo "2. Read epics/index.md for conventions and project structure."
    echo "3. Read relevant sections of RATATOUILLE_HACKATHON_PRD.md and GOOGLE_CLOUD_TECH_GUIDE.md as referenced in the epic."
    echo "4. Explore the existing codebase to understand what's already built."
    echo "5. For EACH task in the epic:"
    echo "   a. Implement the task (use subagents for independent sub-work if helpful)."
    echo "   b. Verify acceptance criteria."
    echo "   c. Stage the specific files and commit: feat(epic-${epic_num}): task N.M — description"
    echo "6. After all tasks, do a final cleanup commit if needed."
    echo ""
    echo "REMEMBER: One commit per task. Do not batch. Do not skip commits."
    echo ""
    echo "BEGIN IMPLEMENTATION OF EPIC ${epic_num} NOW."
}

###############################################################################
# Build validation prompt (with smoke test instructions)
###############################################################################

build_validation_prompt() {
    local epic_num=$1

    cat <<VALIDATION_PROMPT
You are a code reviewer validating the implementation of Epic ${epic_num} for the Ratatouille hackathon project.

YOUR TASK:
1. Read the epic specification: epics/$(get_epic_filename "$epic_num")
2. Read the project conventions: CLAUDE.md and epics/index.md
3. Explore the codebase to find all files created/modified for this epic.
4. Check EVERY acceptance criterion in the epic against the actual implementation.
5. Check for:
   - Missing files or endpoints
   - Incorrect imports or broken references
   - Missing error handling
   - Deviations from the specified data models
   - Security issues (missing auth, exposed secrets)
   - Convention violations (sync instead of async, missing Pydantic models, etc.)

SMOKE TEST — CRITICAL:
Run the following command to verify the backend can import without errors:
  cd backend && python3 -c "from app.main import app; print('Import OK')"

If the import fails, diagnose and fix the root cause (missing __init__.py, circular imports,
bad imports, missing dependencies in requirements.txt, etc.) before continuing validation.

If specific modules were added by this epic, also test importing them individually:
  python3 -c "from app.routers.X import router"
  python3 -c "from app.models.X import SomeModel"
  python3 -c "from app.agents.X import SomeAgent"

OUTPUT FORMAT:
Produce a structured report:

## Epic ${epic_num} Validation Report

### Status: PASS | FAIL | PARTIAL

### Smoke Test: PASS | FAIL
(include the actual output)

### Task Checklist:
- [ ] Task X.Y: description — PASS/FAIL (details)

### Issues Found:
1. [SEVERITY] Description of issue + file:line
   Fix: What needs to change

### Missing Items:
- List anything from acceptance criteria not yet implemented

If status is FAIL or PARTIAL, fix the issues you found. Use the Edit tool to make corrections.
After fixing, re-run the smoke test to confirm the fix works.
Then re-verify the acceptance criteria.

COMMIT VERIFICATION:
Run "git log --oneline" and verify there is a separate commit for each task in this epic.
Expected pattern: "feat(epic-${epic_num}): task N.M — ..."
If tasks were batched into a single commit, note this in the report but do not attempt to rewrite history.

Commit any fixes with a message like "fix(epic-${epic_num}): address validation findings"
VALIDATION_PROMPT
}

###############################################################################
# Run implementation pass for one epic
###############################################################################

run_implementation() {
    local epic_num=$1
    local resume_task="${2:-}"
    local log_file="${LOG_DIR}/epic-${epic_num}-implement-${TIMESTAMP}.log"
    local prompt
    prompt=$(build_context "$epic_num" "$resume_task")

    log "Starting implementation of Epic ${epic_num}..."
    [[ -n "$resume_task" ]] && log "Resuming from task ${resume_task}"
    log "Log: ${log_file}"

    if $DRY_RUN; then
        log "[DRY RUN] Would run claude with implementation prompt for Epic ${epic_num}"
        echo "$prompt" > "${log_file}.prompt.txt"
        return 0
    fi

    local start_time=$SECONDS

    claude -p \
        --model "$MODEL" \
        --permission-mode bypassPermissions \
        --verbose \
        "$prompt" \
        2>&1 | tee "$log_file"

    local exit_code=${PIPESTATUS[0]}
    local elapsed=$(( SECONDS - start_time ))
    log "Implementation took $(( elapsed / 60 ))m $(( elapsed % 60 ))s"

    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: Implementation of Epic ${epic_num} failed (exit code: ${exit_code})"
        # Record which tasks were completed by scanning git log
        record_completed_tasks "$epic_num"
        return 1
    fi

    # Record completed tasks from git log
    record_completed_tasks "$epic_num"

    mark_done "$epic_num"
    log "Implementation of Epic ${epic_num} complete."
}

###############################################################################
# Scan git log to record which tasks were committed
###############################################################################

record_completed_tasks() {
    local epic_num=$1
    local task_file
    task_file=$(TASK_STATE_FILE "$epic_num")

    # Extract task IDs from commit messages like "feat(epic-2): task 2.3 — ..."
    git log --oneline --all | grep -oE "task ${epic_num}\.[0-9]+" | sed "s/task //" | sort -t. -k2 -n | uniq > "$task_file" 2>/dev/null || true

    local count
    count=$(wc -l < "$task_file" 2>/dev/null | tr -d ' ')
    log "Recorded ${count} completed task(s) for Epic ${epic_num}"
}

###############################################################################
# Determine resume point: find first uncompleted task in an epic
###############################################################################

find_resume_task() {
    local epic_num=$1
    local all_tasks
    all_tasks=$(get_task_ids "$epic_num")

    for task in $all_tasks; do
        if ! is_task_done "$epic_num" "$task"; then
            echo "$task"
            return
        fi
    done
    # All tasks done
    echo ""
}

###############################################################################
# Run validation pass for one epic
###############################################################################

run_validation() {
    local epic_num=$1
    local log_file="${LOG_DIR}/epic-${epic_num}-validate-${TIMESTAMP}.log"
    local prompt
    prompt=$(build_validation_prompt "$epic_num")

    log "Starting validation of Epic ${epic_num}..."
    log "Log: ${log_file}"

    if $DRY_RUN; then
        log "[DRY RUN] Would run claude with validation prompt for Epic ${epic_num}"
        echo "$prompt" > "${log_file}.prompt.txt"
        return 0
    fi

    local start_time=$SECONDS

    claude -p \
        --model "$MODEL" \
        --permission-mode bypassPermissions \
        --verbose \
        "$prompt" \
        2>&1 | tee "$log_file"

    local exit_code=${PIPESTATUS[0]}
    local elapsed=$(( SECONDS - start_time ))
    log "Validation took $(( elapsed / 60 ))m $(( elapsed % 60 ))s"

    if [[ $exit_code -ne 0 ]]; then
        log "WARNING: Validation of Epic ${epic_num} had issues (exit code: ${exit_code})"
        return 1
    fi

    mark_validated "$epic_num"
    log "Validation of Epic ${epic_num} complete."
}

###############################################################################
# Main orchestration loop
###############################################################################

main() {
    log_section "Ratatouille Epic Implementation Orchestrator"
    log "Project root: ${PROJECT_ROOT}"
    log "Model: ${MODEL}"
    echo ""

    # Preflight (skip for dry runs)
    if ! $DRY_RUN; then
        preflight
    fi

    # Determine which epics to run
    local epics_to_run=()
    if [[ -n "$ONLY_EPIC" ]]; then
        epics_to_run=("$ONLY_EPIC")
    else
        for e in "${EPIC_ORDER[@]}"; do
            if [[ $e -ge $FROM_EPIC ]]; then
                epics_to_run+=("$e")
            fi
        done
    fi

    log "Epics to execute: ${epics_to_run[*]}"
    echo ""

    if $DRY_RUN; then
        log "[DRY RUN MODE — no changes will be made]"
        echo ""
    fi

    for epic_num in "${epics_to_run[@]}"; do
        local epic_filename
        epic_filename=$(get_epic_filename "$epic_num")

        if [[ -z "$epic_filename" ]]; then
            log "ERROR: No epic file found for epic ${epic_num}"
            exit 1
        fi

        log_section "Epic ${epic_num}: ${epic_filename}"

        # Skip if already done and validated (unless --only is set)
        if [[ -z "$ONLY_EPIC" ]] && is_done "$epic_num" && is_validated "$epic_num"; then
            log "Epic ${epic_num} already completed and validated. Skipping."
            continue
        fi

        # Determine resume point for this epic
        local resume_task=""
        if [[ -n "$FROM_TASK" && "$epic_num" == "${FROM_TASK%%.*}" ]]; then
            # Explicit --from-task flag
            resume_task="$FROM_TASK"
            FROM_TASK=""  # Only applies to the first epic
        elif is_done "$epic_num" && [[ -z "$ONLY_EPIC" ]]; then
            # Epic marked done but not validated — skip to validation
            resume_task=""
        else
            # Check if we have partial progress
            local auto_resume
            auto_resume=$(find_resume_task "$epic_num")
            if [[ -n "$auto_resume" ]]; then
                local first_task
                first_task=$(get_task_ids "$epic_num" | head -1)
                if [[ "$auto_resume" != "$first_task" ]]; then
                    resume_task="$auto_resume"
                    log "Detected partial progress — resuming from task ${resume_task}"
                fi
            fi
        fi

        # Phase 1: Implementation
        if ! is_done "$epic_num" || [[ -n "$ONLY_EPIC" ]]; then
            if ! run_implementation "$epic_num" "$resume_task"; then
                log "ERROR: Epic ${epic_num} implementation failed."
                log "To resume, run: ./implement.sh --from-task $(find_resume_task "$epic_num")"
                exit 1
            fi
        else
            log "Epic ${epic_num} already implemented. Skipping to validation."
        fi

        # Phase 1.5: Build check (between implementation and validation)
        if ! $DRY_RUN; then
            if ! run_build_check "$epic_num"; then
                log "ERROR: Build check failed after Epic ${epic_num}."
                log "The validation pass will attempt to fix this."
            fi
        fi

        # Phase 2: Validation (includes smoke tests)
        if ! run_validation "$epic_num"; then
            log "WARNING: Epic ${epic_num} validation found issues. Review logs."
            log "Continuing to next epic (validation fixes were attempted)."
        fi

        # Phase 2.5: Post-validation build check
        if ! $DRY_RUN; then
            if ! run_build_check "$epic_num"; then
                log "FATAL: Build check STILL failing after validation of Epic ${epic_num}."
                log "Manual intervention required. Stopping."
                exit 1
            fi
        fi

        log "Epic ${epic_num} done."
        echo ""
    done

    log_section "All requested epics processed!"
    log "State directory: ${STATE_DIR}"
    log "Logs directory: ${LOG_DIR}"

    # Summary
    echo ""
    echo "Epic Status Summary:"
    echo "──────────────────────────────────────────────"
    for e in "${EPIC_ORDER[@]}"; do
        local status="NOT STARTED"
        local task_info=""
        if is_done "$e" && is_validated "$e"; then
            status="DONE + VALIDATED"
        elif is_done "$e"; then
            status="DONE (not validated)"
        fi

        # Task-level progress
        local total_tasks completed_tasks
        total_tasks=$(get_task_ids "$e" 2>/dev/null | wc -l | tr -d ' ')
        completed_tasks=$(get_completed_tasks "$e" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$completed_tasks" -gt 0 ]]; then
            task_info=" [${completed_tasks}/${total_tasks} tasks]"
        fi

        printf "  Epic %d: %-25s%s\n" "$e" "$status" "$task_info"
    done
    echo "──────────────────────────────────────────────"
}

main
