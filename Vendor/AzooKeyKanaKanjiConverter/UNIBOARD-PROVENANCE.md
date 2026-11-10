# Modified dependency provenance — approved1217

## Origin and inventory

- Upstream: <https://github.com/azooKey/AzooKeyKanaKanjiConverter>
- Revision: `80b8204f1cdfb364bb2ed355cf52c7ebb2519a0c` (v0.11.2).
- Input: the supplied exact export at
  `.airbuild/worktree/tokenizer-pinned-source`, **not** the newer
  japanese-validation/engine working tree. Its supplied
  `UNIBOARD_UPSTREAM_REVISION` marker is retained.
- Local package: `Vendor/AzooKeyKanaKanjiConverter`; its directory basename
  gives SwiftPM identity `azookeykanakanjiconverter`, matching the former
  remote package identity.
- All 184 exported files (4,007,554 original bytes) are retained. Exactly
  five files differ; the other 179 files are byte-identical to the export.
  No upstream source, resources, tests, documentation or notices were stripped.
- `upstream.sha256`: complete input inventory, SHA-256 per file, paths relative
  to the export/package root.
- `vendored.sha256`: complete patched inventory of those 184 exported files in
  the same format. The added local `UNIBOARD-PROVENANCE.md` record is not an
  upstream file and is excluded from this inventory.
- `approved1217.patch`: complete five-file unified patch, with `a/` and `b/`
  paths relative to the package root (apply with `patch -p1`).

SHA-256 of these provenance records:

| Record | SHA-256 |
| --- | --- |
| `upstream.sha256` | `7ceb5810d6c00e1b9ea567abfab78ea7c9f745206e411e391d8906e35ee9650b` |
| `vendored.sha256` | `c015e94a9d2a73c0c62c5f4ac1710d0fffcb0e3694afcfc04a831656312ecac2` |
| `approved1217.patch` | `8194dffa22a7051aebda6b13d2bea5035dbf8c37679fecd8d1c8779a01b5a81a` |

For example, from the package root, verify all retained files using
`sha256sum -c ../AzooKeyKanaKanjiConverter.provenance/vendored.sha256`
(or the equivalent SHA-256 verifier on the host).

## Local modification

This is a **modified dependency**, not an unmodified upstream release.
The approved1217 change is a source/build-graph exclusion for production's
explicit empty trait set, not a runtime tokenizer substitution:

1. `Package.swift`: make only the converter target's `EfficientNGram` edge
   conditional on `.when(traits: ["Zenzai", "ZenzaiCPU"])`.
2. `Sources/KanaKanjiConverterModule/ConverterAPI/KanaKanjiConverter.swift`:
   guard the EfficientNGram import; define module-internal
   `ZenzaiPersonalization` as the exact original labeled tuple when either
   neural trait is enabled, otherwise `Never`; use its optional for the stored
   property and helper return; guard only the helper body with `return nil`
   in the empty-trait case.
3. `Sources/KanaKanjiConverterModule/ConversionAlgorithms/Zenzai/zenzai.swift`:
   guard the EfficientNGram import and use the optional alias in `all_zenzai`.
4. `Sources/KanaKanjiConverterModule/ConversionAlgorithms/Zenzai/Zenz/Zenz.swift`:
   guard the import and use the optional alias in `candidateEvaluate`.
5. `Sources/KanaKanjiConverterModule/ConversionAlgorithms/Zenzai/Zenz/ZenzContext.swift`:
   guard the import, use the optional alias in `evaluate_candidate`, and guard
   the personalization-rescoring branch. The empty-trait branch executes an
   exact copy of the original non-personalized scoring loop.

`PrefixConstraint` remains available to the ordinary converter. No dictionary,
core conversion, neural math, tokenizer implementation, public options, or
Uniboard runtime behavior/configuration code was otherwise changed.
`EfficientNGram` retains its original sources, dependencies and
`.copy("tokenizer")` resource rule for enabled neural traits. There are no
missing-resource stubs or finished-artifact stripping steps.

## Production project and dependency resolution

`project.yml` now points to the local package and keeps `traits: []`, disabling
both defaults and the Zenzai/ZenzaiCPU traits. The existing
`Uniboard.xcodeproj/project.pbxproj` consistently uses an
`XCLocalSwiftPackageReference` with `relativePath = Vendor/AzooKeyKanaKanjiConverter`
and an explicit empty `traits` list. The existing reference/product UUIDs and
`KanaKanjiConverterModule` keyboard dependency are retained. No regeneration of
unrelated project content was performed.

No tracked or workspace `Package.resolved` existed at implementation time.
The existing resolution supplied in
`.airbuild/worktree/japanese-smoke/final-run/results/Package.resolved` was used
as the pin source for
`Uniboard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
Only the former remote root-package pin was removed, since it is now local.
All five transitive identity/location/version/revision entries are unchanged:

| Identity | Version | Revision |
| --- | --- | --- |
| `jinja` | 1.1.2 | `31c4dd39bcdc07eaa42a384bdc88ea599022b800` |
| `swift-algorithms` | 1.2.1 | `87e50f483c54e6efd60e885f7f5aa946cee68023` |
| `swift-collections` | 1.7.5 | `f96b909e1a9e469620bc5037c1e24e00153f376f` |
| `swift-numerics` | 1.1.1 | `0c0290ff6b24942dadb83a929ffaaa1481df04a2` |
| `swift-tokenizers` | 0.0.1 | `4a606f66e0cc4d7d9f0197649e812f7fc86a4c34` |

The lockfile uses supported schema version 2 rather than retaining the old
schema-3 `originHash` for the replaced remote graph. No dependency resolver,
network fetch, update or build was run to generate new pins. Resolution of
packages and reachability of compiled targets are distinct: keeping the
existing swift-tokenizers pin does not add a production target dependency.
The upstream manifest's other declarations (including optional/CLI dependencies)
are unchanged; dependencies not present in the supplied empty-trait lockfile
have not been newly selected or pinned.

## Retained notices and limitations

The upstream MIT `LICENSE` and existing copyright headers are retained verbatim.
The tokenizer's original `Sources/EfficientNGram/tokenizer/README.md` is retained
verbatim, including its attribution to
<https://huggingface.co/ku-nlp/gpt2-small-japanese-char> and CC BY-SA 4.0 statement.
All six accompanying tokenizer data/config files remain intact. Their retention
in source does not mean they are intended to be shipped by the empty-trait
production graph. This provenance record does not replace any upstream notice
or grant a new license.

The supplied export has unpopulated dictionary and emoji submodule directories;
`.gitmodules` and their upstream URLs are retained. No submodule contents were
invented or downloaded. Production uses `KanaKanjiConverterModule`, not the
upstream `WithDefaultDictionary` product; Uniboard's separately managed language
pack resources were not modified.

Implementation verification was limited to byte inventories, exact five-file
diff review, and project-edit whitespace checks. No build, runtime test, full
regression, package resolution, or finished-artifact inspection was run here.
The parent validation must check Xcode/XcodeGen local trait handling, locked
resolution, production target/resource exclusion, and ordinary dictionary
conversion. **Neural-enabled compatibility has not been tested and is not
claimed.** Existing app notices UI and all unrelated dirty-tree work are outside
this change.
