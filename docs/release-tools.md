# Release translator identity

The shipped translator contains no personal source-machine paths or debug symbols. `dmsh_xlate.csproj` disables Release debug symbols and the translator's source-revision suffix. Keep all required license notices when rebuilding its vendored dependencies.

## Rebuild

Use the supported .NET 10 SDK and a scratch directory outside the repository. For example:

```sh
dotnet publish dm/gfx/tools/dmsh_xlate/dmsh_xlate.csproj \
  -c Release --self-contained false -p:UseAppHost=false \
  -p:IncludeSourceRevisionInInformationalVersion=false \
  -p:EnableSourceControlManagerQueries=false \
  --artifacts-path /tmp/horizonnative-xlate-artifacts \
  -o /tmp/horizonnative-xlate-publish
```

The existing universal `dmsh_xlate` apphost is kept. Replace only `dmsh_xlate.dll`, `Ryujinx.Graphics.Shader.dll` and `Ryujinx.Common.dll` with the rebuilt versions when the dependency graph is unchanged. Do not distribute a stale `dmsh_xlate.pdb`. Dependency updates require reviewing the full publish output and dependency manifest together.

Update `dm/gfx/tools/dmsh_chain.lock` with `tool_lock.py --update-lock`, regenerate `dm/gfx/nvn/dmsh_chain.h` with `dmsh_chain.py --header`, and run `tool_lock.py --check-tools`. Compare synthetic shader output with the prior translator and run the affected compiler tests before publishing.

Every changed chain requires rebuilding the affected game's shader libraries and the host together. An artifact cleanup is not permission to keep using an old cache under a new chain identifier. See [AGENTS.md](../AGENTS.md) and the [validation record](validation.md).

## Synthetic compiler and GPU checks

```sh
make -C dm/gfx/tests GAME=010015100B514000 -j2 t_geometry t_geometry_primitive_id
DMSH_TEST_XLATE="$PWD/dm/gfx/tools/dmsh_xlate_bin/dmsh_xlate" \
DM_TEST_GEOMETRY="$PWD/dm/gfx/tests/t_geometry" \
DM_TEST_GEOMETRY_PRIMITIVE_ID="$PWD/dm/gfx/tests/t_geometry_primitive_id" \
DMSH_TEST_METAL=1 DMSH_TEST_GPU=1 DMSH_TEST_METAL_SDKS=macosx,iphoneos \
python3 -m unittest -q dm/tools/tests/test_image_atomic_bounds.py dm/gfx/tests/test_dmsh_geometry.py
```
