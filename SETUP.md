# Setup

Run the SQL files in order. Six steps need work in the Azure or Microsoft 365 portals, because they depend on values that do not exist until a Snowflake object has been created.

| # | Manual step | Needed before |
|---|---|---|
| 1 | Consent and blob role assignments for the storage integration | Ingestion |
| 2 | OneLake shortcut in Fabric | Power BI |
| 3 | Event Grid, queue, consent and queue role assignment | Snowpipe |
| 4 | Cortex Agent in Snowsight | MCP server |
| 5 | Redirect URI from Copilot Studio back into Snowflake | Teams |
| 6 | Upload manual PDFs and vehicle photos | Unstructured layer |

Azure role assignments take a few minutes to propagate. A `403 AuthorizationPermissionMismatch` on first use usually means it has not finished.

## Prerequisites

- Snowflake trial on Azure, ACCOUNTADMIN
- Azure subscription with permission to create storage accounts and assign IAM roles
- Microsoft Fabric workspace, any SKU
- Microsoft Copilot Studio
- `ElectricVehiclePopulationData.json` from the exercise

Put the Snowflake account, the storage account, and the Fabric workspace in the same region.

## 1. Azure storage

Create an ADLS Gen2 storage account with hierarchical namespace enabled. Add two containers, `landing` and `iceberg`, and a directory `incoming` inside `landing`. Upload the JSON file to `landing`.

## 2. Foundation

```
sql/01_foundation.sql
```

## 3. Ingestion

```
sql/02_ingestion.sql
```

**Manual step 1.**

```sql
DESC STORAGE INTEGRATION AZINT_EV_DEMO;
```

Open `AZURE_CONSENT_URL` and accept. In the Azure portal, on the storage account, assign the application named in `AZURE_MULTI_TENANT_APP_NAME` (search the string before the underscore):

- **Storage Blob Data Reader** on `landing`
- **Storage Blob Data Contributor** on `iceberg`

## 4. Transformations and aggregates

```
sql/03_transformations.sql
sql/04_gold.sql
```

## 5. Iceberg and Fabric

```
sql/05_iceberg.sql
```

**Manual step 2.**

```sql
SELECT SYSTEM$GET_ICEBERG_TABLE_INFORMATION('EV_INTELLIGENCE.ANALYTICS.EV_VEHICLES_ICEBERG');
```

Snowflake appends a random suffix to `BASE_LOCATION`, so the folder name will not match the table name. In Fabric, create a workspace identity, grant it **Storage Blob Data Reader** on the storage account, and create a OneLake shortcut in a non-schema-enabled lakehouse pointing at that exact folder.

Rebuilding the Iceberg table generates a new suffix and orphans the shortcut. The file uses `IF NOT EXISTS` and `INSERT OVERWRITE` to avoid this. If the table is ever rebuilt, delete and recreate the shortcut.

## 6. Governance

```
sql/06_governance.sql
```

Re-running `03_transformations.sql` detaches the masking policy and the PII tag, so run this file again afterward.

To demonstrate sharing, create a reader account and attach the share:

```sql
CREATE MANAGED ACCOUNT EV_PARTNER_READER
  ADMIN_NAME = '<user>' ADMIN_PASSWORD = '<password>' TYPE = READER;

SHOW MANAGED ACCOUNTS;
ALTER SHARE EV_ADOPTION_SHARE ADD ACCOUNTS = <locator>;
```

Reader accounts have no warehouse and bill to the provider. Create an X-Small with a short auto-suspend, and drop the account when finished.

## 7. Semantic view

```
sql/07_semantic_ai.sql
```

## 8. Snowpipe

Azure side first:

```bash
az provider register --namespace Microsoft.EventGrid
az extension add --name eventgrid

az storage queue create --name snowpipe-queue --account-name <storage_account>

export storageid=$(az storage account show --name <storage_account> \
  --resource-group <resource_group> --query id --output tsv)
export queueid="$storageid/queueservices/default/queues/snowpipe-queue"

az eventgrid event-subscription create \
  --source-resource-id $storageid \
  --name snowpipe-ev-sub --endpoint-type storagequeue \
  --endpoint $queueid \
  --advanced-filter data.api stringin CopyBlob PutBlob PutBlockList FlushWithClose SftpCommit
```

The advanced filter limits the subscription to blob creation events. For ADLS Gen2, `FlushWithClose` is the commit signal, and without it files land but never ingest.

```
sql/10_snowpipe.sql
```

**Manual step 3.**

```sql
DESC NOTIFICATION INTEGRATION AZNOTIF_EV_DEMO;
```

Grant consent, then assign **Storage Queue Data Contributor** on the queue itself, not the storage account. This service principal is a different application from the storage integration's.

The pipe cannot be created until that assignment propagates. Once it can:

```sql
SELECT SYSTEM$PIPE_STATUS('EV_INTELLIGENCE.RAW.EV_PIPE');
```

`executionState` should be `RUNNING` with `notificationChannelName` populated.

Backfill `RAW.EV_RECORDS` from the existing raw row before resuming the tasks, and create the stream before the backfill so the task does not reprocess rows already loaded.

## 9. Unstructured layer

**Manual step 6.** Upload owner's manual PDFs to `RAW.MANUALS` and vehicle photos to `RAW.PHOTOS`.

```
sql/08_unstructured.sql
```

A first run takes over an hour. `PARSE_DOCUMENT` in `LAYOUT` mode is bound by the document AI service rather than by warehouse compute, so sizing up helps very little. Subsequent runs parse only files that are not already in `MANUAL_DOCS`.

Manuals are not committed to this repository. Both stages use `SNOWFLAKE_SSE` encryption, which `GET_PRESIGNED_URL` requires.

## 10. Agent

**Manual step 4.** Create the agent in Snowsight under **AI & ML** » **Agents**, in `EV_INTELLIGENCE.AI`, with three tools:

| Tool | Type | Target |
|---|---|---|
| `ev_registration_analytics` | Cortex Analyst | `AI.EV_SEMANTIC` |
| `ev_manual_lookup` | Cortex Search | `AI.EV_MANUAL_SEARCH` |
| `get_vehicle_photo` | Custom table function | `AI.GET_VEHICLE_PHOTO` |

Tool descriptions drive routing, so each should say what the tool covers and what it does not. Publish the agent; the MCP server serves the published version, not the draft.

## 11. MCP server and OAuth

```
sql/09_mcp.sql
```

Set the session defaults the MCP server depends on, since Cortex Agents derive permissions from the querying user's default role:

```sql
ALTER USER <user> SET DEFAULT_WAREHOUSE = 'EV_WH_XS';
ALTER USER <user> SET DEFAULT_ROLE = 'EV_MCP_ROLE';
```

```sql
DESC SECURITY INTEGRATION EV_MCP_OAUTH;
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('EV_MCP_OAUTH');
```

Use the endpoints from `DESC`. They use the account-specific hostname, which differs from the organization-prefixed URL shown elsewhere in Snowsight.

## 12. Copilot Studio

Create a Model Context Protocol server connector:

| Field | Value |
|---|---|
| Server URL | `https://<account_host>/api/v2/databases/EV_INTELLIGENCE/schemas/AI/mcp-servers/EV_MCP` |
| Authentication | OAuth 2.0, Manual |
| Client ID and secret | from `SYSTEM$SHOW_OAUTH_CLIENT_SECRETS` |
| Authorization URL | `OAUTH_AUTHORIZATION_ENDPOINT` |
| Token URL template | `OAUTH_TOKEN_ENDPOINT` |
| Refresh URL | same as token URL |
| Scopes | `session:role:EV_MCP_ROLE refresh_token` |

**Manual step 5.** Copilot Studio generates the redirect URL only after the connector exists. Copy it back:

```sql
ALTER SECURITY INTEGRATION EV_MCP_OAUTH SET OAUTH_REDIRECT_URI = '<generated url>';
```

Use `ALTER` rather than `CREATE OR REPLACE`, which would issue new client credentials and invalidate the ones already in the connector. The URI must match exactly, including encoded characters, and a mismatch fails at authorization without saying why.

Snowflake blocks `ACCOUNTADMIN`, `ORGADMIN` and `SECURITYADMIN` over OAuth by default, which is why the scope requests a purpose-built role.

Authorize the connection, add the agent tool, and publish to Teams.

## 13. Power BI

In the Fabric workspace holding the lakehouse: **Create** » **OneLake catalog** » select the lakehouse » **New semantic model**, and select the Iceberg shortcut table.

This path produces a Direct Lake on OneLake model, which reads the storage location directly and never falls back to DirectQuery. Confirm by dragging the Expressions node into TMDL view: the connector should be `AzureStorage.DataLake`.

The model must be in the same region as the lakehouse, and cannot be in My Workspace. Direct Lake does not support calculated columns, so derived values are measures or are pushed upstream. Measure definitions are in `powerbi/`.

## 14. Streamlit

Deploy `streamlit/ev_intelligence_chat/` to `EV_INTELLIGENCE.AI` with `EV_WH_XS` as the query warehouse, owned by `EV_MCP_ROLE`.

Apps deployed from Snowsight workspaces run on a container runtime where the `_snowflake` module is unavailable. The app detects this and falls back to reading the session token from `/snowflake/session/token`.

## Teardown

```sql
ALTER TASK EV_INTELLIGENCE.RAW.T_EXPLODE_EV SUSPEND;
ALTER TASK EV_INTELLIGENCE.RAW.T_REFRESH_ICEBERG SUSPEND;
ALTER PIPE EV_INTELLIGENCE.RAW.EV_PIPE SET PIPE_EXECUTION_PAUSED = TRUE;
DROP MANAGED ACCOUNT EV_PARTNER_READER;
```

