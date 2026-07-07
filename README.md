# Relational Database Design — PostgreSQL

A full database engineering project: analyzing the flaws in a flat-file data structure, designing a normalized 8-table relational schema from scratch, cleaning raw data with SQL, implementing business queries, benchmarking query optimization with and without indexing, and enforcing role-based access control.

The platform manages patient health records, allergy histories, and fitness tracker device inventories for a health monitoring service — **HealthFit**.

| ![DataSources](Figures/DataSources.png) |

> **Note on Data & Database Availability**
> The PostgreSQL database instance and underlying patient dataset have been removed from this repository for data ethics reasons — the source data contains personal and medical information. All schema diagrams, architectural figures, query scripts, and optimization results are retained for portfolio and reference purposes.

---

## The Problem — Why Flat Files Break

The original data lived in two CSV files (565 patient rows, 100,000 tracker rows). The issues were structural, not cosmetic:

| Problem | Impact |
|---|---|
| Patient name stored as one field (`"Dr. John Smith Jr."`) | Unqueryable by first/last name; prefix extraction requires unreliable regex |
| Multiple allergies in one column | Violates 1NF; one UPDATE can corrupt multiple records |
| Tracker colors as comma-separated values (`"Blue, Red, Black"`) | Violates 1NF; filtering by color requires pattern matching on dirty strings |
| No foreign key between patients and trackers | Deleting a tracker leaves orphaned patient records; no referential integrity |
| No constraints, no indexing, no roles | Every query does a full table scan; no security boundary between user types |

---

## Database Design

### 8-Table Schema in Third Normal Form (3NF)

| Table | Role |
|---|---|
| `patient` | Personal info, medical condition, medication, assigned tracker FK |
| `allergy` | Lookup table — all known allergy names |
| `pt_allergy` | M:N bridge — links patients to their allergies |
| `tracker` | Unique tracker models: model name + device type |
| `trck_spec` | Full per-SKU specifications: color, brand, price, rating, materials |
| `colors` | Lookup table — available tracker colors |
| `trck_brand` | Lookup table — tracker brands |
| `trck_material` | Lookup table — strap materials |

### Entity-Relationship Diagram

| ERD |
|---|
| ![DataStructureDesign](Figures/DataStructureDesign.jpeg) |

All tables satisfy 3NF: atomic columns, no partial dependencies, no transitive dependencies.

---

### Key Design Decisions

**Surrogate key for `trck_spec` — not a composite key**

The natural candidate key for `trck_spec` is the combination of `(brand_name, color, display, strp_material)`. Using that as a composite primary key would cascade four string values into every foreign key reference. Instead, a surrogate integer key is used, with a `UNIQUE` constraint enforced on the four-column combination to prevent duplicates. This halves the join cost on any query involving tracker specifications.

**Value-as-primary-key for lookup tables**

`colors`, `trck_brand`, and `trck_material` use the value itself (e.g., `'Blue'`, `'Fitbit'`) as the primary key rather than a numeric surrogate ID. The rationale: the value *is* the unique identifier. Using a surrogate ID would require joining through it on every query without any informational gain. The tradeoff — slightly larger foreign key storage — is negligible at this data volume.

**Check constraints instead of lookup tables for low-cardinality fixed sets**

`gender` (M/F/Other), `medical_condition` (Watch/Mild/None), `device_type` (FitnessBand/Smartwatch), and `display` (7 display types) are enforced via `CHECK` constraints rather than separate lookup tables. These values are unlikely to change frequently, and a lookup table per attribute would create unnecessary joins for no scalability benefit. New values can be added to the constraint definition when needed.

**M:N bridge for allergies**

A patient can have zero or many allergies; an allergy can apply to zero or many patients. Storing allergies in the patient row (as the original dataset did) forces either one-allergy-per-row duplication or comma-stuffed columns. The `pt_allergy` bridge table resolves this: each row is an atomic patient–allergy pairing with a composite primary key on `(pt_id, allergy_name)`.

---

## Data Cleaning

Before populating the normalized schema, the raw CSVs required significant cleaning to meet constraint requirements.

**1. Trim and capitalize string values**

```sql
UPDATE dataset1
SET brand_name = TRIM(CONCAT(
    UPPER(SUBSTRING(brand_name, 1, 1)),
    LOWER(SUBSTRING(brand_name, 2, LENGTH(brand_name)))
));
```

**2. Correct price columns — strip commas and cast to MONEY**

```sql
UPDATE dataset1
SET original_price = REPLACE(original_price, ',', '');

ALTER TABLE dataset1
ALTER COLUMN original_price TYPE MONEY USING original_price::money;
```

**3. Fuzzy string matching on color values**

Colors had 75 distinct raw entries due to misspellings (`'Bleu'`, `'Grey'`). Using the `fuzzystrmatch` extension, values were matched by Soundex similarity score and corrected:

```sql
SELECT *, CASE
    WHEN DIFFERENCE(subb.vcolor, 'BLUE') = 4 THEN 'Blue'
    WHEN DIFFERENCE(subb.vcolor, 'GRAY') = 4 THEN 'Gray'
    ELSE subb.vcolor
END AS corrected_color
FROM (
    SELECT *, CONCAT(
        UPPER(SUBSTRING(scolor, 1, 1)),
        LOWER(SUBSTRING(scolor, 2, LENGTH(scolor)))
    ) AS vcolor
    FROM (
        SELECT TRIM(unnest(string_to_array(color, ','))) AS scolor
        FROM dataset1
    ) AS subq
) AS subb;
```

The `DIFFERENCE()` function returns a Soundex similarity score from 0–4; a score of 4 means near-identical phonetic match — used here to canonicalize spelling variants.

**4. Extract prefix and split patient name**

Patient names were stored as single strings including titles and generational suffixes (`"Dr. John Smith Jr."`). Prefixes were extracted with a regex and moved to a dedicated `prefix` column before splitting into `first_name` and `last_name`.

```sql
UPDATE dataset3
SET prefix = subq.prefix
FROM (
    SELECT patient_name,
        (REGEXP_MATCHES(patient_name,
            '\sV$|\sIV$|\sIII$|\sII$|Dr\.|Mr\.|Ms\.|Mrs\.|Miss\s|Jr\.', 'g')
        )[1] AS prefix
    FROM dataset3
) AS subq
WHERE dataset3.patient_name = subq.patient_name;
```

---

## Business Queries

Four queries were implemented against the new schema and benchmarked against the original flat-table design.

### Query 1 — Emergency Allergy & Tracker Lookup

Retrieve a patient's full allergy list and their assigned tracker device type by patient ID.

```sql
SELECT p.pt_id, p.prefix, p.first_name, p.last_name,
    pa.allergy_name, t.device_type
FROM patient p
LEFT JOIN tracker t ON p.trck_model_id = t.trck_model_id
LEFT JOIN pt_allergy pa ON p.pt_id = pa.pt_id
WHERE p.pt_id = '592';
```

| Query 1 Result |
|---|
| ![query1](Figures/query1.png) |

---

### Query 2 — Insurance Promotion Eligibility

Find all patients with the prefix `Dr.`, born after 1990, allergic to Egg or Peanuts.

```sql
SELECT p.pt_id, p.prefix, p.first_name, p.last_name,
    p.dob, p.medical_condition, pa.allergy_name
FROM patient p
JOIN pt_allergy pa ON p.pt_id = pa.pt_id
WHERE pa.allergy_name IN ('Egg', 'Peanuts')
AND p.dob > '1990-01-01'
AND p.prefix = 'Dr.'
ORDER BY p.pt_id;
```

| Query 2 Result |
|---|
| ![query2](Figures/query2.png) |

---

### Query 3 — Tracker Recommendation Engine

Recommend the top 5 highest-rated trackers matching a given patient's device type, preferred color, and a price ceiling. Device type is inferred from the patient's currently assigned tracker.

```sql
SELECT tc.trck_id, t.model_name, tc.brand_name,
    t.device_type, tc.color, tc.display,
    tc.strap_material, tc.selling_price
FROM trck_spec tc
JOIN tracker t ON tc.trck_model_id = t.trck_model_id
WHERE t.device_type = (
    SELECT t.device_type FROM tracker t
    JOIN patient p ON p.trck_model_id = t.trck_model_id
    WHERE p.pt_id = '99995'
)
AND tc.color = 'Blue'
AND tc.selling_price < 20000
ORDER BY tc.rating DESC
LIMIT 5;
```

| Query 3 Result |
|---|
| ![query3](Figures/query3.png) |

---

### Query 4 — Medication Reminder Targeting

Identify male Doctor patients over 50, allergic to both Peanut and Egg, currently on medication, and not seen since 2022 — targeted for a medication review outreach.

```sql
SELECT p.pt_id, p.prefix, p.first_name, p.last_name,
    p.dob, p.gender, pa.allergy_name,
    p.medication, p.last_visit
FROM patient p
JOIN pt_allergy pa ON p.pt_id = pa.pt_id
WHERE pa.allergy_name IN ('Egg', 'Peanut')
AND p.gender = 'M'
AND p.prefix = 'Dr.'
AND p.dob < '1975-01-01'
AND p.medication = true
AND p.last_visit < '2022-01-01';
```

| Query 4 Result |
|---|
| ![query4](Figures/query4.png) |

---

## Query Optimization — Before & After Indexing

Each query was benchmarked using `EXPLAIN ANALYZE` in three configurations: normalized schema without indexes, normalized schema with targeted composite indexes, and the original flat-table design.

| Query | Schema (no index) | Schema (indexed) | Flat-table baseline |
|---|---|---|---|
| Q1 — Allergy Lookup | Sequential scan on all rows | Primary key index used on join | Sequential full-table scan |
| Q2 — Eligibility Filter | 99,997 rows scanned | Composite index on `(dob, prefix)` | Slow; redundant data + no index |
| Q3 — Tracker Recommender | 648 rows scanned | Bitmap index scan on `(color, selling_price)` | Full scan on both tables |
| Q4 — Medication Reminder | 257 rows scanned | Reduced to 73 rows with index on `(dob, last_visit, prefix)` | Slow; no join, no index |

| Before Indexing |
|---|
| ![BeforeIndexing](Figures/BeforeIndexing.png) | 

| After Indexing |
|---|
| ![AfterIndexing](Figures/AfterIndexing.png) |

| Flat Table Baseline |
|---|
| ![FlatTableBaseline](Figures/FlatTableBaseline.png) |

---

## Security — Role-Based Access Control

Three roles were defined using PostgreSQL's RBAC system, following the **Least Privilege Principle** — each role accesses only what its function requires.

| Role | Permissions |
|---|---|
| `admin` | Full access (`ALL ON ALL`) — restricted to the superuser account holder |
| `doctor` | `SELECT` on all tables; `INSERT` and `UPDATE` on `patient`, `allergy`, `pt_allergy` |
| `technician` | `SELECT`, `INSERT`, `UPDATE` on `tracker`, `trck_spec`, `colors`, `trck_brand`, `trck_material` |

Role access was tested via `SET ROLE` before executing queries on sensitive tables to verify grant boundaries are enforced.

---

## Project Structure

```
project/
├── Figures/                  # ERD, query results, optimization benchmarks
├── Task1Queries.sql          # All 4 business queries + data cleaning scripts
├── README.md
```

---

## Tech Stack

`PostgreSQL` · `SQL` · `fuzzystrmatch` extension · `EXPLAIN ANALYZE`
