#!/bin/bash
# Open psql on the SongNotes Supabase database. Password comes from the macOS Keychain.
#   scripts/db.sh                         interactive
#   scripts/db.sh -c "select * from tag_counts"
#   scripts/db.sh -f supabase/migrations/001_init.sql
set -euo pipefail
PGPASSWORD="$(security find-generic-password -a songnotes -s 'SongNotes Supabase DB password' -w)" \
  exec psql "postgresql://postgres.tcpxsxzqzpmosnenodes@aws-1-us-east-1.pooler.supabase.com:5432/postgres?sslmode=require" "$@"
