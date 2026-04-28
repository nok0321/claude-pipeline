# Type B: WASM ↔ TypeScript

Detection patterns and test strategy for Type B boundaries (a WASM
module providing functions/types to a TypeScript consumer).

---

## Detection (Step 1-2 Type B)

### Provider side (WASM)

| Language | Pattern                                |
|----------|----------------------------------------|
| Rust     | `#[wasm_bindgen]` + `pub fn` / `pub struct` |
| Go       | `//export` directive                   |
| C / C++  | `EMSCRIPTEN_KEEPALIVE`                 |

### Consumer side (TypeScript)

- WASM import: `import { ... } from '*.wasm'` / `init()` pattern
- Types: matching `.d.ts`

**Match by:** export name.

---

## Test strategy (Step 2-2 Type B)

```
Strategy: typed input / output shape

1. Call the WASM function directly
2. Verify input type conversion
3. Verify output type matches the TS expectation
```

### Checks

- JS → WASM argument conversion is correct
- WASM → JS return-value conversion is correct
- Errors propagate correctly

### Run prerequisite

WASM tests need a built WASM artifact; build it before running the
boundary test suite if missing.
