# TODO: Future Enhancements

## Text Normalization Improvements for Duplicate Detection

### High Priority (Recommended for Implementation)

1. **Unicode Normalization**
   - Apply `.precomposedStringWithCanonicalMapping` to standardize Unicode representation
   - Handles accented characters (é vs e + combining accent)
   - Important for international documents
   ```swift
   let normalized = text.precomposedStringWithCanonicalMapping
   ```

2. **Case Folding**
   - Apply `.folding(options: .caseInsensitive, locale: nil)` for case normalization
   - More comprehensive than `.lowercased()` for international text
   - Handles Turkish i/İ, German ß, etc.
   ```swift
   let normalized = text.folding(options: .caseInsensitive, locale: nil)
   ```

3. **Diacritic Stripping**
   - Apply `.folding(options: .diacriticInsensitive, locale: nil)` to remove accents
   - Treats "résumé" and "resume" as identical
   - Useful for matching documents with inconsistent accent usage
   ```swift
   let normalized = text.folding(options: .diacriticInsensitive, locale: nil)
   ```

### Medium Priority (Consider for Next Release)

4. **Punctuation Removal**
   - Remove or normalize punctuation marks
   - Handles different quote styles (" vs " vs „ vs «)
   - Removes hyphens, em-dashes, en-dashes variations
   ```swift
   let normalized = text.replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
   ```

5. **Ligature Expansion**
   - Expand ligatures (ﬁ → fi, ﬂ → fl, ﬀ → ff)
   - Important for PDFs with fancy typography
   - May be handled automatically by Unicode normalization
   ```swift
   let ligatureMap = ["ﬁ": "fi", "ﬂ": "fl", "ﬀ": "ff", "ﬃ": "ffi", "ﬄ": "ffl"]
   var normalized = text
   for (ligature, expanded) in ligatureMap {
       normalized = normalized.replacingOccurrences(of: ligature, with: expanded)
   }
   ```

### Low Priority (Experimental/Advanced)

6. **Number Normalization**
   - Replace all numbers with a placeholder token
   - Useful if documents differ only in dates, page numbers, etc.
   - May cause false positives, use cautiously
   ```swift
   let normalized = text.replacingOccurrences(of: #"\d+"#, with: "[NUM]", options: .regularExpression)
   ```

7. **Citation/Reference Removal**
   - Remove bracketed citations [1], [Smith et al.], etc.
   - Remove parenthetical citations (Smith, 2020)
   - Useful for academic papers where only citation style differs
   ```swift
   let normalized = text
       .replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)
       .replacingOccurrences(of: #"\([A-Za-z\s,]+\d{4}\)"#, with: "", options: .regularExpression)
   ```

8. **LaTeX/Math Symbol Removal**
   - Remove or normalize LaTeX commands (\alpha, \beta, etc.)
   - Convert common math symbols to text equivalents
   - Only needed if comparing LaTeX source vs rendered PDFs

### Recommended Unified Implementation

Create a single `normalizeText()` helper function combining all high-priority normalizations:

```swift
private func normalizeText(_ text: String) -> String {
    return text
        .precomposedStringWithCanonicalMapping                              // Unicode normalization
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)  // Case + diacritics
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)  // Whitespace (current)
        .trimmingCharacters(in: .whitespacesAndNewlines)                    // Trim edges
}
```

This unified approach would replace the current normalization in both RAG and Content Fingerprint methods.

### Testing Recommendations

- Test with PDF pairs that differ only in:
  - Compression settings
  - OCR quality
  - Font embedding
  - Unicode encoding
  - Accent usage (café vs cafe)
  - Case variations
  - Ligature usage
- Monitor false positive rate to ensure normalization isn't too aggressive
- Consider making normalization level configurable (Conservative/Moderate/Aggressive)

---

## Other Future Enhancements

### Smart Library
- [ ] Add duplicate resolution UI (choose which version to keep)
- [ ] Show preview comparison for duplicates side-by-side
- [ ] Add duplicate detection progress indicator
- [ ] Cache RAG embeddings to speed up repeated scans

### Performance
- [ ] Parallel processing for RAG comparisons
- [ ] Incremental duplicate detection (only scan new PDFs)
- [ ] Persist duplicate detection results to avoid re-scanning

### Features
- [ ] Export duplicate detection report as CSV/JSON
- [ ] Configurable similarity thresholds per method
- [ ] Whitelist/blacklist for files to exclude from duplicate detection
