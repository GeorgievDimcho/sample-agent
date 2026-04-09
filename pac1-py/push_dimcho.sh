#!/bin/bash

# Script to verify branch, stage, commit, and push to dimcho

echo "=== Git Status ==="
git status

# Check if we're on dimcho branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [ "$CURRENT_BRANCH" != "dimcho" ]; then
    echo ""
    echo "ERROR: Not on dimcho branch. Currently on: $CURRENT_BRANCH"
    echo "Please switch to dimcho branch first: git checkout dimcho"
    exit 1
fi

echo ""
echo "✓ On dimcho branch"

# Add all files
echo ""
echo "=== Staging Files ==="
git add -A
echo "✓ All files staged"

# Check if there are changes to commit
if git diff --cached --quiet; then
    echo ""
    echo "No changes to commit"
    exit 0
fi

# Commit
echo ""
echo "=== Committing ==="
COMMIT_MESSAGE="${1:-Update changes}"
git commit -m "$COMMIT_MESSAGE"
echo "✓ Changes committed"

# Push to dimcho
echo ""
echo "=== Pushing to dimcho ==="
git push origin dimcho
echo "✓ Pushed to dimcho branch"

echo ""
echo "=== Complete ==="
git log --oneline -1
