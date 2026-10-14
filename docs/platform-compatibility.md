# Platform compatibility

`config/platforms.json` declares which platforms allow every module.
Module `metadata.json` `supports` lists additional supported platforms.
Host `tags.json` selects its platform. Tag resolution rejects enabling an
unsupported module.

```bash
firn platform list all
firn platform list darwin
firn platform list linux
firn platform show <module>
firn platform safelist
```

Metadata states support intent. Evaluate and build the selected host on its
platform to verify the configuration and packages.
