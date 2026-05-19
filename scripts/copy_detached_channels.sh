#!/usr/bin/env bash
set -euo pipefail

# copy_detached_channels.sh
# Find channels in a Murmur (mumble-server) sqlite DB that are NOT reachable
# from the active root (parent_id = 0) and deep-copy each detached subtree
# to be children of the active root (parent_id = 0).
#
# Safety: dry-run by default. You must pass --apply to actually write changes.
# You should run this script as root (sudo) so backups and DB writes work.

DB=/var/lib/mumble-server/mumble-server.sqlite
SERVER_ID=""
APPLY=0
STOP_SERVICE=0
BACKUP=1

usage(){
  cat <<EOF
Usage: $0 [--db /path/to/mumble-server.sqlite] [--server-id ID] [--apply] [--stop]

Options:
  --db PATH        Path to sqlite DB (default: /var/lib/mumble-server/mumble-server.sqlite)
  --server-id ID   Server ID to operate on (auto-detect if only one present)
  --apply          Actually apply changes (default: dry-run)
  --stop           Stop `mumble-server` service while modifying DB (recommended with --apply)
  --no-backup      Skip creating a backup (not recommended)
  -h, --help       Show this help

This script will create a backup at /tmp/mumble-server.sqlite.bak (unless --no-backup).
Run as root (sudo) so the script can backup and write the DB.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    --server-id) SERVER_ID="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --stop) STOP_SERVICE=1; shift ;;
    --no-backup) BACKUP=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 not found; install sqlite3 and re-run." >&2
  exit 1
fi

if [ ! -f "$DB" ]; then
  echo "Database not found at $DB" >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

echo "DB: $DB"

# determine server id if not provided
if [ -z "$SERVER_ID" ]; then
  cnt=$(sqlite3 "$DB" "SELECT COUNT(*) FROM servers;" 2>/dev/null || echo 0)
  if [ "$cnt" -eq 0 ]; then
    echo "No rows in servers table; cannot determine server_id" >&2
    exit 1
  elif [ "$cnt" -eq 1 ]; then
    SERVER_ID=$(sqlite3 "$DB" "SELECT server_id FROM servers LIMIT 1;")
    echo "Auto-detected server_id=$SERVER_ID"
  else
    echo "Multiple servers in DB; please pass --server-id" >&2
    sqlite3 "$DB" "SELECT * FROM servers;"
    exit 1
  fi
fi

echo "Operating on server_id=$SERVER_ID"

backup_db(){
  if [ "$BACKUP" -eq 0 ]; then
    echo "Skipping backup (user requested).";
    return
  fi
  echo "Creating DB backup to /tmp/mumble-server.sqlite.bak..."
  sqlite3 "$DB" ".backup '/tmp/mumble-server.sqlite.bak'" || {
    echo "Fallback: stop service and copy file to /tmp/...";
    systemctl stop mumble-server || true
    cp -a "$DB" /tmp/mumble-server.sqlite.bak
    systemctl start mumble-server || true
  }
  chown "$SUDO_USER:${SUDO_USER:+$(id -gn $SUDO_USER)" /tmp/mumble-server.sqlite.bak 2>/dev/null || true
  ls -lh /tmp/mumble-server.sqlite.bak || true
}

sql_escape(){
  # Escape single quotes for SQL string literals
  printf "%s" "$1" | sed "s/'/''/g"
}

echo "Collecting detached channel roots (dry-run: $((1-APPLY)) )..."

readarray -t DETACHED_ROOTS < <(sqlite3 "$DB" -separator $'|' -noheader <<SQL
WITH RECURSIVE reach(channel_id) AS (
  SELECT channel_id FROM channels WHERE (parent_id IS NULL OR parent_id = 0) AND server_id = $SERVER_ID
  UNION ALL
  SELECT c.channel_id FROM channels c JOIN reach r ON c.parent_id = r.channel_id AND c.server_id = $SERVER_ID
), det AS (
  SELECT channel_id, parent_id FROM channels WHERE server_id = $SERVER_ID AND channel_id NOT IN (SELECT channel_id FROM reach)
)
SELECT d.channel_id FROM det d WHERE d.parent_id IS NULL OR d.parent_id = 0 OR d.parent_id NOT IN (SELECT channel_id FROM det);
SQL
)

if [ ${#DETACHED_ROOTS[@]} -eq 0 ]; then
  echo "No detached channel roots found for server_id=$SERVER_ID. Nothing to do."
  exit 0
fi

echo "Found detached roots: ${DETACHED_ROOTS[*]}"

if [ "$APPLY" -ne 1 ]; then
  echo "DRY RUN: the script will print planned actions. To apply, re-run with --apply --stop (recommended)."
fi

if [ "$BACKUP" -eq 1 ]; then
  backup_db
fi

if [ "$STOP_SERVICE" -eq 1 ]; then
  echo "Stopping mumble-server service..."
  systemctl stop mumble-server || true
fi

declare -A MAP_OLD2NEW
ALL_OLD_IDS=()

for ROOT in "${DETACHED_ROOTS[@]}"; do
  echo "Processing detached root $ROOT"

  # get subtree nodes, ordered by depth so parents come before children
  readarray -t NODES < <(sqlite3 "$DB" -separator $'|' -noheader <<SQL
WITH RECURSIVE subtree(channel_id,parent_id,name,inheritacl,depth) AS (
  SELECT channel_id, parent_id, name, coalesce(inheritacl,0), 0 FROM channels WHERE server_id=$SERVER_ID AND channel_id = $ROOT
  UNION ALL
  SELECT c.channel_id, c.parent_id, c.name, coalesce(c.inheritacl,0), subtree.depth + 1
    FROM channels c JOIN subtree ON c.parent_id = subtree.channel_id AND c.server_id = $SERVER_ID
)
SELECT channel_id || '|' || ifnull(parent_id,'') || '|' || replace(name, '\n', ' ') || '|' || inheritacl || '|' || depth FROM subtree ORDER BY depth ASC, channel_id ASC;
SQL
)

  # collect old ids for later channel_links copy
  for entry in "${NODES[@]}"; do
    oldid=$(printf '%s' "$entry" | cut -d '|' -f1)
    ALL_OLD_IDS+=("$oldid")
  done

  for entry in "${NODES[@]}"; do
    oldid=$(printf '%s' "$entry" | cut -d '|' -f1)
    oldparent=$(printf '%s' "$entry" | cut -d '|' -f2)
    oldname=$(printf '%s' "$entry" | cut -d '|' -f3)
    oldinherit=$(printf '%s' "$entry" | cut -d '|' -f4)

    # determine new parent
    if [ -z "$oldparent" ] || [ "$oldparent" = "0" ]; then
      newparent=0
    else
      newparent=${MAP_OLD2NEW[$oldparent]:-0}
    fi

    # compute a new channel_id
    newid=$(sqlite3 "$DB" "SELECT COALESCE(MAX(channel_id),0)+1 FROM channels WHERE server_id = $SERVER_ID;")

    echo "Would create channel: old_id=$oldid -> new_id=$newid parent->$newparent name='$oldname' inheritacl=$oldinherit"

    if [ "$APPLY" -eq 1 ]; then
      esc_name=$(sql_escape "$oldname")
      sqlite3 "$DB" "INSERT INTO channels(server_id, channel_id, parent_id, name, inheritacl) VALUES ($SERVER_ID, $newid, $newparent, '$esc_name', $oldinherit);"

      # copy channel_info
      sqlite3 "$DB" "INSERT INTO channel_info(server_id, channel_id, key, value) SELECT server_id, $newid, key, value FROM channel_info WHERE server_id = $SERVER_ID AND channel_id = $oldid;"

      # copy groups and group_members
      # for each group on the old channel, create a corresponding group on the new channel
      while IFS='|' read -r old_group_id gname ginherit ginheritable; do
        if [ -z "$old_group_id" ]; then continue; fi
        esc_gname=$(sql_escape "$gname")
        sqlite3 "$DB" "INSERT INTO groups(server_id, name, channel_id, inherit, inheritable) VALUES ($SERVER_ID, '$esc_gname', $newid, $ginherit, $ginheritable);"
        # fetch the new group_id
        new_group_id=$(sqlite3 "$DB" "SELECT group_id FROM groups WHERE server_id=$SERVER_ID AND channel_id=$newid AND name='$esc_gname' LIMIT 1;")
        if [ -n "$new_group_id" ]; then
          sqlite3 "$DB" "INSERT INTO group_members(group_id, server_id, user_id, addit) SELECT $new_group_id, server_id, user_id, addit FROM group_members WHERE server_id=$SERVER_ID AND group_id=$old_group_id;"
        fi
      done < <(sqlite3 "$DB" -separator $'|' -noheader "SELECT group_id, name, inherit, inheritable FROM groups WHERE server_id=$SERVER_ID AND channel_id=$oldid;")

      # copy ACL rows
      sqlite3 "$DB" "INSERT INTO acl(server_id, channel_id, priority, user_id, group_name, apply_here, apply_sub, grantpriv, revokepriv) SELECT server_id, $newid, priority, user_id, group_name, apply_here, apply_sub, grantpriv, revokepriv FROM acl WHERE server_id=$SERVER_ID AND channel_id=$oldid;"

      # copy channel_listeners
      sqlite3 "$DB" "INSERT INTO channel_listeners(server_id, user_id, channel_id, volume_adjustment, enabled) SELECT server_id, user_id, $newid, volume_adjustment, enabled FROM channel_listeners WHERE server_id=$SERVER_ID AND channel_id=$oldid;"

    fi

    MAP_OLD2NEW[$oldid]=$newid
  done
done

# Copy channel_links for all old ids collected above
if [ "$APPLY" -eq 1 ]; then
  # build CSV list of old ids
  OLD_CSV=$(IFS=,; echo "${ALL_OLD_IDS[*]}")
  # iterate links where channel_id or link_id references old ids
  sqlite3 "$DB" -separator $'|' -noheader "SELECT channel_id, link_id FROM channel_links WHERE server_id=$SERVER_ID AND (channel_id IN ($OLD_CSV) OR link_id IN ($OLD_CSV));" | while IFS='|' read -r ch lid; do
    new_ch=${MAP_OLD2NEW[$ch]:-}
    if [ -z "$new_ch" ]; then continue; fi
    new_l=${MAP_OLD2NEW[$lid]:-$lid}
    sqlite3 "$DB" "INSERT INTO channel_links(server_id, channel_id, link_id) VALUES ($SERVER_ID, $new_ch, $new_l);"
  done
fi

echo "Done. Mappings (old -> new):"
for k in "${!MAP_OLD2NEW[@]}"; do echo "$k -> ${MAP_OLD2NEW[$k]}"; done

if [ "$STOP_SERVICE" -eq 1 ]; then
  echo "Starting mumble-server service..."
  systemctl start mumble-server || true
fi

echo "Finished. If this was a dry-run re-run with --apply --stop to actually create the copies (ensure backup first)."
