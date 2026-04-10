#!/bin/bash

# Smart sequential task runner for PAC1 benchmark
# - Stops on first failure and waits for fix
# - 15-second idle timeout detection (API instability)
# - Auto-restart hung tasks

set -e

TASK_START=${1:-4}
TASK_END=${2:-40}
SCRIPT="./run.sh"
IDLE_TIMEOUT=15  # seconds

echo "Starting smart sequential PAC1 task runner: tasks $TASK_START to $TASK_END"
echo "Idle timeout: ${IDLE_TIMEOUT}s (restarts hung tasks)"
echo "=========================================================="

run_task_with_timeout() {
    local TASK=$1
    local TMPFILE=$(mktemp)
    local LASTLINE_TIME=$(date +%s)
    local LASTLINE_LEN=0
    
    echo "Running task $TASK..." > "$TMPFILE"
    
    # Start task in background
    $SCRIPT $TASK > "$TMPFILE" 2>&1 &
    local PID=$!
    
    # Monitor for idle/hang
    while kill -0 $PID 2>/dev/null; do
        sleep 1
        local CURRENT_TIME=$(date +%s)
        local CURRENT_LEN=$(wc -c < "$TMPFILE")
        
        # Check if output changed
        if [ $CURRENT_LEN -gt $LASTLINE_LEN ]; then
            LASTLINE_TIME=$(date +%s)
            LASTLINE_LEN=$CURRENT_LEN
        else
            # No output change - check if idle timeout exceeded
            local IDLE=$((CURRENT_TIME - LASTLINE_TIME))
            if [ $IDLE -gt $IDLE_TIMEOUT ]; then
                echo "[HUNG] Task $TASK idle for ${IDLE}s, killing..."
                kill $PID 2>/dev/null || true
                wait $PID 2>/dev/null || true
                cat "$TMPFILE"
                rm "$TMPFILE"
                return 2  # Return code 2 = hung/timeout
            fi
        fi
    done
    
    wait $PID
    local EXIT_CODE=$?
    
    cat "$TMPFILE"
    rm "$TMPFILE"
    return $EXIT_CODE
}

for TASK in $(seq $TASK_START $TASK_END); do
    echo ""
    echo ">>> Task $TASK"
    echo "---"
    
    # Run with timeout wrapper
    OUTPUT=$(run_task_with_timeout $TASK 2>&1) || {
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 2 ]; then
            echo ""
            echo "✗ HUNG/TIMEOUT - Restarting task $TASK..."
            echo "---"
            OUTPUT=$(run_task_with_timeout $TASK 2>&1) || {
                EXIT_CODE=$?
                echo ""
                echo "✗ Task $TASK FAILED after retry (exit code: $EXIT_CODE)"
                echo "STOPPING. Fix and re-run: $SCRIPT $TASK"
                exit 1
            }
        else
            echo ""
            echo "✗ Task $TASK FAILED (exit code: $EXIT_CODE)"
            echo "STOPPING. Fix and re-run: $SCRIPT $TASK"
            exit 1
        fi
    }
    
    # Check output for success
    if echo "$OUTPUT" | grep -q "FINAL: 100.0%" && echo "$OUTPUT" | grep -q "Score: 1.00"; then
        echo "✓ Task $TASK PASSED"
    else
        # Extract error details
        echo ""
        echo "✗ Task $TASK FAILED or had errors"
        echo ""
        echo "Error details (last 20 lines):"
        echo "$OUTPUT" | tail -20
        echo ""
        echo "STOPPING. Fix the agent and re-run: $SCRIPT $TASK"
        exit 1
    fi
done

echo ""
echo "=========================================================="
echo "✓ All tasks $TASK_START to $TASK_END passed!"
