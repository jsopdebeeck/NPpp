# Welcome to NPpp

A **minimalist** text & Markdown editor for macOS, *inspired by* Notepad++.

> [!TIP] Three views
> Press ⌘1 for text, ⌘2 for side by side, ⌘3 for the formatted preview.

## Features

- [x] Tabs restored on relaunch — even ==unsaved== changes
- [x] Find & replace with regex, `\1` back-references
- [x] Line endings: LF / CRLF / CR conversion
- [ ] Your next idea

| Shortcut | Action          |
|:---------|:----------------|
| ⌘F       | Find            |
| ⌥⌘F      | Find & replace  |
| ⇧⌘J      | Unwrap paragraphs |

## Syntax highlighting

```bash
for f in *.md; do
  echo "Converting $f"  # loop over files
done
```

```python
def greet(name: str = "world") -> str:
    return f"Hello, {name}!"
```
