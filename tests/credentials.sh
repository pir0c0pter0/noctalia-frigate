#!/usr/bin/env bash
set -euo pipefail
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
export FRIGATE_CHECK_DIR="$check_dir"
mkdir "$check_dir/bin"
cat > "$check_dir/bin/secret-tool" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FRIGATE_CHECK_DIR/argv"
if [[ $1 == store ]]; then
    if [[ ${FRIGATE_CHECK_STORE_FAIL:-0} == 1 ]]; then exit 2; fi
    cat > "$FRIGATE_CHECK_DIR/${@: -1}"
elif [[ $1 == clear ]]; then
    rm -f "$FRIGATE_CHECK_DIR/${@: -1}"
else
    exit 2
fi
FAKE
cat > "$check_dir/bin/noctalia" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FRIGATE_CHECK_DIR/ipc"
[[ $* == 'msg plugin pir0c0pter0/frigate:service all refresh' || $* == 'msg plugin pir0c0pter0/frigate:doorbell all refresh' ]]
[[ ${FRIGATE_CHECK_IPC_FAIL:-0} != 1 ]]
FAKE
chmod +x "$check_dir/bin/secret-tool" "$check_dir/bin/noctalia"
export LANG=C
export PATH="$check_dir/bin:$PATH"
check_user='test user; $(exit 9)'
check_password='fake $() `exit 7` " quote \ backslash'
printf '%s\n%s\n\n' "$check_user" "$check_password" | bash Credentials.sh > "$check_dir/output"
[[ $(cat "$check_dir/username") == "$check_user" ]]
[[ $(cat "$check_dir/password") == "$check_password" ]]
! rg -Fq -- "$check_user" "$check_dir/argv"
! rg -Fq -- "$check_password" "$check_dir/argv"
[[ $(wc -l < "$check_dir/ipc") == 1 ]]
rg -Fq 'Credentials reloaded' "$check_dir/output"
printf '\n\n' | bash Credentials.sh > "$check_dir/output"
[[ ! -e $check_dir/username && ! -e $check_dir/password ]]
[[ $(wc -l < "$check_dir/ipc") == 2 ]]
export FRIGATE_CHECK_IPC_FAIL=1
printf '%s\n%s\n\n' "$check_user" "$check_password" | bash Credentials.sh > "$check_dir/output"
rg -Fq 'Click Try again' "$check_dir/output"
[[ $(wc -l < "$check_dir/ipc") == 3 ]]
export FRIGATE_CHECK_STORE_FAIL=1
if printf '%s\n%s\n\n' "$check_user" "$check_password" | bash Credentials.sh > "$check_dir/output"; then
    printf '%s\n' 'Expected credential store failure' >&2
    exit 1
fi
[[ $(wc -l < "$check_dir/ipc") == 3 ]]
unset FRIGATE_CHECK_STORE_FAIL FRIGATE_CHECK_IPC_FAIL
printf '%s\n%s\n\n' "$check_user" "$check_password" | bash Credentials.sh doorbell > "$check_dir/output"
rg -Fq 'service noctalia-frigate-doorbell key password' "$check_dir/argv"
rg -Fq 'service noctalia-frigate-doorbell key username' "$check_dir/argv"
[[ $(tail -1 "$check_dir/ipc") == 'msg plugin pir0c0pter0/frigate:doorbell all refresh' ]]
! rg -Fq -- "$check_user" "$check_dir/argv"
! rg -Fq -- "$check_password" "$check_dir/argv"
before=$(wc -l < "$check_dir/argv")
if printf '\n\n' | bash Credentials.sh unexpected > "$check_dir/output" 2>&1; then
    printf '%s\n' 'Expected rejection of unknown credential scope' >&2
    exit 1
fi
[[ $(wc -l < "$check_dir/argv") == "$before" ]]
printf '%s\n' 'credential store/clear, stdin-only secrets, automatic reload and failure handling: passed'
