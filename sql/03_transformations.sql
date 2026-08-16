-- Flatten Socrata JSON (SRC:data) into typed business columns, skipping system metadata (positions 0-7)
-- Co-authored with CoCo

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE EV_WH_XS;

-- Inspect the embedded schema to confirm column positions
-- Positions 0-7: Socrata system columns (sid, id, position, created_at, etc.) — all meta_data, hidden
-- Positions 8-24: Real business fields
-- Positions 25-27: Computed region columns (system-generated)

SELECT
    f.index                           AS col_position,
    f.value:fieldName::STRING         AS field_name,
    f.value:dataTypeName::STRING      AS data_type,
    f.value:flags                     AS flags
FROM EV_INTELLIGENCE.RAW.EV_RAW,
     LATERAL FLATTEN(input => SRC:meta:view:columns) f
ORDER BY f.index;

-- Dynamic table: flatten data array into typed columns (business fields only)
CREATE OR REPLACE DYNAMIC TABLE EV_INTELLIGENCE.ANALYTICS.EV_VEHICLES
  TARGET_LAG = '1 hour'
  WAREHOUSE  = EV_WH_XS
AS
SELECT
    r.value[8]::STRING                          AS VIN_1_10,
    r.value[9]::STRING                          AS COUNTY,
    r.value[10]::STRING                         AS CITY,
    r.value[11]::STRING                         AS STATE,
    r.value[12]::STRING                         AS ZIP_CODE,
    TRY_CAST(r.value[13]::STRING AS INTEGER)    AS MODEL_YEAR,
    r.value[14]::STRING                         AS MAKE,
    r.value[15]::STRING                         AS MODEL,
    r.value[16]::STRING                         AS EV_TYPE,
    r.value[17]::STRING                         AS CAFV_ELIGIBILITY,
    NULLIF(TRY_CAST(r.value[18]::STRING AS INTEGER), 0) AS ELECTRIC_RANGE,
    TRY_CAST(r.value[20]::STRING AS INTEGER)    AS LEGISLATIVE_DISTRICT,
    r.value[21]::STRING                         AS DOL_VEHICLE_ID,
    TRY_TO_GEOGRAPHY(r.value[22]::STRING)       AS VEHICLE_LOCATION,
    ST_X(TRY_TO_GEOGRAPHY(r.value[22]::STRING))  AS LONGITUDE,
    ST_Y(TRY_TO_GEOGRAPHY(r.value[22]::STRING))  AS LATITUDE,
    r.value[23]::STRING                         AS ELECTRIC_UTILITY,
    r.value[24]::STRING                         AS CENSUS_TRACT_2020,
    (r.value[11]::STRING = 'WA')                AS IS_WA_REGISTRATION
FROM EV_INTELLIGENCE.RAW.EV_RAW,
     LATERAL FLATTEN(input => SRC:data) r;
