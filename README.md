# Snowflake + Azure: EV Intelligence

A reference architecture for Snowflake on Azure, built around Washington State's public electric vehicle registration data.

In this scenario Contoso Logistics has a fleet electrification policy requiring a 200 mile minimum range. We drop in to the data to see how many vehicles meet that policy.

## What it does

Data lands in Azure Data Lake Storage, causing event Grid to notify Snowflake. Snowpipe ingests it, a stream and task explode and upsert it, and a dynamic table refreshes the analytics layer incrementally. The result is written to a Snowflake-managed Iceberg table sitting in the same storage account, which Microsoft Fabric reads through a OneLake shortcut and Power BI queries through Direct Lake without importing a copy.

In parallel, a semantic view over the same tables powers Cortex Analyst, which is one of three tools on a Cortex Agent alongside Cortex Search over owner's manuals and a photo lookup. The agent is published through a Snowflake managed MCP server, authenticated over OAuth, and consumed by a Microsoft Copilot Studio agent that answers questions in Teams.

```
ADLS Gen2 ──► Event Grid ──► Snowpipe ──► RAW.EV_RAW
                                              │ stream
                                              ▼
                                   TASK: FLATTEN + MERGE
                                              │
                                              ▼
                                       RAW.EV_RECORDS
                                              │
                                              ▼
                              ANALYTICS.EV_VEHICLES (dynamic table)
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    ▼                         ▼                         ▼
              gold aggregates          Iceberg on ADLS            AI.EV_SEMANTIC
                    │                         │                         │
                    ▼                         ▼                         ▼
             Streamlit in SiS        OneLake shortcut            AI.EV_AGENT
                                              │                         │
                                              ▼                         ▼
                                   Power BI Direct Lake            AI.EV_MCP
                                                                        │
                                                                        ▼
                                                          Copilot Studio ──► Teams
```

Snowflake publishes a managed MCP server and Microsoft's Work IQ exposes M365 context through an MCP gateway, so Copilot Studio composes the two and the agent can read an email thread and answer from registration data in the same turn.

## Data problems

The source is a Socrata export of Washington's EV registration file. 22,183 vehicles, 22,120 of them registered in Washington.

`Electric Range` is zero for 8,155 records which does not mean the range is zero. Instead, it means the state did not research the range for that registration. All of those records is a battery electric vehicle: 47.8% of all BEVs in the file, and 0% of plug-in hybrids.

The missing data is not randomly distributed. It falls entirely on the vehicle class the 200-mile policy is actually about. Treating those zeros as real values drags the BEV average down against PHEVs, which have no phantom zeros to drag them. Tesla's average range reads 240 miles when the sentinel values are excluded and roughly 114 when they are not.

ANALYTICS.EV_VEHICLES converts those zeros to NULL once, so Power BI, Cortex Analyst, and the Teams agent all report the same figure rather than three engines each deciding what a zero means.

## Data curiosities

- `Base MSRP` is 97% zeros and was dropped from the dataset. Not used here.
- `Vehicle Location` is a zip code centroid in WKT, not an actual vehicle position. Density maps are density by area.
- 63 registrations are out of state. 17 of those are in the unresearched-range bucket, which is why the statewide count is 8,138 and the full-file count is 8,155.
- The Iceberg table defaults to v2, which has no geospatial type, so VEHICLE_LOCATION is serialized to WKT with latitude and longitude materialized alongside it, while ANALYTICS.EV_VEHICLES keeps the native GEOGRAPHY. Iceberg v3 added GEOGRAPHY, but Power BI Direct Lake can't consume a geospatial column either way, so the numeric pair is required regardless.

## Layout

```
sql/
  01_foundation.sql        database, schemas, warehouse
  02_ingestion.sql         storage integration, stage, raw table, bulk load
  03_transformations.sql   silver dynamic table
  04_gold.sql              county, make, and zip aggregates
  05_iceberg.sql           external volume, Snowflake-managed Iceberg table
  06_governance.sql        role, VIN masking policy, secure share
  07_semantic_ai.sql       semantic view
  08_unstructured.sql      manual parsing, chunking, Cortex Search, photo catalog
  09_mcp.sql               MCP server, OAuth security integration
  10_snowpipe.sql          notification integration, pipe, stream, task
  admin/                   optional and exploratory scripts
streamlit/                 Streamlit in Snowflake chat interface
powerbi/                   semantic model definition (TMDL)
```

Setup instructions are in [SETUP.md](SETUP.md).

## Technology choices

**Snowpipe over Azure Data Factory.** Event Grid already emits blob events, so ADF would add a second orchestration plane and a second bill to do what a notification integration does natively.

**Streams and tasks alongside dynamic tables, not instead of them.** COPY transformations do not support `FLATTEN`, so the pipe cannot explode the Socrata array at ingest, and the task handles the flatten and the MERGE while the dynamic table covers everything expressible declaratively above it. Landing one row per vehicle rather than one row per file is also what makes the dynamic table's incremental refresh meaningful, since incremental refresh operates on row-level deltas and a second file would otherwise change 100% of the base table.

**Snowflake-managed Iceberg over externally managed.** Snowflake owns the writer and the metadata, which keeps DML and dynamic table refreshes working normally, and the files still land in the customer's own storage account where Fabric can read them.

**OneLake shortcut over a catalog connection.** The shortcut is Microsoft's documented pattern and works today, at the cost of binding to a storage path rather than a catalog entry.

## Constraints

**Snowflake policies do not federate to OneLake.** The Iceberg Parquet files contain raw values, so masking and row access policies are enforced by Snowflake while OneLake security is enforced by Fabric.

**Snowflake does not clean up orphaned Iceberg folders.** Managed Iceberg writes to the customer's storage account, so lifecycle and cost for anything left behind by a rebuild are theirs.


## Future enhancements
**Write-back for the unresearched range records.** The pipeline discloses the 8,155 records with no researched range but has no way to resolve them, so a write-back path would let analysts record and audit those decisions.

**Forecasting.** Registrations by county and model year are a time series, so projecting adoption forward would let the demo inform siting decisions rather than only describe past adoption.

**Deployment from source.** Snowflake can read this repository directly through a Git repository object, so a single deploy script could stand the whole environment up rather than running the files individually.