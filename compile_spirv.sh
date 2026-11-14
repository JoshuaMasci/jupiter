#!/usr/bin/env bash
mkdir -p ./cache/shaders/slang/
for filepath in ./assets/shaders/slang/*.slang; do
    filename="${filepath##*/}"
    name="${filename%.*}"
    slangc -target spirv -profile spirv_1_3 -fvk-use-entrypoint-name -o "./cache/shaders/slang/${name}.spv" "$filepath"
done
