# Type C: DB ↔ Application

Detection patterns and test strategy for Type C boundaries (an ORM /
application model talking to a relational or document DB).

---

## Detection (Step 1-2 Type C)

### Schema side

| Method         | Pattern                                                          |
|----------------|------------------------------------------------------------------|
| Migration      | `CREATE TABLE`, `ALTER TABLE` (SQL)                              |
| ORM definition | `#[derive(Entity)]`, `@Entity`, `models.Model`, `Schema({`       |
| SurrealQL      | `DEFINE TABLE`, `DEFINE FIELD`                                   |

### Application side

- Model struct / entity class
- Column references in queries

**Match by:** table name + column name.

---

## Test strategy (Step 2-2 Type C)

```
Strategy: round-trip (insert → select → assert)

1. Insert a model from the application layer
2. Read back from the DB
3. Assert equality with the original model
```

### Checks

- Every field maps correctly
- Type conversions (DateTime, JSON, Enum) are correct
- NULL / default-value handling
- Related-table integrity

### Run prerequisite

DB tests require a test database. Skip and report when unavailable —
do not silently pass.
