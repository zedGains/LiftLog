# Translations

`master_list.json` is every English string the app shows (numbers written as `{0}`, names as `{x}`).
Each `<lang>*.tsv` file has one line per string: `index<TAB>translation`.
After editing a .tsv, run from the repo root: `python3 i18n/src/merge.py es fr pt-BR vi zh ja ko ar`
That rebuilds `i18n/<lang>.json`, which the app loads. Exercise names stay in English.
