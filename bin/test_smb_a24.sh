#!/usr/bin/env bash
# Check startup ordering without touching the real session or credentials.
set -eu
script=${1:-$HOME/.local/bin/smb-a24-mount}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/home/.config/smb-a24"
printf 'user=test\ndomain=test\npassword=test\n' > "$test_dir/home/.config/smb-a24/credentials"
cat > "$test_dir/bin/stub" <<'STUB'
#!/usr/bin/env bash
set -eu
cmd=${0##*/}
printf '%s\n' "$cmd $*" >> "$TEST_LOG"
case $cmd in
  timeout) shift; exec "$@" ;;
  gio)
    if [[ ${FAIL_GVFS:-0} == 1 ]]; then exit 1; fi
    touch "$TEST_DIR/ready"
    printf 'smb://192.168.2.240/share\n'
    ;;
  ls) [[ -f "$TEST_DIR/bridge" ]] ;;
  pgrep) exit 1 ;;
  systemd-run)
    [[ -f "$TEST_DIR/ready" ]] || touch "$TEST_DIR/bad-order"
    touch "$TEST_DIR/bridge"
    ;;
esac
STUB
chmod +x "$test_dir/bin/stub"
for cmd in timeout gio ls pgrep systemd-run fusermount3 mkdir sleep; do
  ln -s stub "$test_dir/bin/$cmd"
done
export TEST_DIR=$test_dir TEST_LOG=$test_dir/log
export HOME=$test_dir/home XDG_RUNTIME_DIR=$test_dir/runtime
export PATH="$test_dir/bin:$PATH"
bash "$script"
if [[ -f "$test_dir/bad-order" ]]; then
  echo 'FAIL: FUSE launched before GVFS was ready' >&2
  exit 1
fi
rm -f "$test_dir/bridge" "$test_dir/ready" "$TEST_LOG"
if FAIL_GVFS=1 bash "$script"; then
  echo 'FAIL: script succeeded despite GVFS activation failure' >&2
  exit 1
fi
if grep -q '^systemd-run ' "$TEST_LOG"; then
  echo 'FAIL: FUSE launched despite GVFS activation failure' >&2
  exit 1
fi
echo 'PASS: startup ordering and activation failure'
