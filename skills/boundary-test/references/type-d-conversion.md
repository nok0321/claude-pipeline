# Type D: Conversion boundaries

Detection patterns and test strategy for Type D boundaries (coordinate
ordering, unit conversion, encoding/decoding, format conversion — any
function that maps between two representations of the same value).

---

## Detection (Step 1-2 Type D)

Pull conversion rules from CLAUDE.md `## Critical Constraints`.

### Detection procedure

1. Grep for conversion functions (`to_`, `from_`, `convert_`, `transform_`).
2. Pinpoint conversion functions between the type pairs the constraint
   mentions.
3. Identify round-trippable conversion pairs.

### Example (data-format conversion)

```
Constraint: <FormatA>=[<field1>,<field2>], <FormatB>=[<field2>,<field1>]
Detected:   to_<format_b>(), from_<format_b>()
Test:       value → to_<format_b> → from_<format_b> → assert_eq(value)
```

---

## Test strategy (Step 2-2 Type D)

```
Strategy: round-trip (value → forward → reverse → equal)

1. Prepare test values (typical + edge cases)
2. Apply forward conversion
3. Apply reverse conversion
4. Assert equality with the original
```

### Test values

- Typical values
- Boundary values (0, max, min, negative)
- Edge cases (NaN, Infinity, empty, polar singularities)

### Checks

- Round-trip equality (epsilon tolerance allowed)
- Intermediate range check (output within expected bounds)

### Failure example

```
[FAIL] boundary_convert::test_<value>_roundtrip_<edge_case>
  Input:    <Value> { <field1>: NaN, <field2>: 0.0 }
  Expected: round-trip equality or explicit error
  Actual:   panic at <path/to/convert>:<N>
  Boundary: [D-1] <DataType> format conversion
```
