snipman
Your personal snippet brain. Instant, offline, private.

Store every command, config, and code snippet you keep re-Googling —then find it in 0.2 seconds with grep-speed search. Tag them, executethem directly, copy to clipboard, export/import to share between machines.

the problem
I kept scrolling bash history and re-Googling the same 30 commands —that docker prune, that git undo, that config line. So I built my ownprivate Stack Overflow that never forgets.

usage
./snippet.sh add <name> [tags]        # opens editor, save+exit to store./snippet.sh find <keyword>           # search across names, tags, content./snippet.sh show <name>              # pretty display with line numbers./snippet.sh copy <name>              # clipboard (auto-detects xclip/wl-copy/pbcopy/clip.exe for WSL)./snippet.sh run <name>               # EXECUTES the snippet — not just shows it./snippet.sh run <name> arg1 arg2     # passes arguments through./snippet.sh list [tag]               # browse all, or filter by tag./snippet.sh tags                     # every tag you've used./snippet.sh del <name>               # delete (asks for confirmation)./snippet.sh export <file>            # backup / share with friends./snippet.sh import <file>            # restore on another machine
examples
# save that command you always forget./snippet.sh add docker-clean docker#   (nano opens — type: docker system prune -af --volumes — save, exit)# save a personal tool./snippet.sh add weather api#   (nano opens — type: ~/weather.sh mumbai)# find it 3 months later./snippet.sh find docker./snippet.sh run docker-clean     # executes it right there# your whole arsenal./snippet.sh list./snippet.sh tags
features
fuzzy-ish search across snippet names, tags, AND content
tags — organize by language/project/purpose
execute mode — snippets aren't just text, they're runnable
clipboard integration — works on WSL (clip.exe), Linux (xclip/wl-copy), macOS (pbcopy)
export/import — backup, sync between machines, share your arsenal
100% offline — no cloud, no login, your data in one local TSV file at ~/.snipman/
self-test (offline)
./snippet.sh --selftest
bash 4+, coreutils. Clipboard optional. MIT licensed.


# snipman — dependency manifest (deliberately tiny)
# snippet
