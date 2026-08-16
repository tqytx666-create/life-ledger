#!/bin/bash
# 对 life-ledger 的 Supabase 跑 SQL: bash scripts/db-sql.sh "SELECT 1;"
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
set -a; source "$DIR/credentials.env"; set +a
python3 - "$1" <<'PY'
import sys, json, subprocess, os
sql = sys.argv[1]
body = json.dumps({"query": sql})
r = subprocess.run(["curl","-sS","--max-time","60","-X","POST",
  os.environ["SUPABASE_MGMT_QUERY"],
  "-H","Authorization: Bearer "+os.environ["SUPABASE_MGMT_TOKEN"],
  "-H","Content-Type: application/json","-d",body], capture_output=True, text=True)
print(r.stdout if r.stdout else r.stderr)
PY
