#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 OpenParsec/NetworkHandler.swift OpenParsec/SAMLAuthClient.swift Tests/main.swift -o "$build_dir/saml-tests"
"$build_dir/saml-tests"
