# Tag composition

See [TAGS.md](TAGS.md) for source metadata and resolution semantics.

```bash
firn tag list all
firn tag show <module>
firn tag filter <tag>
firn tag resolve <host>
firn tag index stdout
```

The CLI reads module `metadata.json` and host `tags.json`. After changing
composition, run `firn repo build` and `firn check` before committing.
