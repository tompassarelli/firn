# Query the compiler instead of grep

Ask `galileo` for mechanical facts about `.gal` sources:

```bash
galileo check [PATH...]                 # parse and type errors with file:line
galileo refs OPTION [PATH...]           # every source that sets or reads an option path
galileo query [PATH...] QUESTION --json # facts, e.g. 'all ?m where ?m is a Module'
galileo why S [PATH...]                 # the proof of a sentence
galileo help [syntax]                   # commands and the language card
```

A `.gal` file exports every declaration not marked `private`. `galileo lsp`
serves `.gal` in the editor; there is no daemon to start.
