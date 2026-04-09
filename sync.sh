#!/bin/bash

# Fetch and pull from remote, then push changes

set -e  # Exit on error

echo "Fetching from remote..."
git fetch origin

echo "Pulling from remote..."
git pull origin HEAD

#echo "Pushing to remote..."
#git push -u origin HEAD

echo "✓ Sync complete!"
