# snowflake-azure-ev-intelligence
Reference architecture demonstrating Azure ingestion, Snowflake-managed Iceberg interoperability, Cortex AI, governance, and Microsoft co-sell value using EV data.

# Setup

End-to-end setup for the Snowflake + Azure EV Intelligence reference architecture.

Some steps cannot be scripted: Azure IAM role assignments require a Snowflake-generated service principal that does not exist until the Snowflake object is created, and the OAuth redirect URI is not known until the Copilot Studio connector is created. Those manual steps are called out below.

## Prerequisites

- Snowflake trial on Azure (East US 2 or West US 2), with ACCOUNTADMIN
- Azure subscription with permission to create storage accounts and assign IAM roles
- Microsoft Fabric workspace (any SKU, including trial) for the OneLake shortcut
- Microsoft Copilot Studio access for the Teams integration
- `ElectricVehiclePopulationData.json` from the exercise

## 1. Azure storage

Create an ADLS Gen2 storage account in the same region as the Snowflake account, with hierarchical namespace enabled.

Create two containers:

- `landing` — source data
- `iceberg` — external volume base for Snowflake-managed Iceberg tables

Upload `ElectricVehiclePopulationData.json` to `landing`.

## 2. Foundation

Run `sql/01_foundation.sql`. Creates the database, the `RAW` / `ANALYTICS` / `AI` / `ADMIN` schemas, and the warehouse.

## 3. Ingestion

Run `sql/02_ingestion.sql`. Creates the storage integration, external stage, file format, and raw table, then loads the dataset.

**Manual step — Azure consent and IAM.** After the storage integration is created, retrieve the consent URL and service principal:

```sql
DESC STORAGE INTEGRATION AZINT_EV_DEMO;
```

Open `AZURE_CONSENT_URL` in a browser and grant consent. Then, in the Azure portal, on the storage account, assign the application named in `AZURE_MULTI_TENANT_APP_NAME`:

- **Storage Blob Data Reader** — required for reading the `landing` container
- **Storage Blob Data Contributor** — required later for the `iceberg` container

Role assignments take several minutes to propagate. A `403 AuthorizationPermissionMismatch` on first use usually means propagation is still in progress.

The storage integration uses `CREATE ... IF NOT EXISTS` deliberately. Replacing it mints a new service principal and orphans the IAM role assignments above.

## 4. Transformations and gold tables

Run `sql/03_transformations.sql` then `sql/04_gold.sql`. Creates the silver dynamic table and the three aggregate tables.

## 5. Iceberg and Fabric

Run `sql/05_iceberg.sql`. Creates the external volume and the Snowflake-managed Iceberg table.

Verify the external volume:

```sql
SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('EXVOL_EV_ICEBERG');
```

**Manual step — Fabric shortcut.** Get the physical path of the Iceberg table:

```sql
SELECT SYSTEM$GET_ICEBERG_TABLE_INFORMATION('EV_INTELLIGENCE.ANALYTICS.EV_VEHICLES_ICEBERG');
```

Snowflake appends a unique suffix to `BASE_LOCATION`, so the folder name will not match the table name exactly. In Fabric, create a workspace identity, grant it **Storage Blob Data Reader** on the storage account, then create a OneLake shortcut in a non-schema-enabled lakehouse pointing at that exact folder.

Rebuilding the Iceberg table generates a new suffix and orphans the shortcut. If the table is rebuilt, delete and recreate the shortcut.

## 6. Governance

Run `sql/06_governance.sql`. Creates `EV_MCP_ROLE`, the VIN masking policy, and the secure share.

Re-running `sql/03_transformations.sql` detaches the masking policy; re-run this file afterward.

## 7. Semantic view

Run `sql/07_semantic_ai.sql`. Creates the semantic view that powers Cortex Analyst, the agent, and the MCP server.

## 8. Unstructured layer

Upload owner's manual PDFs to `RAW.MANUALS` and vehicle photos to `RAW.PHOTOS`, then run `sql/08_unstructured.sql`.

Manual PDFs are not committed to this repository. Source them from the manufacturers' sites; `scripts/fetch_manuals.py` documents the URLs used.

`PARSE_DOCUMENT` in `LAYOUT` mode is the expensive step in this pipeline. On an X-Small warehouse, eight manuals take well over an hour. Sizing the warehouse up helps but not proportionally, because throughput is bounded by the document AI service rather than by warehouse compute.

Both stages use `SNOWFLAKE_SSE` encryption. This is required for `GET_PRESIGNED_URL`, which the photo tool depends on.

## 9. Agent

The Cortex Agent is created through Snowsight (**AI & ML** » **Agents**) rather than SQL. Create `EV_AGENT` in `EV_INTELLIGENCE.AI` with three tools:

| Tool | Type | Target |
|---|---|---|
| `ev_registration_analytics` | Cortex Analyst | `AI.EV_SEMANTIC` |
| `ev_manual_lookup` | Cortex Search | `AI.EV_MANUAL_SEARCH` |
| `get_vehicle_photo` | Custom (table function) | `AI.GET_VEHICLE_PHOTO` |

Tool descriptions determine routing. Each description should state both what the tool covers and what it does not, or the agent will reach for the wrong one on ambiguous questions.

Publish the agent. The MCP server serves the published version, not the draft.

## 10. MCP server and OAuth

Run `sql/09_mcp.sql`. Creates the MCP server and the OAuth security integration.

Set the user defaults the MCP session depends on:

```sql
ALTER USER <your_user> SET DEFAULT_WAREHOUSE = 'EV_WH_XS';
ALTER USER <your_user> SET DEFAULT_ROLE = 'EV_MCP_ROLE';
```

Cortex Agents determines session permissions from the querying user's default role. Both values must be set or the MCP session fails.

Retrieve the OAuth endpoints and client credentials:

```sql
DESC SECURITY INTEGRATION EV_MCP_OAUTH;
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('EV_MCP_OAUTH');
```

Use the `OAUTH_AUTHORIZATION_ENDPOINT` and `OAUTH_TOKEN_ENDPOINT` values from `DESC`. These use the account-specific hostname, which may differ from the organization-prefixed URL shown elsewhere in Snowsight.

## 11. Copilot Studio

Create a Model Context Protocol server connector:

| Field | Value |
|---|---|
| Server URL | `https://<account_host>/api/v2/databases/EV_INTELLIGENCE/schemas/AI/mcp-servers/EV_MCP` |
| Authentication | OAuth 2.0, Manual |
| Client ID / secret | from `SYSTEM$SHOW_OAUTH_CLIENT_SECRETS` |
| Authorization URL | `OAUTH_AUTHORIZATION_ENDPOINT` from `DESC` |
| Token URL template | `OAUTH_TOKEN_ENDPOINT` from `DESC` |
| Refresh URL | same as token URL |
| Scopes | `session:role:EV_MCP_ROLE refresh_token` |

**Manual step — redirect URI.** Copilot Studio generates the redirect URL only after the connector is created. Copy it and update Snowflake:

```sql
ALTER SECURITY INTEGRATION EV_MCP_OAUTH SET OAUTH_REDIRECT_URI = '<generated url>';
```

Use `ALTER`, not `CREATE OR REPLACE`. Replacing the integration issues new client credentials and invalidates the ones already stored in the connector.

The redirect URI must match exactly, including URL-encoded characters. A mismatch fails at the authorization step without indicating the cause.

Snowflake blocks `ACCOUNTADMIN`, `ORGADMIN`, and `SECURITYADMIN` over OAuth by default, which is why the scope requests a purpose-built role.

Authorize the connection, then add the agent tool and publish to Microsoft Teams.

## 12. Streamlit

The chat interface is deployed from a Snowsight workspace (`streamlit/ev_intelligence_chat/`). Deploy to `EV_INTELLIGENCE.AI` with `EV_WH_XS` as the query warehouse, owned by `EV_MCP_ROLE`.

Apps deployed from workspaces run on a container runtime, where the `_snowflake` module is unavailable. The app detects its runtime and falls back to reading the session token from `/snowflake/session/token` and calling the REST API directly.

## Validation

`python/validate_pipeline.py` is a phase-aware acceptance harness. Expected values are profiled from the source file: 22,183 total rows, 22,120 Washington registrations, 63 out-of-state, 38 Washington counties, 8,155 battery electric vehicles with unresearched range.
