#!/bin/sh
# Offline tests for plugins/port-kill: a fake lsof reports only sleep processes
# this test spawns, so no other process is ever listed or signalled.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script=$repo/plugins/port-kill/port-kill
root=$(mktemp -d "$repo/tests/.port-kill-test.XXXXXX")
pids=
cleanup() {
    for pid in $pids; do kill -9 "$pid" 2>/dev/null || :; done
    rm -rf -- "$root"
}
trap cleanup 0
trap 'exit 1' 1 2 3 15
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$root/bin"

# web and db exit on TERM; stubborn ignores TERM so only --force kills it.
# Each is double-forked so init reaps it: a killed direct child would linger as
# a zombie, which kill -0 still reports as alive.
spawn() { sh -c "$1"' > /dev/null 2>&1 & echo $!'; }
web=$(spawn 'exec sleep 300')
db=$(spawn 'exec sleep 300')
stubborn=$(spawn 'trap "" TERM; exec sleep 300')
pids="$web $db $stubborn"
sleep 0.2

# The fake answers the TCP and UDP queries with -F field output. Port 3000 is
# reported twice (IPv4 and IPv6) and a connected UDP socket must be ignored.
cat > "$root/bin/lsof" <<LSOF
#!/bin/sh
case "\$*" in
    *-iTCP*)
        printf 'p%s\ncnode\nLalice\nf20\nPTCP\nn*:3000\nf21\nPTCP\nn[::]:3000\n' "$web"
        printf 'p%s\ncpostgres\nLbob\nf5\nPTCP\nn127.0.0.1:5432\n' "$db" ;;
    *-iUDP*)
        printf 'p%s\ncmdns\nLalice\nf7\nPUDP\nn*:5353\nf8\nPUDP\nn10.0.0.2:5000->1.1.1.1:443\nf9\nPUDP\nn*:*\n' "$stubborn" ;;
    *) exit 1 ;;
esac
LSOF
chmod +x "$root/bin/lsof"
PK_LSOF=$root/bin/lsof PK_KILL_WAIT=1
export PK_LSOF PK_KILL_WAIT
pk() { sh "$script" "$@"; }

[ -f "$script" ] || fail 'port-kill script missing'
sh -n "$script" || fail 'port-kill syntax'

# List is sorted by port, de-duplicated, and shows proto, pid and user.
pk list > "$root/list" || fail 'list failed'
head -n 1 "$root/list" | grep -q 'PORT.*PROTO.*PID.*USER.*COMMAND' || fail 'list header'
[ "$(tail -n +2 "$root/list" | awk '{ print $1 }' | tr '\n' ' ')" = '3000 5353 5432 ' ] ||
    fail "list not sorted or not de-duplicated: $(cat "$root/list")"
tail -n +2 "$root/list" | awk -v p="$web" '$1 == 3000 && $2 == "TCP" && $3 == p && $4 == "alice"' | grep -q . ||
    fail 'port 3000 row'
tail -n +2 "$root/list" | awk -v p="$stubborn" '$1 == 5353 && $2 == "UDP" && $3 == p' | grep -q . || fail 'udp row'
tail -n +2 "$root/list" | awk -v p="$db" '$1 == 5432 && $3 == p' | grep -q 'sleep' || fail 'full command not shown'
grep -q '5000' "$root/list" && fail 'connected udp socket listed'

# A port argument filters exactly that port; invalid ports are rejected.
[ "$(pk list 3000 | tail -n +2 | awk '{ print $1 }')" = 3000 ] || fail 'list 3000 filter'
[ "$(pk list 300 | tail -n +2 | wc -l | tr -d ' ')" -eq 0 ] || fail 'filter matched a prefix'
for port in 0 65536 abc -1 03000 123456; do
    if pk list "$port" > /dev/null 2>&1; then fail "invalid port accepted: $port"; fi
done

# Missing lsof is a clear error.
if PK_LSOF=$root/bin/no-such-lsof pk list > /dev/null 2> "$root/err"; then fail 'missing lsof accepted'; fi
grep -q 'lsof' "$root/err" || fail 'missing lsof not explained'

# Invalid pids are rejected before anything is signalled.
for pid in abc 1 0 '' -5 "$web,1"; do
    if pk kill "$pid" > /dev/null 2>&1; then fail "invalid pid accepted: '$pid'"; fi
done
if pk kill > /dev/null 2>&1; then fail 'kill without pids accepted'; fi
if pk kill "$web" abc > /dev/null 2>&1; then fail 'mixed invalid pid accepted'; fi
kill -0 "$web" 2>/dev/null || fail 'rejected kill signalled a valid pid'

# TERM stops a normal process; a TERM-ignoring one survives until --force.
pk kill "$web" > "$root/out" || fail 'kill failed'
! kill -0 "$web" 2>/dev/null || fail 'TERM did not kill web'
grep -q "$web.*killed" "$root/out" || fail 'kill not reported'
if pk kill "$stubborn" > "$root/out" 2>&1; then fail 'surviving process reported success'; fi
kill -0 "$stubborn" 2>/dev/null || fail 'stubborn died without force'
grep -q "$stubborn.*still alive" "$root/out" || fail 'survivor not reported'
pk kill --force "$stubborn" "$db" > "$root/out" || fail 'force kill failed'
! kill -0 "$stubborn" 2>/dev/null || fail 'force did not kill stubborn'
! kill -0 "$db" 2>/dev/null || fail 'force did not kill db'
grep -q "$stubborn.*killed (KILL)" "$root/out" || fail 'force kill not reported'

# Unknown commands print usage and fail.
if pk bogus > /dev/null 2> "$root/err"; then fail 'unknown command accepted'; fi
grep -q 'usage' "$root/err" || fail 'unknown command usage'
pk --help | grep -q 'usage' || fail 'help'
printf 'ok: list, filter, de-dup, validation, TERM, force KILL and usage\n'
