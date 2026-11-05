#!/usr/bin/env bash
# Export every WoWSims Forever rotation and build as JSON (for SimData_Forever.lua).
#   tools/forever_export.sh <wowsims/forever checkout> <out dir>
# .apl.json / .build.json files are copied; .siml files are read with the
# WoWSims CLI (wowsimcli siml parse -json), which needs Go 1.25.
set -euo pipefail
SRC=$(cd "$1" && pwd)
OUT=$(mkdir -p "$2" && cd "$2" && pwd)
CLI="${WOWSIMCLI:-$OUT/../wowsimcli}"
if [ ! -x "$CLI" ]; then
	# needs protoc and protoc-gen-go on the PATH (see .github/workflows)
	(cd "$SRC" && protoc -I=./proto \
		--go_opt=Mgoogle/protobuf/descriptor.proto=google.golang.org/protobuf/types/descriptorpb \
		--go_out=./sim/core ./proto/*.proto && go build --tags=with_db -o "$CLI" ./cmd/wowsimcli)
fi
rm -rf "$OUT"/*
cd "$SRC/ui/specs"
find . \( -path '*/apls/*' -o -path '*/builds/*' \) \( -name '*.json' -o -name '*.siml' \) | sort | while read -r f; do
	rel=${f#./}
	dest="$OUT/${rel%.siml}"
	case "$rel" in *.siml) dest="$dest.json" ;; *) dest="$OUT/$rel" ;; esac
	mkdir -p "$(dirname "$dest")"
	case "$rel" in
	*.siml) "$CLI" siml parse -json "$f" > "$dest" || { echo "FAILED $rel" >&2; rm -f "$dest"; } ;;
	*) cp "$f" "$dest" ;;
	esac
done
echo "exported $(find "$OUT" -name '*.json' | wc -l) files"
