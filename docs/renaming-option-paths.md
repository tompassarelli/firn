# Renaming option paths

To rename an option path across all `.bnix` files (e.g., refactoring `myConfig.modules.foo` → `myConfig.modules.bar`):

```bash
beagle-rename --dry-run myConfig.modules.foo myConfig.modules.bar   # preview
beagle-rename myConfig.modules.foo myConfig.modules.bar             # apply
firn validate                                                        # verify clean
```

Word-boundary matching prevents partial collisions; string literals are skipped. After applying, always re-run `firn validate`.
