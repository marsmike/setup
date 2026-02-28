#!/bin/bash
# Phase 0 — Server only (run as root)
# Creates the 'mike' user and grants sudo + docker access.
set -euo pipefail

adduser mike
usermod -aG sudo mike
usermod -aG docker mike
