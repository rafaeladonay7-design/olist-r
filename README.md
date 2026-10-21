# Data Quality and Integrity Validation with R

**English** · [Español](README.es.md)

**Case study with public data** · R · Rafael Adonay Rocha Gutiérrez

## Scenario

Simulated role: data support for the operations team of a marketplace. Internal users report issues in the dashboards: missing information, delivery times that make no sense and sales that don't show up under any category. Before touching the dashboard, I validate the database at its source to answer:

1. How reliable is the data feeding the dashboards?
2. Which records have problems, and what kind?
3. How much do the KPIs change if they are not fixed?

## Data

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle): 8 related tables with **550,759 records** (99,441 orders from 2016 to 2018, items, payments, reviews, customers, products, sellers and category translation).

Tools: R 4.6 (base R only, no packages).

## Method: 32 data quality rules in 7 categories

| Category | What it checks | Example rule |
|---|---|---|
| Completeness | Missing data where it shouldn't be | Product without a category |
| Uniqueness | Duplicate keys | Duplicate `order_id` |
| Integrity | Records pointing to something that doesn't exist | Item with a non-existent product |
| Dates | Dates out of order | Delivered to the customer before leaving with the carrier |
| Status | Status that doesn't match the dates | `delivered` status without a delivery date |
| Ranges | Impossible values | Zero payment, review score outside 1–5 |
| Reconciliation | Totals that don't match | Amount paid ≠ price + freight |

Each rule records the IDs that fail, so they can be fixed one by one.

## Key findings

**17 of the 32 rules pass:** there are no duplicate keys, every relationship between tables is valid and every review score is between 1 and 5. **15 rules find problems:**

![Records with problems by rule](figuras/problemas_por_regla.png)

| # | Problem | Records | What happens in a dashboard |
|---|---|---|---|
| 1 | The same `review_id` appears in 2 or more orders | 1,603 rows | Counting reviews by ID gives 98,410 instead of 99,224 |
| 2 | Product without a category | 610 products | **R$179,535 in sales (1.32%)** show up as "blank" in sales by category |
| 3 | Amount paid doesn't match price + freight (difference above R$1) | 249 orders | Revenue differs depending on the table the dashboard uses |
| 4 | Handed to the carrier **before** the purchase | 166 orders | Date errors: negative preparation times |
| 5 | Delivered to the customer **before** leaving with the carrier | 23 orders | Negative transit times that pull the average down |
| 6 | Non-canceled order without an approval date | 19 orders | Missing information in approval time |
| 7 | Zero payments | 9 payments | Lower average ticket |
| 8 | `delivered` status without a delivery date | 8 orders | "Delivered" orders missing from delivery times |
| 9 | Non-canceled order without products | 8 orders | Orders with no sales |
| 10 | Canceled order with a customer delivery date | 6 orders | Deliveries counted on a canceled order |

All 15 rules are in [`resultados/reglas.csv`](resultados/reglas.csv), and the 2,723 records with problems, with their IDs, in [`resultados/registros_con_problemas.csv`](resultados/registros_con_problemas.csv).

### How much does a KPI change?

| KPI | Raw data | Validated data |
|---|---|---|
| % late deliveries | 8.11% (96,478 orders) | 8.13% (96,282 orders) |

The **% of late deliveries is reliable**: it moves only 0.02 points. The problems weigh more on **stage times** (23 negative transit times and 166 negative preparation times) and on **sales by category** (1.32% without a category). That's why each KPI should be validated on its own instead of trusting the whole database.

## Recommendations

1. **Fix at the source** the 189 out-of-order dates (166 + 23) and the 8 delivered orders without a date. Meanwhile, the times dashboard should exclude them and say so in a note.
2. **Assign a category** to the 610 uncategorized products, starting with the best sellers.
3. **Use `review_id` + `order_id` as the key** for reviews, not `review_id` alone.
4. **Define a single source of revenue** (payments or items) and review the 249 orders that don't reconcile.
5. **Run this script before every dashboard refresh**, to catch issues before users do.

## Files

| File | Content |
|---|---|
| [`validacion.R`](validacion.R) | Full script: load, 32 rules, results, chart and KPI impact |
| [`resultados/reglas.csv`](resultados/reglas.csv) | The 32 rules with records checked, records with problems, % and severity |
| [`resultados/registros_con_problemas.csv`](resultados/registros_con_problemas.csv) | Each record with a problem and the rule it fails |
| [`resultados/impacto_tablero.csv`](resultados/impacto_tablero.csv) | % late deliveries with raw and validated data |
| [`resultados/salida_consola.txt`](resultados/salida_consola.txt) | Full output of the last run |
| [`figuras/problemas_por_regla.png`](figuras/problemas_por_regla.png) | Chart of records with problems by rule |

## How to run it

1. Download the dataset from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) and put the 8 CSV files (keeping their names) in the `datos/` folder. Use the `olist_*_dataset.csv` files and `product_category_name_translation.csv`.
2. From the project folder: `Rscript validacion.R`

## Related projects

- [olist-sql](https://github.com/rafaeladonay7-design/olist-sql): logistics diagnostic of the same database with SQL.
