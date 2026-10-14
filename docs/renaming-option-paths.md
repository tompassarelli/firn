# Renaming option paths

Find the existing callers with `rg -n 'myConfig.modules.foo' modules hosts
native config docs`. Change the option declaration and every caller in the
same change, including composition metadata and tests. Run `firn repo build`
when metadata changed, then `firn check`. Support only the current interface;
do not retain a compatibility option for an unused path.
