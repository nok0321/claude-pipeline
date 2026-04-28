# Type A: REST API ↔ Frontend

Detection patterns and test strategy for Type A boundaries (an API
provider serving JSON to a frontend consumer).

---

## Detection (Step 1-2 Type A)

### Provider side (API)

| Language / FW    | Pattern                                                          |
|------------------|------------------------------------------------------------------|
| Rust (Axum)      | `async fn` + handler types (`Json<T>`, `Path<T>`, `State<T>`)    |
| Rust (Actix)     | `#[get]`, `#[post]` + handler functions                          |
| Node (Express)   | `router.get`, `router.post` + response type                      |
| Python (FastAPI) | `@app.get`, `@app.post` + Pydantic models                        |
| Java (Spring)    | `@GetMapping`, `@PostMapping` + DTO classes                      |
| Go (gin / echo)  | `r.GET`, `r.POST` + response struct                              |

### Consumer side (frontend)

| Pattern          | Targets                                                                |
|------------------|------------------------------------------------------------------------|
| fetch / axios    | `fetch("`, `axios.get(`, `axios.post(` + URL pattern                   |
| Type definitions | response interface / type definitions                                  |
| API client       | generated clients (e.g. openapi-generator)                             |

**Match by:** URL path + HTTP method.

---

## Test strategy (Step 2-2 Type A)

```
Strategy: validate response JSON shape

1. Send a request to the API endpoint
2. Verify the JSON shape (field names + types)
3. Compare against the FE type definition
```

### Checks

- Response field names match FE definition
- Field types (string / number / boolean / array / object) match
- Required vs optional fields match
- Nested object shapes match
- Array element types match

### Failure example

```
[FAIL] boundary_api::test_get_<resource>_response_shape
  Expected: { items: <Item>[] } (<path/to/client>:<N>)
  Actual:   Vec<<Item>> (bare array, no wrap)
  Boundary: [A-2] GET /<api_path>
  Fix: wrap the API response as { items: [...] } or change the FE type to a bare array
```
