#!/usr/bin/env bats
# infrastructure/ on the manifest: start_docker.sh sizes the Colima VM from
# services.colima.resources, compose_helpers.sh finds the Immich folder from any
# working folder, and compose_wrapper.sh works without a .env under bash 3.2.
# Stub colima and docker record their arguments; HOME is a temporary folder, so
# the real Colima VM and its profile are never touched.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS" "$BATS_TEST_TMPDIR/home"
    unset $(compgen -v | grep '^HOMELAB_' || true)
    export HOME="$BATS_TEST_TMPDIR/home" CALLS="$BATS_TEST_TMPDIR/calls" FAKE_VM=0
    : >"$CALLS"
    printf '#!/usr/bin/env bash\necho "colima $*" >> "$CALLS"\n[[ "$1" == status ]] && { [[ "$FAKE_VM" == 1 ]] && echo "disk: 60GiB" && exit 0; exit 1; }\nexit 0\n' >"$STUBS/colima"
    printf '#!/usr/bin/env bash\necho "docker $* (in $PWD)" >> "$CALLS"\nexit 0\n' >"$STUBS/docker"
    chmod +x "$STUBS/colima" "$STUBS/docker"
    export PATH="$STUBS:$PATH"
    [ "$(command -v colima)" = "$STUBS/colima" ] && [ "$(command -v docker)" = "$STUBS/docker" ]
}

@test "start_docker: a new VM gets the manifest's size" {
    run bash "$ROOT/scripts/infrastructure/start_docker.sh"
    [ "$status" -eq 0 ]
    grep -q "colima start --cpu 4 --memory 6 --disk 60 --arch" "$CALLS"
}

@test "start_docker: COLIMA_MEM still overrides the manifest" {
    COLIMA_MEM=8 run bash "$ROOT/scripts/infrastructure/start_docker.sh"
    grep -q "colima start --cpu 4 --memory 8 --disk 60" "$CALLS"
}

@test "start_docker: an existing VM is started as it is, not resized" {
    FAKE_VM=1 run bash "$ROOT/scripts/infrastructure/start_docker.sh"
    [ "$status" -eq 0 ]
    grep -qx "colima start" "$CALLS"
    ! grep -q -- "--memory" "$CALLS" || false
}

@test "compose_helpers: compose runs in the manifest's Immich folder from any working folder" {
    run bash -c 'cd / && source "$1" && compose ps' _ "$ROOT/scripts/infrastructure/lib/compose_helpers.sh"
    [ "$status" -eq 0 ]
    grep -q "docker compose -p immich .*ps (in $ROOT/services/immich)" "$CALLS"
}

@test "compose_wrapper: no .env in the service folder is fine under bash 3.2" {
    mkdir -p "$BATS_TEST_TMPDIR/svc"
    printf 'services: {}\n' >"$BATS_TEST_TMPDIR/svc/docker-compose.yml"
    run /bin/bash "$ROOT/scripts/infrastructure/compose_wrapper.sh" "$BATS_TEST_TMPDIR/svc" ps
    [ "$status" -eq 0 ]
    [[ "$output" != *"unbound variable"* ]] || false
    grep -q "docker compose -p svc ps" "$CALLS"
}

@test "configure_https lists the tailnet URLs from the mappings file, not its own ports" {
    ! grep -nE 'echo .*https://\$TAILSCALE_HOSTNAME:[0-9]+' "$ROOT/scripts/infrastructure/configure_https.sh" || false
    grep -q 'config/tailscale_serve.txt' "$ROOT/scripts/infrastructure/configure_https.sh"
}
