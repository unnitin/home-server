# Recorded command output for TEST_MODE

Under `TEST_MODE=1`, `homelab/exec.py` runs nothing: each call returns the file
here named after its argv (`homelab.exec.fixture_key`), and a call with no file
is an error that names the file it looked for.

- `<key>.out`: the stdout of a call that exited 0.
- `<key>.json`: `{"rc": …, "stdout": …, "stderr": …, "timed_out": false}`.

`diskutil appleRAID list -plist` is `diskutil_appleRAID_list_-plist.out`. A
path inside the repo is written relative to it.

Record from the real mini only commands `exec.py` allows (all read-only), and
replace anything that identifies the machine or the tailnet: hostnames with
`mini.example.ts.net`, tailnet IPs with `100.64.0.x`, disk serials with
`SERIAL-n`. Tests can add their own folder with `HOMELAB_EXEC_FIXTURES`.
