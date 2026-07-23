# Code, in the brand's palette

Code with real syntax color, tuned separately for Paper and Ink. Hover any
block for a copy button.

```swift
struct Galley {
    let role = "reader"

    /// A reader never mutates the manuscript.
    func open(_ file: URL) -> Page {
        Page(typeset: file, cursor: nil)
    }
}
```

Two languages, one palette. The same spectral family carries strings,
numbers, and keywords in every theme.

```python
def reading_time(words: int, wpm: int = 225) -> int:
    """Minutes, rounded up, never zero."""
    return max(1, round(words / wpm))
```
