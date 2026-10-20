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
    cat > "$FRIGATE_CHECK_DIR/${@: -1}"
elif [[ $1 == clear ]]; then
    rm -f "$FRIGATE_CHECK_DIR/${@: -1}"
else
    exit 2
fi
FAKE
chmod +x "$check_dir/bin/secret-tool"
export PATH="$check_dir/bin:$PATH"
check_user='test user; $(exit 9)'
check_password='fake $() `exit 7` " quote \ backslash'
printf '%s\n%s\n\n' "$check_user" "$check_password" | bash Credentials.sh > "$check_dir/output"
[[ $(cat "$check_dir/username") == "$check_user" ]]
[[ $(cat "$check_dir/password") == "$check_password" ]]
! rg -Fq -- "$check_user" "$check_dir/argv"
! rg -Fq -- "$check_password" "$check_dir/argv"
printf '\n\n' | bash Credentials.sh > "$check_dir/output"
[[ ! -e $check_dir/username && ! -e $check_dir/password ]]
printf '%s\n' 'credential store/clear, literal special characters, stdin-only secrets: passed'
