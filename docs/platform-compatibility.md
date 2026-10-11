# Discovering platform compatibility

Platform support is stated as Galileo facts in `config/tags.gal`:

```
linux is a Platform
linux allows every module
darwin is a Platform
atuin supports darwin
```

A module runs on a platform that allows every module or that it supports
(firn/tags' rules `supported-everywhere` and `supported-by-platform`). Each
module is `both`, `linux-only`, `darwin-only` or `neither`.

```bash
firn platform list all          # full matrix
firn platform list darwin       # modules that run on darwin
firn platform list linux        # modules that run on linux only
firn platform show <name>       # one module's verdict and the platforms it lacks
firn platform safelist          # the support facts as Galileo
```

The commands read the facts through `galileo query --json` in the checkout
root, so they agree with `galileo query 'all ?m where ?m supports darwin'`.

`firn platform safelist` prints one line per platform that does not allow
every module, with the module names sorted:

```
[atuin, bash, …] supports darwin
```

Those lines can replace the `X supports darwin` facts in `config/tags.gal`.

**Limitation**: the facts state intent, not a build. A module that supports
darwin may still fail there; build it on a darwin host to verify.
