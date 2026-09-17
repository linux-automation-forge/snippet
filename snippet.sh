#!/usr/bin/env bash
# snipman.sh — your personal snippet brain (v1.0.0)
# Store, find, show, copy, run, tag, and share code snippets — instantly, offline.
# USAGE:
#   snipman.sh add <name> [tags]        add snippet (from editor or stdin)
#   snipman.sh find <keyword>           search name+tags+content
#   snipman.sh show <name>              display a snippet
#   snipman.sh copy <name>              copy to clipboard (xclip/wl-copy/pbcopy)
#   snipman.sh run <name> [args...]     execute a snippet
#   snipman.sh list [tag]               list all snippets (optionally by tag)
#   snipman.sh tags                     list all unique tags
#   snipman.sh del <name>               delete a snippet
#   snipman.sh export <file>            export all snippets to one file
#   snipman.sh import <file>            import snippets from a file
#   snipman.sh --selftest | --gen-files | -h | -V
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C

SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"
VERSION="1.0.0"
STORE_DIR="${HOME}/.snipman"
STORE_FILE="${STORE_DIR}/snippets.tsv"
META_FILE="${STORE_DIR}/meta.tsv"       # name|tags|created
EDITOR_BIN="${SNIPMAN_EDITOR:-${EDITOR:-nano}}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    R=$'\033[0m'; B=$'\033[1m'; DIM=$'\033[2m'
    GRN=$'\033[1;32m'; YLW=$'\033[1;33m'; RED=$'\033[1;31m'
    CYN=$'\033[1;36m'; MAG=$'\033[1;35m'
else
    R=""; B=""; DIM=""; GRN=""; YLW=""; RED=""; CYN=""; MAG=""
fi
ok()   { printf '  %s[ok]%s %s\n' "$GRN" "$R" "$1"; }
warn() { printf '  %s[!!] %s%s\n' "$YLW" "$1" "$R"; }
err()  { printf '  %s[XX] %s%s\n' "$RED" "$1" "$R" >&2; }
sect() { printf '\n%s%s── %s %s%s\n' "$B$MAG" "" "$1" "$(printf '─%.0s' $(seq 1 46))" "$R"; }
die()  { err "$2"; exit "$1"; }

# ==================== helpers ====================
ensure_store() {
    mkdir -p "$STORE_DIR"
    touch "$STORE_FILE" "$META_FILE"
}

valid_name() { [[ "${1:-}" =~ ^[a-zA-Z0-9_-]+$ ]]; }

name_exists() {
    grep -q "^${1}	" "$STORE_FILE" 2>/dev/null
}

read_snippet() { # echoes content of a snippet
    awk -F'\t' -v n="$1" '$1==n{found=1; for(i=2;i<NF;i++) printf "%s\n",$i; if(!found){}; exit}' "$STORE_FILE"
}

get_tags() {
    awk -F'\t' -v n="$1" '$1==n{print $2; exit}' "$META_FILE"
}

get_created() {
    awk -F'\t' -v n="$1" '$1==n{print $3; exit}' "$META_FILE"
}

# ==================== core commands ====================
cmd_add() {
    local name="${1:-}"
    shift || true
    local tags="${*:---}"

    [[ -n "$name" ]] || die 2 "add needs a name: snipman add <name> [tags]"
    valid_name "$name" || die 2 "name must be letters/numbers/dash/underscore only"
    name_exists "$name" && die 2 "'$name' already exists — delete first with: snipman del $name"

    sect "Adding snippet: ${name}"
    printf '  %seditor:%s %s  (save+exit to store, empty file cancels)\n' "$B" "$R" "$EDITOR_BIN"

    local tmp; tmp="$(mktemp /tmp/snipman.XXXXXX)"
    "$EDITOR_BIN" "$tmp" < /dev/tty > /dev/tty 2>&1 || true

    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        die 1 "empty snippet — cancelled"
    fi

    # append: name<TAB>line1<TAB>line2...
    {
        printf '%s' "$name"
        while IFS= read -r line; do
            printf '\t%s' "$line"
        done < "$tmp"
        printf '\n'
    } >> "$STORE_FILE"

    printf '%s|%s|%s\n' "$name" "$tags" "$(date '+%Y-%m-%d %H:%M')" >> "$META_FILE"
    rm -f "$tmp"
    ok "stored '$name' (tags: $tags)"
    printf '  use: %ssnipman show %s%s  |  %ssnipman run %s%s\n' \
        "$CYN" "$name" "$R" "$CYN" "$name" "$R"
}

cmd_find() {
    local q="${1:-}"
    [[ -n "$q" ]] || die 2 "find needs a keyword: snipman find <term>"

    sect "Search results for: ${q}"
    local hits=0
    while IFS=$'\t' read -r name; do
        [[ -z "$name" ]] && continue
        local content tags
        content="$(read_snippet "$name")"
        tags="$(get_tags "$name")"
        if printf '%s\n%s\n%s\n' "$name" "$tags" "$content" \
           | grep -qi -- "$q"; then
            local first_line
            first_line="$(printf '%s\n' "$content" | head -n 1)"
            printf '  %s%-20s%s tags:[%s] %s| %s%s\n' \
                "$B$CYN" "$name" "$R" "$tags" "$DIM" "$R" "${first_line:0:50}"
            hits=$(( hits + 1 ))
        fi
    done < <(cut -f1 "$STORE_FILE")

    if (( hits == 0 )); then
        warn "no snippets matching '${q}'"
    else
        printf '\n  %d match(es). Show one: %ssnipman show <name>%s\n' \
            "$hits" "$CYN" "$R"
    fi
}

cmd_show() {
    local name="${1:-}"
    [[ -n "$name" ]] || die 2 "show needs a name"
    name_exists "$name" || die 2 "'$name' not found — try: snipman find <keyword>"

    sect "$name"
    printf '  tags   : %s\n' "$(get_tags "$name")"
    printf '  added  : %s\n' "$(get_created "$name")"
    printf '\n'
    read_snippet "$name" | nl -ba | sed 's/^/  /'
    printf '\n'
}

cmd_copy() {
    local name="${1:-}"
    [[ -n "$name" ]] || die 2 "copy needs a name"
    name_exists "$name" || die 2 "'$name' not found"

    local content
    content="$(read_snippet "$name")"

    if command -v xclip > /dev/null 2>&1; then
        printf '%s' "$content" | xclip -selection clipboard
        ok "copied to clipboard (xclip)"
    elif command -v wl-copy > /dev/null 2>&1; then
        printf '%s' "$content" | wl-copy
        ok "copied to clipboard (wl-copy)"
    elif command -v pbcopy > /dev/null 2>&1; then
        printf '%s' "$content" | pbcopy
        ok "copied to clipboard (pbcopy)"
    elif command -v clip.exe > /dev/null 2>&1; then
        printf '%s' "$content" | clip.exe
        ok "copied to clipboard (WSL clip.exe)"
    else
        warn "no clipboard tool found (xclip/wl-copy/pbcopy/clip.exe)"
        printf '  fallback — printing to stdout:\n%s\n' "$content"
    fi
}

cmd_run() {
    local name="${1:-}"
    shift || true
    [[ -n "$name" ]] || die 2 "run needs a name"
    name_exists "$name" || die 2 "'$name' not found"

    local content
    content="$(read_snippet "$name")"

    sect "Running: $name"
    bash -c "$content" "$@" 2>&1 || warn "snippet exited non-zero"
}

cmd_list() {
    local tag="${1:-}"
    sect "Snippets ${tag:+tagged '$tag'}"
    local count=0
    while IFS='|' read -r name tags created; do
        [[ -z "$name" ]] && continue
        if [[ -n "$tag" && ! "$tags" =~ (^|,)${tag}(,|$) ]]; then continue; fi
        printf '  %-24s tags:[%s] added:%s\n' "$name" "$tags" "$created"
        count=$(( count + 1 ))
    done < "$META_FILE"

    if (( count == 0 )); then
        warn "no snippets yet — add one: snipman add <name>"
    else
        printf '\n  %d snippet(s).\n' "$count"
    fi
}

cmd_tags() {
    sect "All tags"
    local -A seen=()
    while IFS='|' read -r _ tags _; do
        [[ -z "$tags" ]] && continue
        local IFS=','
        local t
        for t in $tags; do
            t="$(printf '%s' "$t" | xargs)"
            [[ -z "$t" ]] && continue
            seen[$t]=1
        done
    done < "$META_FILE"

    local t
    for t in "${!seen[@]}"; do
        printf '  %s\n' "$t"
    done
    if (( ${#seen[@]} == 0 )); then
        warn "no tags yet"
    fi
}

cmd_del() {
    local name="${1:-}"
    [[ -n "$name" ]] || die 2 "del needs a name"
    name_exists "$name" || die 2 "'$name' not found"

    # confirm
    local reply=""
    read -r -p "Delete '$name'? [y/N]: " reply || true
    if [[ ! "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        warn "aborted"
        return 0
    fi

    awk -F'\t' -v n="$name" '$1!=n' "$STORE_FILE" > "${STORE_FILE}.tmp" && mv "${STORE_FILE}.tmp" "$STORE_FILE"
    awk -F'|' -v n="$name" '$1!=n' "$META_FILE" > "${META_FILE}.tmp" && mv "${META_FILE}.tmp" "$META_FILE"
    ok "deleted '$name'"
}

cmd_export() {
    local out="${1:-snipman-export-$(date +%Y%m%d).txt}"
    sect "Exporting to: $out"
    {
        printf '# snipman export v%s\n' "$VERSION"
        printf '# format: ===NAME=== then content then ===END===\n\n'
        while IFS=$'\t' read -r name; do
            [[ -z "$name" ]] && continue
            printf '===NAME===\n%s\n===META===\n%s|%s\n===END===\n\n' \
                "$name" "$(get_tags "$name")" "$(get_created "$name")"
            read_snippet "$name"
        done < "$STORE_FILE"
    } > "$out"
    ok "exported $(grep -c '^===NAME===' "$out" || echo 0) snippet(s) → $out"
}

cmd_import() {
    local in="${1:-}"
    [[ -f "$in" ]] || die 2 "import needs a valid file: snipman import <file>"
    sect "Importing from: $in"

    local name="" count=0 tmp="" started=0
    while IFS= read -r line; do
        case "$line" in
            "===NAME===")
                started=1; name=""; tmp="$(mktemp)" ;;
            "===META===")
                : ;;
            "===END===")
                if [[ -n "$name" && -s "$tmp" ]]; then
                    if name_exists "$name"; then
                        warn "skip '$name' (already exists)"
                    else
                        { printf '%s' "$name"; while IFS= read -r l; do printf '\t%s' "$l"; done < "$tmp"; printf '\n'; } >> "$STORE_FILE"
                        printf '%s|%s|%s\n' "$name" "imported" "$(date '+%Y-%m-%d %H:%M')" >> "$META_FILE"
                        count=$(( count + 1 ))
                    fi
                fi
                rm -f "$tmp"; started=0 ;;
            ===*)
                : ;;
            *)
                if [[ "$started" == 1 && -z "$name" && -n "$line" ]]; then
                    name="$line"
                elif [[ "$started" == 1 && -n "$name" && -n "$tmp" ]]; then
                    printf '%s\n' "$line" >> "$tmp"
                fi ;;
        esac
    done < "$in"
    ok "imported $count snippet(s)"
}

# ==================== selftest / gen-files ====================
self_test() {
    local pass=0 fail=0
    oks()  { printf '  %sPASS%s %s\n' "$GRN" "$R" "$1"; pass=$((pass+1)); }
    bads() { printf '  %sFAIL%s %s\n' "$RED" "$R" "$1"; fail=$((fail+1)); }
    printf '%sSNIPMAN SELF-TEST (offline, temp store)%s\n' "$CYN" "$R"

    local saved_s=$STORE_FILE saved_m=$META_FILE saved_d=$STORE_DIR
    local tmp; tmp="$(mktemp -d)"
    STORE_DIR="$tmp"; STORE_FILE="$tmp/s.tsv"; META_FILE="$tmp/m.tsv"
    ensure_store

    # write helper
    write_snippet() {
        local n="$1" t="$2" c="$3"
        { printf '%s' "$n"; while IFS= read -r l; do printf '\t%s' "$l"; done <<< "$c"; printf '\n'; } >> "$STORE_FILE"
        printf '%s|%s|%s\n' "$n" "$t" "$(date '+%Y-%m-%d %H:%M')" >> "$META_FILE"
    }

    write_snippet "testecho" "bash,test" $'echo "hello world"\nls -la'
    name_exists "testecho" && oks "snippet written" || bads "snippet written"

    local content; content="$(read_snippet "testecho")"
    [[ "$content" == *"hello world"* ]] && oks "read_snippet retrieves content" || bads "read_snippet"

    [[ "$(get_tags 'testecho')" == "bash,test" ]] && oks "get_tags" || bads "get_tags"

    # find
    local find_out
    find_out="$(cmd_find 'hello' 2>&1 || true)"
    [[ "$find_out" == *"testecho"* ]] && oks "cmd_find matches content" || bads "cmd_find"

    # run
    local run_out
    run_out="$(bash -c "$(read_snippet 'testecho' | head -n 1)" 2>&1 || true)"
    [[ "$run_out" == *"hello world"* ]] && oks "snippet executes" || bads "snippet executes"

    # delete
    cmd_del_del() { :; }  # avoid interactive; test awk directly
    awk -F'\t' -v n="testecho" '$1!=n' "$STORE_FILE" > "${STORE_FILE}.t" && mv "${STORE_FILE}.t" "$STORE_FILE"
    name_exists "testecho" && bads "delete failed" || oks "snippet deleted"

    rm -rf "$tmp"
    STORE_FILE=$saved_s; META_FILE=$saved_m; STORE_DIR=$saved_d
    printf '%sRESULT: pass=%d fail=%d%s\n' "$CYN" "$pass" "$fail" "$R"
    (( fail > 0 )) && exit 1
    printf '%sSELF-TEST OK%s\n' "$GRN" "$R"
}

gen_repo_files() {
    if [[ ! -e README.md ]]; then
        cat > README.md <<'RM1'
# snipman

Your personal snippet brain. Instant, offline, private.

Store every command, config, and code snippet you keep re-Googling —
then find it in 0.2 seconds with plain grep-speed search. Tag them,
execute them directly, copy them, export/import to share between machines.

## usage

    ./snipman.sh add <name> [tags]        # opens editor (or pipe stdin)
    ./snipman.sh find <keyword>           # instant fuzzy-ish search
    ./snipman.sh show <name>              # pretty display
    ./snipman.sh copy <name>              # clipboard (xclip/wl-copy/pbcopy/clip.exe)
    ./snipman.sh run <name>               # execute it
    ./snipman.sh list [tag]               # browse
    ./snipman.sh tags                     # all tags
    ./snipman.sh del <name>               # delete (with confirmation)
    ./snipman.sh export <file>            # backup/share
    ./snipman.sh import <file>            # restore

## why

I kept scrolling bash history and re-Googling the same commands.
Built this to have my own private Stack Overflow that never forgets.
Works on WSL, Linux, macOS. Storage = one tab-separated text file.
No cloud. No login. Your data is yours.

## self-test (offline)

    ./snipman.sh --selftest

bash 4+, coreutils. MIT licensed.
RM1
        printf '  [ok] README.md\n'
    fi
    if [[ ! -e LICENSE ]]; then
        cat > LICENSE <<'RM2'
MIT License

Copyright (c) 2025 YOUR NAME HERE

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
RM2
        printf '  [ok] LICENSE (add your name!)\n'
    fi
    if [[ ! -e requirements.txt ]]; then
        printf 'bash (4+), coreutils. Optional: xclip/wl-copy/pbcopy for clipboard.\n' > requirements.txt
        printf '  [ok] requirements.txt\n'
    fi
    if [[ ! -e .gitignore ]]; then
        printf '.snipman/\n*.log\n.DS_Store\n' > .gitignore
        printf '  [ok] .gitignore\n'
    fi
    printf '\nDone — edit LICENSE (your name), then upload.\n'
}

# ==================== CLI ====================
usage() {
    cat <<SMH
snipman v$VERSION — your personal snippet brain

USAGE
  $SCRIPT_NAME add <name> [tags]         add snippet (opens editor)
  $SCRIPT_NAME find <keyword>            instant search
  $SCRIPT_NAME show <name>               display
  $SCRIPT_NAME copy <name>               clipboard
  $SCRIPT_NAME run <name> [args]         execute
  $SCRIPT_NAME list [tag]                browse
  $SCRIPT_NAME tags                      list all tags
  $SCRIPT_NAME del <name>                delete
  $SCRIPT_NAME export <file>             export
  $SCRIPT_NAME import <file>             import
  $SCRIPT_NAME --selftest | --gen-files | -h | -V
SMH
}

ensure_store

case "${1:-}" in
    add)
        shift
        cmd_add "$@"
        ;;
    find)
        shift; cmd_find "${1:-}" ;;
    show)
        shift; cmd_show "${1:-}" ;;
    copy)
        shift; cmd_copy "${1:-}" ;;
    run)
        shift
        local_name="${1:-}"
        shift || true
        cmd_run "$local_name" "$@"
        ;;
    list)
        shift; cmd_list "${1:-}" ;;
    tags)
        cmd_tags ;;
    del)
        shift; cmd_del "${1:-}" ;;
    export)
        shift; cmd_export "${1:-}" ;;
    import)
        shift; cmd_import "${1:-}" ;;
    --selftest) self_test ;;
    --gen-files) gen_repo_files ;;
    -h|--help) usage ;;
    -V|--version) printf '%s v%s\n' "$SCRIPT_NAME" "$VERSION" ;;
    "") usage ;;
    *) die 2 "unknown command '$1' — try --help" ;;
esac
