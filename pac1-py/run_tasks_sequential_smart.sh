#!/bin/bash

# Smart sequential task runner for PAC1 benchmark
# - Stops on first failure and waits for fix
# - 15-second idle timeout detection (API instability)
# - Auto-restart hung tasks
# - Background execution with nohup support

TASK_START=${1:-4}
TASK_END=${2:-40}
SCRIPT="./run.sh"
IDLE_TIMEOUT=15  # seconds

# Check if running in background mode (NOHUP_MODE env var set)
# If not, re-invoke ourselves with nohup and exit
if [ -z "$NOHUP_MODE" ]; then
    cd /home/glo/Documents/code/python/sample-agents/pac1-py
    NOHUP_MODE=1 nohup "$0" "$TASK_START" "$TASK_END" > "/tmp/tasks_${TASK_START}_${TASK_END}.log" 2>&1 &
    echo "Tasks $TASK_START-$TASK_END running in background, PID: $!"
    sleep 5
    exit 0
fi

set -e

echo "Starting smart sequential PAC1 task runner: tasks $TASK_START to $TASK_END"
echo "Idle timeout: ${IDLE_TIMEOUT}s (restarts hung tasks)"
echo "=========================================================="

run_task_with_timeout() {
    local TASK=$1
    local TMPFILE=$(mktemp)
    local LASTLINE_TIME=$(date +%s)
    local LASTLINE_LEN=0
    
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
    
    cat "$TMPFILE"
    rm "$TMPFILE"
    return 0
}

for TASK in $(seq $TASK_START $TASK_END); do
    echo ""
    echo ">>> Task $TASK"
    echo "---"
    
    # Run with timeout wrapper
    OUTPUT=$(run_task_with_timeout $TASK 2>&1)
    HANDLER_CODE=$?
    
    if [ $HANDLER_CODE -eq 2 ]; then
        # Task hung/timeout - retry once
        echo ""
        echo "[TIMEOUT] Task $TASK hung, retrying..."
        OUTPUT=$(run_task_with_timeout $TASK 2>&1)
        HANDLER_CODE=$?
    fi
    
    # Print output
    echo "$OUTPUT"
    
    # Check for success: both "Score: 1.00" and "FINAL: 100" somewhere in output
    if echo "$OUTPUT" | grep -q "Score: 1.00" && echo "$OUTPUT" | grep -q "FINAL: 100"; then
        echo ""
        echo "✓ Task $TASK PASSED"
    else
        # Extract error for debugging
        echo ""
        echo "✗ Task $TASK FAILED"
        echo ""
        echo "Extracting error lines..."
        echo "$OUTPUT" | grep -iE "missing|expected|error|fail|denied" | head -10 || echo "(no error keywords found)"
        echo ""
        echo "STOPPING. Review error above."
        echo "To debug: ./run.sh $TASK"
        exit 1
    fi
done

echo ""
echo "=========================================================="
echo "✓ All tasks $TASK_START to $TASK_END passed!"
