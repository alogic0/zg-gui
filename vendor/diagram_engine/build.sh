#!/bin/sh
set -eu

mermaid_zig_version="0.17.0"
mermaid_zig_exe="${ZIG_EXE:-${HOME}/.zig/${mermaid_zig_version}/files/zig}"

if [ ! -x "${mermaid_zig_exe}" ]; then
    if [ -n "${ZIG_EXE:-}" ]; then
        echo "configured Zig compiler not found: ${mermaid_zig_exe}" >&2
        exit 1
    fi
    mermaid_path_zig="$(command -v zig || true)"
    if [ -n "${mermaid_path_zig}" ] && [ -x "${mermaid_path_zig}" ]; then
        mermaid_zig_exe="${mermaid_path_zig}"
    else
        echo "required Zig compiler not found: ${mermaid_zig_exe}" >&2
        exit 1
    fi
fi

mermaid_actual_zig_version="$("${mermaid_zig_exe}" version)"
if [ "${mermaid_actual_zig_version}" != "${mermaid_zig_version}" ]; then
    echo "required Zig version ${mermaid_zig_version}, found ${mermaid_actual_zig_version} at ${mermaid_zig_exe}" >&2
    exit 1
fi

if [ "$#" -ge 1 ]; then
    case "$1" in
        version)
            shift
            exec "${mermaid_zig_exe}" run tools/package_version.zig -- "$@"
            ;;
        update-font-metrics)
            shift
            exec "${mermaid_zig_exe}" run tools/gen_diagram_font_metrics.zig -- "$@"
            ;;
    esac
fi

exec "${mermaid_zig_exe}" build "$@"
