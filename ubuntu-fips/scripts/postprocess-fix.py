import sys

p = sys.argv[1]
exceptions = [
    "package_chrony_installed",
    "package_timesyncd_removed",
    "chronyd_or_ntpd_set_maxpoll",
    "chronyd_sync_clock",
]
lines = open(p).read().splitlines()
out = []
i = 0
while i < len(lines):
    line = lines[i]
    if "BEGIN fix" in line and any(r in line for r in exceptions):
        out.append(line)  # keep the BEGIN comment
        i += 1
        while i < len(lines):
            l = lines[i]
            if "END fix" in l:
                out.append("# " + l)
                i += 1
                break
            out.append("# " + l if l.strip() else l)
            i += 1
        continue
    s = line.strip()
    if s.startswith("if ") and "'auditd'" in line and "'linux-base'" in line:
        out.append("if dpkg-query --show --showformat='${db:Status-Status}' 'auditd' 2>/dev/null | grep -q '^installed$'; then")
    else:
        out.append(line)
    i += 1

open(p, "w").write("\n".join(out) + "\n")
print("post-processed", p)
