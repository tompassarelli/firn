# Renaming option paths

To rename an option path across all `.gal` sources (for example
`myConfig.modules.foo` to `myConfig.modules.bar`):

```bash
galileo refs myConfig.modules.foo                                   # preview the users
galileo rename option myConfig.modules.foo myConfig.modules.bar     # apply
firn repo build && firn repo validate                               # regenerate and verify
```
