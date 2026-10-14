#!/bin/bash
#~~~~~~~~~~
# Syncs this repo to one or more build servers and runs scripts/publish.sh on
# each. Unlike simply-cpp-onnxruntime's deploy.sh, this needs to actually run
# on every distro (defaults to all three) since publish.sh compiles from
# source - the result is tied to whichever Ubuntu release built it.
#
# Usage: scripts/deploy.sh [server...]   (defaults to build-jammy build-noble build-resolute)

module="sc-pdfhummus"
user="root"
servers=("$@")
if [ ${#servers[@]} -eq 0 ]; then
    servers=(build-jammy build-noble build-resolute)
fi

scriptfile=$(realpath "$0")
scriptpath="${scriptfile%/*}"
dirpath=$(realpath "$scriptpath"/..)
pushd "$dirpath" || exit

# Each server's output (rsync and the build server's) is also kept in a local log named after
# the server: <suite>/logs/<server>/ inside the simply-cpp suite, otherwise logs/<server>/ in
# /tmp. Skipped when the caller already logs the run (publish-apt.sh sets SC_LOGGING).
suite=$(git -C "$dirpath" rev-parse --show-superproject-working-tree 2>/dev/null)
logs="${suite:-${TMPDIR:-/tmp}/simply-cpp}/logs"
logged() {
    local server="$1"
    shift
    if [ -n "${SC_LOGGING:-}" ]; then
        "$@"
        return
    fi
    mkdir -p "$logs/$server"
    local log_file
    log_file="$logs/$server/$(date -u +%Y%m%dT%H%M%SZ)-$module.log"
    echo "Logging to $log_file"
    "$@" 2>&1 | tee "$log_file"
    return "${PIPESTATUS[0]}"
}

deploy_to() {
    local server="$1"
    rsync -av --no-owner --no-group ./ "$user@$server:/var/www/build/$module/" --exclude=".git" --exclude=".idea" --exclude="work" --exclude="pkg" --delete || return
    ssh "$user@$server" "cd /var/www/build/$module && bash scripts/publish.sh"
}

overall=0
for server in "${servers[@]}"; do
    echo "==> $server"
    if ! logged "$server" deploy_to "$server"; then
        echo "$server FAILED" >&2
        overall=1
    fi
done

popd || exit
exit $overall
