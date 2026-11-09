#!/bin/bash
# Double-click in Finder to set up and install Darkstar Robotics.
cd "$(dirname "$0")"
bash Scripts/setup.sh
echo
read -r -p "Press Return to close this window."
