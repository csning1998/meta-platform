#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

readonly cli="platform"

go test -C tools/"${cli}" -race -count=1 -coverprofile=coverage.out ./...

go build -C tools/"${cli}" -o ../../"${cli}" ./cmd/"${cli}"

echo "built: $(pwd)/${cli}"
