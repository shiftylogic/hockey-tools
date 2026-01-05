#!/usr/bin/env bash
#
# Copyright (c) 2025-present Robert Anderson.
# SPDX-License-Identifier: MIT
#

#
# CONSTANTS
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/tagger.lua"


#
# Argument processing
#
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            TAG_CONFIG="$2"
            shift 2
            ;;
        --video)
            TAG_VIDEO="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "${TAG_CONFIG}" ]]; then
    echo "Error: --config is required" >&2
    exit 1
fi

if [[ -z "${TAG_VIDEO}" ]]; then
    echo "Error: --video is required" >&2
    exit 1
fi

if [[ ! -f "${TAG_CONFIG}" ]]; then
    echo "Error: Config file not found: $config" >&2
    exit 1
fi

if [[ ! -f "${TAG_VIDEO}" ]]; then
    echo "Error: Video file not found: $video" >&2
    exit 1
fi


CONFIG_FILE=$(cd "$(dirname "${TAG_CONFIG}")" && pwd -P)/$(basename "${TAG_CONFIG}")
echo "Config: ${CONFIG_FILE}"


TAGGER_CONF=${CONFIG_FILE} mpv      \
    --scripts="${SCRIPT_PATH}"      \
    "${TAG_VIDEO}"

