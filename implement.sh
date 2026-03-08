#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Ratatouille Epic Implementation Orchestrator
#
# Drives Claude Code in non-interactive mode to implement each epic
# sequentially or in parallel (via git worktrees), with validation passes,
# build checks, and context management.
#
# Usage:
#   ./implement.sh                  # Run all epics (with parallel tracks)
#   ./implement.sh --from 3         # Resume from epic 3
#   ./implement.sh --only 2         # Run only epic 2
#   ./implement.sh --from-task 4.6  # Resume from task 4.6 within epic 4
#   ./implement.sh --no-parallel    # Force sequential execution
#   ./implement.sh --dry-run        # Show plan without executing
###############################################################################

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
EPICS_DIR="${PROJECT_ROOT}/epics"
STATE_DIR="${PROJECT_ROOT}/.epic-state"
LOG_DIR="${PROJECT_ROOT}/.epic-logs"
WORKTREE_DIR="${PROJECT_ROOT}/.epic-worktrees"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Working directory — defaults to PROJECT_ROOT, changes for worktree runs.
# All code-path references (backend/, mobile/) use WORK_DIR.
# State/logs always use PROJECT_ROOT.
WORK_DIR="$PROJECT_ROOT"

# Epic execution order — auto-detected from epics/ directory
EPIC_ORDER=()
for f in "$EPICS_DIR"/epic-*-*.md; do
    num=$(basename "$f" | grep -oE '^epic-[0-9]+' | grep -oE '[0-9]+')
    [[ -n "$num" ]] && EPIC_ORDER+=("$num")
done
IFS=$'\n' EPIC_ORDER=($(printf '%s\n' "${EPIC_ORDER[@]}" | sort -n | uniq)); unset IFS

if [[ ${#EPIC_ORDER[@]} -eq 0 ]]; then
    echo "FATAL: No epic files found in ${EPICS_DIR}"
    exit 1
fi

###############################################################################
# Parallel execution schedule (based on dependency graph in epics/index.md)
#
#   Epic 1 → Epic 2 (sequential foundation)
#       │
#       ├── Track A: Epic 3                  ← parallel
#       └── Track B: Epic 4 → Epic 5 → Epic 6  ← parallel
#       │
#       merge
#       │
#   Epic 8 → Epic 7 (sequential finalization)
#
# Modify these arrays if the dependency graph changes.
###############################################################################

PHASE_SEQ_PRE=(1 2)            # Sequential: foundation (must complete before parallel)
PHASE_TRACK_A=(3)              # Parallel track A: scan & suggestions
PHASE_TRACK_B=(4 5 6)         # Parallel track B: live session chain
PHASE_SEQ_POST=(8 7)          # Sequential: integration & demo (after merge)

# CLI args
FROM_EPIC=1
FROM_TASK=""
ONLY_EPIC=""
DRY_RUN=false
NO_PARALLEL=false
MODEL="opus"

while [[ $# -gt 0 ]]; do
    case $1 in
        --from)         FROM_EPIC="$2"; shift 2 ;;
        --from-task)    FROM_TASK="$2"; shift 2 ;;
        --only)         ONLY_EPIC="$2"; shift 2 ;;
        --dry-run)      DRY_RUN=true; shift ;;
        --no-parallel)  NO_PARALLEL=true; shift ;;
        --model)        MODEL="$2"; shift 2 ;;
        --reset)        rm -rf "$STATE_DIR" "$WORKTREE_DIR"; echo "State reset."; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -n "$FROM_TASK" ]]; then
    FROM_EPIC="${FROM_TASK%%.*}"
fi

mkdir -p "$STATE_DIR" "$LOG_DIR"

# Detect line-buffering tool
if command -v stdbuf &>/dev/null; then
    LINEBUF="stdbuf -oL"
else
    LINEBUF=""
fi

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

get_task_ids() {
    local epic_num=$1
    local epic_file="${EPICS_DIR}/$(get_epic_filename "$epic_num")"
    grep -oE "^### ${epic_num}\.[0-9]+" "$epic_file" | sed "s/^### //"
}

record_completed_tasks() {
    local epic_num=$1
    local task_file
    task_file=$(TASK_STATE_FILE "$epic_num")
    git -C "$WORK_DIR" log --oneline --all | grep -oE "task ${epic_num}\.[0-9]+" | sed "s/task //" | sort -t. -k2 -n | uniq > "$task_file" 2>/dev/null || true
    local count
    count=$(wc -l < "$task_file" 2>/dev/null | tr -d ' ')
    log "Recorded ${count} completed task(s) for Epic ${epic_num}"
}

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
    echo ""
}

has_new_tasks() {
    local epic_num=$1
    record_completed_tasks "$epic_num"
    local resume
    resume=$(find_resume_task "$epic_num")
    [[ -n "$resume" ]]
}

# Check if an epic should be skipped (based on --from flag)
should_skip_epic() {
    local epic_num=$1
    [[ $epic_num -lt $FROM_EPIC ]]
}

###############################################################################
# Preflight checks
###############################################################################

preflight() {
    log "Running preflight checks..."
    local failed=false

    command -v claude &>/dev/null || { log "FATAL: 'claude' CLI not found in PATH"; failed=true; }
    git rev-parse --git-dir &>/dev/null || { log "FATAL: not inside a git repository"; failed=true; }

    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        log "FATAL: git working tree is dirty — commit or stash changes before running"
        failed=true
    fi

    [[ -f "${EPICS_DIR}/index.md" ]] || { log "FATAL: epics/index.md not found"; failed=true; }
    [[ -f "${PROJECT_ROOT}/CLAUDE.md" ]] || log "WARNING: CLAUDE.md not found"
    command -v python3 &>/dev/null || log "WARNING: python3 not found — build checks will be skipped"

    for e in "${EPIC_ORDER[@]}"; do
        local fname
        fname=$(get_epic_filename "$e" 2>/dev/null || true)
        [[ -z "$fname" ]] && { log "FATAL: no epic file found for epic ${e}"; failed=true; }
    done

    $failed && { log "Preflight checks failed. Aborting."; exit 1; }
    log "Preflight checks passed."
}

###############################################################################
# Build / smoke check
###############################################################################

build_error_file() { echo "${STATE_DIR}/build_error_epic${1}.txt"; }

run_build_check() {
    local epic_num=$1
    local backend_dir="${WORK_DIR}/backend"
    local error_file
    error_file=$(build_error_file "$epic_num")

    [[ ! -d "$backend_dir" ]] && { log "Build check: no backend/ directory yet — skipping"; return 0; }
    [[ ! -f "$backend_dir/requirements.txt" ]] && { log "Build check: no requirements.txt yet — skipping"; return 0; }

    log "Running build/smoke check after Epic ${epic_num}..."

    local venv_dir="${WORK_DIR}/.epic-venv"
    if [[ ! -d "$venv_dir" ]]; then
        python3 -m venv "$venv_dir" 2>/dev/null || { log "WARNING: could not create venv — skipping"; return 0; }
    fi

    # pip install
    local pip_output
    pip_output=$(source "${venv_dir}/bin/activate" && cd "$backend_dir" && pip install -r requirements.txt 2>&1) || {
        echo "pip install failed:"$'\n'"$pip_output" > "$error_file"
        log "WARNING: pip install failed"
        return 1
    }

    # App import
    local import_output
    import_output=$(source "${venv_dir}/bin/activate" && cd "$backend_dir" && python -c "from app.main import app; print('Smoke check: app imports OK')" 2>&1) || {
        echo "App import failed:"$'\n'"$import_output" > "$error_file"
        log "ERROR: app import failed after Epic ${epic_num}"
        return 1
    }

    # pytest
    if [[ -d "$backend_dir/tests" ]]; then
        log "Running pytest..."
        local pytest_output
        pytest_output=$(source "${venv_dir}/bin/activate" && cd "$backend_dir" && python -m pytest tests/ -v --tb=short 2>&1) || {
            echo "pytest failed:"$'\n'"$pytest_output" > "$error_file"
            log "ERROR: tests failing after Epic ${epic_num}"
            return 1
        }
    fi

    # Flutter
    if [[ -d "${WORK_DIR}/mobile" && -f "${WORK_DIR}/mobile/pubspec.yaml" ]] && command -v flutter &>/dev/null; then
        log "Running Flutter analysis..."
        local flutter_output
        flutter_output=$(cd "${WORK_DIR}/mobile" && flutter analyze --no-fatal-infos 2>&1) || {
            echo "Flutter analyze failed:"$'\n'"$flutter_output" > "$error_file"
            log "ERROR: Flutter analysis failed after Epic ${epic_num}"
            return 1
        }
    fi

    log "Build check passed."
    rm -f "$error_file"
    return 0
}

###############################################################################
# Build fix agent
###############################################################################

MAX_FIX_ATTEMPTS=3

run_build_fix() {
    local epic_num=$1
    local attempt=$2
    local log_file="${LOG_DIR}/epic-${epic_num}-buildfix-${attempt}-${TIMESTAMP}.log"
    local error_file
    error_file=$(build_error_file "$epic_num")

    [[ ! -f "$error_file" ]] && { log "No build error file found — nothing to fix"; return 1; }

    local error_output
    error_output=$(cat "$error_file")

    log "Spawning build-fix agent (attempt ${attempt}/${MAX_FIX_ATTEMPTS})..."
    log "Log: ${log_file}"

    local prompt
    read -r -d '' prompt <<FIXPROMPT || true
You are a build-fix agent for the Ratatouille hackathon project.
The build/smoke check failed after implementing Epic ${epic_num}.
Your ONLY job is to fix the build so that the app imports cleanly.

THE ERROR:
${error_output}

INSTRUCTIONS:
1. Read the error carefully. Identify the root cause.
2. Common causes:
   - Missing __init__.py files in packages
   - Circular imports between modules
   - Importing a module that doesn't exist yet (typo or not created)
   - Missing dependencies in requirements.txt
   - Syntax errors
   - Incompatible function signatures (sync vs async)
   - Import of a name that doesn't exist in the target module
3. Fix the issue using the Edit or Write tool.
4. After fixing, verify by running:
     cd backend && python3 -c "from app.main import app; print('Import OK')"
5. If that still fails, read the NEW error and fix that too. Keep going until it passes.
6. Once the import succeeds, stage and commit your fix:
     git add <specific files>
     git commit -m "fix(epic-${epic_num}): fix build — <what you fixed>"
7. Do NOT refactor, do NOT improve code, do NOT touch anything unrelated to the build error.
   Minimal, targeted fixes only.
FIXPROMPT

    local prompt_file="${log_file}.prompt.txt"
    echo "$prompt" > "$prompt_file"

    pushd "$WORK_DIR" > /dev/null
    $LINEBUF claude -p \
        --model "$MODEL" \
        --permission-mode bypassPermissions \
        --verbose \
        "$(cat "$prompt_file")" \
        < /dev/null 2>&1 | $LINEBUF tee "$log_file"
    local exit_code=${PIPESTATUS[0]}
    popd > /dev/null

    [[ $exit_code -ne 0 ]] && { log "WARNING: Build-fix agent exited with code ${exit_code}"; return 1; }
    return 0
}

###############################################################################
# Build fix loop — run build check, if it fails try fix agent up to N times
###############################################################################

run_build_fix_loop() {
    local epic_num=$1
    local context=$2  # "post-impl" or "post-validation"

    $DRY_RUN && return 0

    if run_build_check "$epic_num"; then
        return 0
    fi

    log "Build check failed (${context}). Spawning build-fix agent..."
    local fix_attempt=1
    while [[ $fix_attempt -le $MAX_FIX_ATTEMPTS ]]; do
        run_build_fix "$epic_num" "$fix_attempt" || true
        if run_build_check "$epic_num"; then
            log "Build fixed on attempt ${fix_attempt}."
            return 0
        fi
        fix_attempt=$((fix_attempt + 1))
    done

    log "WARNING: Build still broken after ${MAX_FIX_ATTEMPTS} fix attempts (${context})."
    return 1
}

###############################################################################
# Build context prompt for implementation
###############################################################################

build_context() {
    local epic_num=$1
    local resume_task="${2:-}"

    cat <<'CONTEXT_HEADER'
You are implementing a hackathon project called "Ratatouille" — a live cooking companion app.
You are working in a repository that has the full PRD, tech guide, and epic specifications.
The CLAUDE.md file in the project root has all conventions — you have already loaded it.

KEY RULES:
1. Read the epic file AND the referenced PRD/tech guide sections before writing any code.
2. Implement ALL tasks in the epic sequentially — do NOT skip any task.
3. Use subagents (the Agent tool) to parallelize independent tasks within the epic.
4. After implementing each task, verify its acceptance criteria.
5. Write clean, production-quality code — not throwaway hackathon code.
6. Follow the project conventions in CLAUDE.md (async everywhere, Pydantic models, etc.)
7. Do NOT modify files from previous epics unless the current epic explicitly requires it (e.g., mounting a new router).
8. If a task requires infrastructure setup (GCP commands), create the code artifacts but note that GCP commands should be run separately.

MOBILE / FLUTTER TASKS — DO NOT SKIP:
Some epics include "Mobile UX Implementation" tasks. You MUST implement these.
- If the mobile/ directory does not exist yet, scaffold a new Flutter project:
    cd mobile && flutter create --org com.ratatouille --project-name ratatouille .
  Then build out the screens/widgets required by the task.
- If the mobile/ directory already exists, add to the existing Flutter project.
- Mobile UX is a first-class, judging-critical deliverable — not optional polish.
- Follow Flutter best practices: use provider or riverpod for state, material3 theme,
  responsive layouts, and clear separation of screens/widgets/services.
- The mobile app should connect to the backend API endpoints you have already built.
- Use environment config for the backend URL (do not hardcode localhost).
- Every mobile task gets its own commit just like backend tasks.

TESTING — REQUIRED FOR EVERY TASK:
You MUST write and run tests for each task as part of the implementation. Tests are not optional.
Follow this testing strategy:

Backend (Python / FastAPI):
- Place tests in backend/tests/ mirroring the app structure:
    backend/tests/test_routers/test_recipes.py
    backend/tests/test_services/test_ingredients.py
    backend/tests/test_agents/test_orchestrator.py
    backend/tests/test_models/test_recipe.py
- Use pytest + httpx.AsyncClient for endpoint tests (with TestClient from FastAPI).
- Mock external dependencies (Firestore, GCS, Gemini, Firebase Auth) using unittest.mock or pytest-mock.
  Do NOT make real calls to GCP services in tests.
- For auth-protected endpoints, create a fixture that overrides the get_current_user dependency.
- Write at minimum for each task:
  * Unit tests: test individual functions, model validation, edge cases
  * Integration tests: test endpoint request/response with mocked dependencies
- After writing tests, RUN THEM: cd backend && python -m pytest tests/ -v
- If any test fails, fix the code or test until all pass.
- Include pytest, httpx, and pytest-asyncio in requirements.txt (add them if missing).
- Ensure backend/tests/__init__.py and all test subdirectory __init__.py files exist.

Flutter (Mobile):
- Place tests in mobile/test/ mirroring the lib structure.
- Write widget tests for key screens/components.
- After writing tests, RUN THEM: cd mobile && flutter test
- If any test fails, fix it.

Test files are committed as part of the same task commit — not in a separate commit.
Example: task 2.1 creates app/routers/recipes.py AND tests/test_routers/test_recipes.py,
both committed together as "feat(epic-2): task 2.1 — recipe CRUD endpoints".

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
    echo "   b. Write tests for the task (unit + integration as described in TESTING section)."
    echo "   c. Run the tests: cd backend && python -m pytest tests/ -v"
    echo "   d. Fix any test failures — do not move on with failing tests."
    echo "   e. Verify acceptance criteria."
    echo "   f. Stage implementation + test files and commit: feat(epic-${epic_num}): task N.M — description"
    echo "6. After all tasks, run the FULL test suite one final time: cd backend && python -m pytest tests/ -v"
    echo "7. If anything fails, fix it and do a final cleanup commit."
    echo ""
    echo "REMEMBER: One commit per task. Do not batch. Do not skip commits."
    echo ""
    echo "BEGIN IMPLEMENTATION OF EPIC ${epic_num} NOW."
}

###############################################################################
# Build validation prompt
###############################################################################

build_validation_prompt() {
    local epic_num=$1

    cat <<VALIDATION_PROMPT
You are a code reviewer AND fixer validating Epic ${epic_num} for the Ratatouille hackathon project.
Your job is NOT just to report issues — you MUST fix every issue you find.

PHASE 1 — AUDIT:
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
   - Missing __init__.py files
   - Async Gemini calls (must use gemini_client.aio or asyncio.to_thread)
   - SKIPPED TASKS — especially "Mobile UX Implementation" tasks. Every task in the
     epic MUST be implemented. If a mobile task was skipped, implement it now.

PHASE 2 — SMOKE TEST + TEST SUITE:
Step A — Import check:
  cd backend && python3 -c "from app.main import app; print('Import OK')"
If this fails, FIX it immediately (missing __init__.py, circular imports, etc.).

Step B — Module imports (test each module added by this epic):
  python3 -c "from app.routers.X import router"
  python3 -c "from app.models.X import SomeModel"
  python3 -c "from app.services.X import something"
  python3 -c "from app.agents.X import SomeAgent"

Step C — Run the full test suite:
  cd backend && python -m pytest tests/ -v
If tests fail:
  - Determine if the test or the implementation is wrong.
  - Fix whichever is incorrect.
  - Re-run until all tests pass.
If NO tests exist for this epic's tasks, WRITE THEM before proceeding. Every task
should have corresponding tests in backend/tests/. Missing test coverage is a validation failure.

Step D — Flutter tests (if mobile/ exists):
  cd mobile && flutter test
Fix any failures.

PHASE 3 — FIX EVERYTHING:
This is the most important phase. For EVERY issue found in Phase 1 and Phase 2:
  1. Fix it using the Edit tool (or Write tool if a file is missing entirely).
  2. Re-run the relevant smoke test to confirm the fix works.
  3. Continue to the next issue.

Do NOT just list issues and move on. Do NOT produce a report without fixing.
You are the last line of defense before the next epic builds on top of this one.

After all fixes are applied:
  - Re-run the full smoke test: cd backend && python3 -c "from app.main import app; print('Import OK')"
  - Stage all fixed files (specific files only, not git add -A)
  - Commit: fix(epic-${epic_num}): address validation findings
  - If there were no issues, do not create an empty commit.

PHASE 4 — REPORT:
After fixing, produce a final structured report:

## Epic ${epic_num} Validation Report

### Status: PASS | FAIL | PARTIAL

### Smoke Test: PASS | FAIL
(include the actual output from AFTER fixes)

### Test Suite: X passed, Y failed, Z missing
(include the pytest output summary line)
(list any tasks that have NO test coverage)
- [ ] Task X.Y: description — PASS/FAIL (details)

### Issues Found and Fixed:
1. [SEVERITY] Description of issue + file:line — FIXED / UNABLE TO FIX (reason)

### Remaining Issues (if any):
- Only list things you genuinely could not fix

### Commit Verification:
Run "git log --oneline" and verify there is a separate commit for each task in this epic.
Expected pattern: "feat(epic-${epic_num}): task N.M — ..."
If tasks were batched into a single commit, note this but do not rewrite history.
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
    local prompt_file="${log_file}.prompt.txt"
    echo "$prompt" > "$prompt_file"

    pushd "$WORK_DIR" > /dev/null
    $LINEBUF claude -p \
        --model "$MODEL" \
        --permission-mode bypassPermissions \
        --verbose \
        "$(cat "$prompt_file")" \
        < /dev/null 2>&1 | $LINEBUF tee "$log_file"
    local exit_code=${PIPESTATUS[0]}
    popd > /dev/null

    local elapsed=$(( SECONDS - start_time ))
    log "Implementation took $(( elapsed / 60 ))m $(( elapsed % 60 ))s"

    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: Implementation of Epic ${epic_num} failed (exit code: ${exit_code})"
        record_completed_tasks "$epic_num"
        return 1
    fi

    record_completed_tasks "$epic_num"
    mark_done "$epic_num"
    log "Implementation of Epic ${epic_num} complete."
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
    local prompt_file="${log_file}.prompt.txt"
    echo "$prompt" > "$prompt_file"

    pushd "$WORK_DIR" > /dev/null
    $LINEBUF claude -p \
        --model "$MODEL" \
        --permission-mode bypassPermissions \
        --verbose \
        "$(cat "$prompt_file")" \
        < /dev/null 2>&1 | $LINEBUF tee "$log_file"
    local exit_code=${PIPESTATUS[0]}
    popd > /dev/null

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
# Full pipeline for a single epic (implement → build check → validate → check)
###############################################################################

run_epic_pipeline() {
    local epic_num=$1
    local epic_filename
    epic_filename=$(get_epic_filename "$epic_num")

    [[ -z "$epic_filename" ]] && { log "ERROR: No epic file found for epic ${epic_num}"; return 1; }

    log_section "Epic ${epic_num}: ${epic_filename}"

    # Check if previously completed but has new tasks
    local has_new=false
    if is_done "$epic_num" && is_validated "$epic_num"; then
        if has_new_tasks "$epic_num"; then
            has_new=true
            log "Epic ${epic_num} was completed, but NEW TASKS detected."
            rm -f "${STATE_DIR}/epic-${epic_num}.done" "${STATE_DIR}/epic-${epic_num}.validated"
        else
            log "Epic ${epic_num} already completed and validated. Skipping."
            return 0
        fi
    fi

    # Determine resume point
    local resume_task=""
    if [[ -n "$FROM_TASK" && "$epic_num" == "${FROM_TASK%%.*}" ]]; then
        resume_task="$FROM_TASK"
        FROM_TASK=""
    elif is_done "$epic_num"; then
        resume_task=""
    else
        local auto_resume
        auto_resume=$(find_resume_task "$epic_num")
        if [[ -n "$auto_resume" ]]; then
            local first_task
            first_task=$(get_task_ids "$epic_num" | head -1)
            if [[ "$auto_resume" != "$first_task" ]] || $has_new; then
                resume_task="$auto_resume"
                log "Detected incomplete tasks — resuming from task ${resume_task}"
            fi
        fi
    fi

    # Phase 1: Implementation
    if ! is_done "$epic_num"; then
        if ! run_implementation "$epic_num" "$resume_task"; then
            log "ERROR: Epic ${epic_num} implementation failed."
            log "To resume: ./implement.sh --from-task $(find_resume_task "$epic_num")"
            return 1
        fi
    else
        log "Epic ${epic_num} already implemented. Skipping to validation."
    fi

    # Phase 1.5: Build check + fix
    if ! run_build_fix_loop "$epic_num" "post-impl"; then
        log "WARNING: Build broken after implementation. Validation will try next."
    fi

    # Phase 2: Validation
    if ! run_validation "$epic_num"; then
        log "WARNING: Epic ${epic_num} validation found issues."
    fi

    # Phase 2.5: Post-validation build check + fix
    if ! run_build_fix_loop "$epic_num" "post-validation"; then
        log "FATAL: Build STILL failing after validation + fix attempts for Epic ${epic_num}."
        return 1
    fi

    log "Epic ${epic_num} done."
}

###############################################################################
# Worktree management for parallel tracks
###############################################################################

create_worktree() {
    local track_name=$1
    local branch_name="epic-track-${track_name}-${TIMESTAMP}"
    local worktree_path="${WORKTREE_DIR}/${track_name}"

    mkdir -p "$WORKTREE_DIR"

    log "Creating worktree for track '${track_name}' at ${worktree_path}..."
    git worktree add "$worktree_path" -b "$branch_name" 2>&1
    echo "$worktree_path"
}

merge_worktree() {
    local track_name=$1
    local worktree_path="${WORKTREE_DIR}/${track_name}"

    # Find the branch name from the worktree
    local branch_name
    branch_name=$(git -C "$worktree_path" branch --show-current 2>/dev/null)

    if [[ -z "$branch_name" ]]; then
        log "WARNING: Could not determine branch for track '${track_name}'"
        return 1
    fi

    local current_branch
    current_branch=$(git branch --show-current)

    log "Merging track '${track_name}' (branch: ${branch_name}) into ${current_branch}..."
    git merge "$branch_name" --no-edit -m "merge: track ${track_name} into ${current_branch}" 2>&1

    if [[ $? -ne 0 ]]; then
        log "ERROR: Merge conflict merging track '${track_name}'!"
        log "Resolve conflicts manually, then continue with: ./implement.sh --from 8"
        return 1
    fi

    # Cleanup
    log "Removing worktree '${track_name}'..."
    git worktree remove "$worktree_path" --force 2>/dev/null || true
    git branch -d "$branch_name" 2>/dev/null || true

    log "Track '${track_name}' merged successfully."
}

###############################################################################
# Run a sequence of epics in a worktree (for parallel tracks)
###############################################################################

run_track() {
    local track_name=$1
    shift
    local epics=("$@")
    local track_log="${LOG_DIR}/track-${track_name}-${TIMESTAMP}.log"

    log_section "Track ${track_name}: epics ${epics[*]}"

    local worktree_path
    worktree_path=$(create_worktree "$track_name")

    # Save and override WORK_DIR for this track
    local saved_work_dir="$WORK_DIR"
    WORK_DIR="$worktree_path"

    local track_failed=false
    for epic_num in "${epics[@]}"; do
        if should_skip_epic "$epic_num"; then
            log "Skipping Epic ${epic_num} (before --from ${FROM_EPIC})"
            continue
        fi
        if ! run_epic_pipeline "$epic_num"; then
            log "ERROR: Track '${track_name}' failed at Epic ${epic_num}"
            track_failed=true
            break
        fi
    done

    WORK_DIR="$saved_work_dir"

    if $track_failed; then
        return 1
    fi

    log "Track '${track_name}' completed all epics: ${epics[*]}"
    return 0
}

###############################################################################
# Run a sequence of epics on main (no worktree)
###############################################################################

run_sequential() {
    local epics=("$@")
    for epic_num in "${epics[@]}"; do
        if should_skip_epic "$epic_num"; then
            log "Skipping Epic ${epic_num} (before --from ${FROM_EPIC})"
            continue
        fi
        if ! run_epic_pipeline "$epic_num"; then
            log "ERROR: Sequential execution failed at Epic ${epic_num}."
            exit 1
        fi
    done
}

###############################################################################
# Check if any epic in a list needs work
###############################################################################

phase_has_work() {
    local epics=("$@")
    for e in "${epics[@]}"; do
        should_skip_epic "$e" && continue
        # If not done+validated, or has new tasks, there's work to do
        if ! (is_done "$e" && is_validated "$e"); then
            return 0
        fi
        if has_new_tasks "$e"; then
            return 0
        fi
    done
    return 1
}

###############################################################################
# Main orchestration — phase-based with parallel tracks
###############################################################################

main() {
    log_section "Ratatouille Epic Implementation Orchestrator"
    log "Project root: ${PROJECT_ROOT}"
    log "Model: ${MODEL}"
    log "Parallel: $( $NO_PARALLEL && echo 'disabled' || echo 'enabled' )"
    echo ""

    if ! $DRY_RUN; then
        preflight
    fi

    # Handle --only: bypass all phase logic
    if [[ -n "$ONLY_EPIC" ]]; then
        log "Running only Epic ${ONLY_EPIC}"
        run_epic_pipeline "$ONLY_EPIC"
        print_summary
        return
    fi

    # Pre-resume build check
    if ! $DRY_RUN && [[ $FROM_EPIC -gt 1 || -n "$FROM_TASK" ]]; then
        log "Running pre-resume build check..."
        if ! run_build_check "pre-resume"; then
            log "WARNING: Existing codebase has build errors. Spawning build-fix agent..."
            if ! run_build_fix_loop "pre-resume" "pre-resume"; then
                log "FATAL: Cannot fix existing build errors. Fix manually."
                exit 1
            fi
        else
            log "Pre-resume build check passed."
        fi
        echo ""
    fi

    # === SEQUENTIAL or PARALLEL execution ===

    if $NO_PARALLEL; then
        # Simple sequential: all epics in order
        log "Running all epics sequentially..."
        local all_epics=("${PHASE_SEQ_PRE[@]}" "${PHASE_TRACK_A[@]}" "${PHASE_TRACK_B[@]}" "${PHASE_SEQ_POST[@]}")
        run_sequential "${all_epics[@]}"
    else
        # === Phase 1: Sequential pre-requisites ===
        log_section "Phase 1: Sequential Foundation (Epics ${PHASE_SEQ_PRE[*]})"
        if phase_has_work "${PHASE_SEQ_PRE[@]}"; then
            run_sequential "${PHASE_SEQ_PRE[@]}"
        else
            log "Phase 1 already complete. Skipping."
        fi

        # === Phase 2: Parallel tracks ===
        local track_a_needs_work=false
        local track_b_needs_work=false
        phase_has_work "${PHASE_TRACK_A[@]}" && track_a_needs_work=true
        phase_has_work "${PHASE_TRACK_B[@]}" && track_b_needs_work=true

        if $track_a_needs_work || $track_b_needs_work; then
            log_section "Phase 2: Parallel Tracks"
            log "  Track A (epics ${PHASE_TRACK_A[*]}): $( $track_a_needs_work && echo 'RUNNING' || echo 'SKIP' )"
            log "  Track B (epics ${PHASE_TRACK_B[*]}): $( $track_b_needs_work && echo 'RUNNING' || echo 'SKIP' )"
            echo ""

            if $DRY_RUN; then
                log "[DRY RUN] Would run Track A and Track B in parallel worktrees"
                # Still run the pipeline in dry-run mode for logging
                $track_a_needs_work && run_track "a" "${PHASE_TRACK_A[@]}" || true
                $track_b_needs_work && run_track "b" "${PHASE_TRACK_B[@]}" || true
            else
                local pids=()
                local track_names=()

                if $track_a_needs_work; then
                    run_track "a" "${PHASE_TRACK_A[@]}" &
                    pids+=($!)
                    track_names+=("a")
                    log "Track A launched (PID: ${pids[-1]})"
                fi

                if $track_b_needs_work; then
                    run_track "b" "${PHASE_TRACK_B[@]}" &
                    pids+=($!)
                    track_names+=("b")
                    log "Track B launched (PID: ${pids[-1]})"
                fi

                # Wait for all tracks and collect exit codes
                local all_tracks_ok=true
                for i in "${!pids[@]}"; do
                    local pid=${pids[$i]}
                    local name=${track_names[$i]}
                    if wait "$pid"; then
                        log "Track '${name}' completed successfully (PID: ${pid})"
                    else
                        log "ERROR: Track '${name}' failed (PID: ${pid})"
                        all_tracks_ok=false
                    fi
                done

                if ! $all_tracks_ok; then
                    log "FATAL: One or more parallel tracks failed. Check logs."
                    log "After fixing, resume with: ./implement.sh --from <next-epic>"
                    print_summary
                    exit 1
                fi

                # === Merge tracks back to main ===
                log_section "Merging parallel tracks"
                for name in "${track_names[@]}"; do
                    if ! merge_worktree "$name"; then
                        log "FATAL: Failed to merge track '${name}'. Resolve manually."
                        log "Worktree at: ${WORKTREE_DIR}/${name}"
                        print_summary
                        exit 1
                    fi
                done
                log "All tracks merged successfully."
            fi
        else
            log_section "Phase 2: Parallel Tracks"
            log "Both tracks already complete. Skipping."
        fi

        # === Phase 3: Sequential post-merge ===
        log_section "Phase 3: Sequential Finalization (Epics ${PHASE_SEQ_POST[*]})"
        if phase_has_work "${PHASE_SEQ_POST[@]}"; then
            run_sequential "${PHASE_SEQ_POST[@]}"
        else
            log "Phase 3 already complete. Skipping."
        fi
    fi

    print_summary
}

###############################################################################
# Summary
###############################################################################

print_summary() {
    log_section "All requested epics processed!"
    log "State directory: ${STATE_DIR}"
    log "Logs directory: ${LOG_DIR}"

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
