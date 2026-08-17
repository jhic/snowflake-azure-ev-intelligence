CREATE OR REPLACE SEMANTIC VIEW EV_INTELLIGENCE.AI.EV_SEMANTIC
  TABLES (
    EV_INTELLIGENCE.ANALYTICS.EV_VEHICLES
      COMMENT = 'The table contains records of registered electric vehicles and their associated attributes. Each record represents a single vehicle and includes details about the vehicle''s make, model, type, and electric range, as well as geographic information such as location, utility provider, and legislative district.',

    EV_INTELLIGENCE.ANALYTICS.EV_ADOPTION_BY_COUNTY
      UNIQUE (COUNTY, MODEL_YEAR, EV_TYPE)
      COMMENT = 'The table contains records of electric vehicle adoption aggregated by county. Each record captures the number of vehicles registered, broken down by model year and vehicle type.',

    EV_INTELLIGENCE.ANALYTICS.EV_RANGE_BY_MAKE
      UNIQUE (MAKE, EV_TYPE)
      COMMENT = 'The table contains records summarizing electric vehicle range statistics aggregated by manufacturer and vehicle type. Each record includes average and median range figures, along with counts of total vehicles and the research status of range data.',

    EV_INTELLIGENCE.ANALYTICS.EV_DENSITY_BY_ZIP
      COMMENT = 'The table contains one record per Washington State zip code with the geographic coordinates of that zip code and the number of electric vehicles registered there. Coordinates are zip code centroids rather than individual vehicle locations, so this table describes registration density by area and must not be presented as the precise location of any vehicle. Use this table for map and geographic distribution questions.'
  )
  RELATIONSHIPS (
    EV_VEHICLES_TO_EV_ADOPTION_BY_COUNTY AS EV_VEHICLES (COUNTY, MODEL_YEAR, EV_TYPE)
      REFERENCES EV_ADOPTION_BY_COUNTY (COUNTY, MODEL_YEAR, EV_TYPE),

    EV_VEHICLES_TO_EV_RANGE_BY_MAKE AS EV_VEHICLES (MAKE, EV_TYPE)
      REFERENCES EV_RANGE_BY_MAKE (MAKE, EV_TYPE)
  )
  FACTS (
    EV_VEHICLES.LATITUDE    AS LATITUDE
      COMMENT = 'The geographic latitude coordinate of the electric vehicle''s location.'
      SAMPLE_VALUES ('47.79802', '47.09583', '47.06512'),

    EV_VEHICLES.LONGITUDE   AS LONGITUDE
      COMMENT = 'Geographic longitude coordinates of the electric vehicle''s location.'
      SAMPLE_VALUES ('-117.18147', '-120.26186'),

    EV_RANGE_BY_MAKE.AVG_RANGE    AS AVG_RANGE
      COMMENT = 'The average range of an electric vehicle, measured in miles.'
      SAMPLE_VALUES ('209.385965', '85.750000', '102.132788'),

    EV_RANGE_BY_MAKE.MEDIAN_RANGE AS MEDIAN_RANGE
      COMMENT = 'The median electric vehicle range in miles across a given make.'
      SAMPLE_VALUES ('87.000', '58.000', '84.000'),

    EV_DENSITY_BY_ZIP.ZIP_VEHICLE_COUNT AS VEHICLE_COUNT
      COMMENT = 'The number of electric vehicles registered in a zip code.'
      SAMPLE_VALUES ('1', '47', '612'),

    EV_DENSITY_BY_ZIP.ZIP_BEV_COUNT AS BEV_COUNT
      COMMENT = 'The number of battery electric vehicles registered in a zip code.'
      SAMPLE_VALUES ('1', '35', '498'),

    EV_DENSITY_BY_ZIP.ZIP_PHEV_COUNT AS PHEV_COUNT
      COMMENT = 'The number of plug-in hybrid electric vehicles registered in a zip code.'
      SAMPLE_VALUES ('0', '12', '114')
  )
  DIMENSIONS (
    EV_VEHICLES.CAFV_ELIGIBILITY AS CAFV_ELIGIBILITY
      COMMENT = 'Clean Alternative Fuel Vehicle tax exemption status under Washington RCW 82.08.809. ''Eligibility unknown as battery range has not been researched'' corresponds exactly to vehicles with NULL electric range.'
      SAMPLE_VALUES ('Clean Alternative Fuel Vehicle Eligible', 'Not eligible due to low battery range', 'Eligibility unknown as battery range has not been researched'),

    EV_VEHICLES.CITY AS CITY
      COMMENT = 'The city where the electric vehicle is registered.'
      WITH CORTEX SEARCH SERVICE EV_INTELLIGENCE.AI._CORTEX_ANALYST_EV_VEHICLES_CITY_17CFC73F_8211_43D1_B2F0_605A1360E882
      SAMPLE_VALUES ('Derby', 'Gig Harbor', 'Hansville'),

    EV_VEHICLES.COUNTY AS COUNTY
      COMMENT = 'The county where the electric vehicle is registered.'
      WITH CORTEX SEARCH SERVICE EV_INTELLIGENCE.AI._CORTEX_ANALYST_EV_VEHICLES_COUNTY_A0EDAACB_EA3E_45AD_82EC_DB39C70A72AD
      SAMPLE_VALUES ('Sedgwick', 'San Diego', 'Snohomish'),

    EV_VEHICLES.ELECTRIC_RANGE AS ELECTRIC_RANGE
      COMMENT = 'Electric-only driving range in miles. NULL means Washington State has not researched the value. Averages and medians exclude NULLs and describe only researched vehicles.'
      SAMPLE_VALUES ('21', '215', '266'),

    EV_VEHICLES.ELECTRIC_UTILITY AS ELECTRIC_UTILITY
      COMMENT = 'The name of the electric utility company serving the area where the electric vehicle is registered.'
      WITH CORTEX SEARCH SERVICE EV_INTELLIGENCE.AI._CORTEX_ANALYST_EV_VEHICLES_ELECTRIC_UTILITY_520BE548_949E_4E0B_BBF7_37975D1EC47E
      SAMPLE_VALUES ('PACIFICORP', 'PUGET SOUND ENERGY INC', 'BONNEVILLE POWER ADMINISTRATION||CITY OF TACOMA - (WA)||PENINSULA LIGHT COMPANY'),

    EV_VEHICLES.EV_TYPE AS EV_TYPE
      COMMENT = 'The type of electric vehicle classification.'
      SAMPLE_VALUES ('Plug-in Hybrid Electric Vehicle (PHEV)', 'Battery Electric Vehicle (BEV)'),

    EV_VEHICLES.IS_WA_REGISTRATION AS IS_WA_REGISTRATION
      COMMENT = 'True when the vehicle is registered in Washington State. A small number of out-of-state registrations exist; exclude them for state-level analysis.'
      SAMPLE_VALUES ('TRUE', 'FALSE'),

    EV_VEHICLES.LEGISLATIVE_DISTRICT AS LEGISLATIVE_DISTRICT
      COMMENT = 'The legislative district number associated with the electric vehicle registration.'
      SAMPLE_VALUES ('38', '26'),

    EV_VEHICLES.MAKE AS MAKE
      COMMENT = 'The manufacturer or brand of the electric vehicle.'
      WITH CORTEX SEARCH SERVICE EV_INTELLIGENCE.AI._CORTEX_ANALYST_EV_VEHICLES_MAKE_35B38794_3DB2_4055_8050_AE2EE3B42063
      SAMPLE_VALUES ('NISSAN', 'FORD', 'TESLA'),

    EV_VEHICLES.MODEL AS MODEL
      COMMENT = 'The model name of the electric vehicle.'
      WITH CORTEX SEARCH SERVICE EV_INTELLIGENCE.AI._CORTEX_ANALYST_EV_VEHICLES_MODEL_5738B60B_3E11_4F94_8C37_9967D1FBDDE1
      SAMPLE_VALUES ('FUSION', 'LEAF', 'MODEL 3'),

    EV_VEHICLES.MODEL_YEAR AS MODEL_YEAR
      COMMENT = 'The model year of the electric vehicle.'
      SAMPLE_VALUES ('2018', '2013', '2017'),

    EV_VEHICLES.ZIP_CODE AS ZIP_CODE
      COMMENT = 'The postal zip code associated with the vehicle''s registered location.'
      SAMPLE_VALUES ('98597', '98367', '75068'),

    EV_ADOPTION_BY_COUNTY.COUNTY AS COUNTY
      COMMENT = 'The name of the county associated with electric vehicle adoption data.'
      WITH CORTEX SEARCH SERVICE EV_INTELLIGENCE.AI._CORTEX_ANALYST_EV_ADOPTION_BY_COUNTY_COUNTY_C329084D_2421_41E7_8B82_6C69B5B3431B
      SAMPLE_VALUES ('Asotin', 'Benton', 'Columbia'),

    EV_ADOPTION_BY_COUNTY.EV_TYPE AS EV_TYPE
      COMMENT = 'The type of electric vehicle registered in the county.'
      SAMPLE_VALUES ('Battery Electric Vehicle (BEV)', 'Plug-in Hybrid Electric Vehicle (PHEV)'),

    EV_ADOPTION_BY_COUNTY.MODEL_YEAR AS MODEL_YEAR
      COMMENT = 'The model year of the electric vehicle.'
      SAMPLE_VALUES ('2017', '2020', '2022'),

    EV_ADOPTION_BY_COUNTY.VEHICLE_COUNT AS VEHICLE_COUNT
      COMMENT = 'The total number of electric vehicles recorded per county.'
      SAMPLE_VALUES ('1', '4', '919'),

    EV_RANGE_BY_MAKE.EV_TYPE AS EV_TYPE
      COMMENT = 'The type of electric vehicle.'
      SAMPLE_VALUES ('Battery Electric Vehicle (BEV)', 'Plug-in Hybrid Electric Vehicle (PHEV)'),

    EV_RANGE_BY_MAKE.MAKE AS MAKE
      COMMENT = 'The manufacturer or brand of the electric vehicle.'
      WITH CORTEX SEARCH SERVICE EV_INTELLIGENCE.AI._CORTEX_ANALYST_EV_RANGE_BY_MAKE_MAKE_4843B0B3_2945_4028_A032_C4350A37B40B
      SAMPLE_VALUES ('FIAT', 'NISSAN', 'LAND ROVER'),

    EV_RANGE_BY_MAKE.RESEARCHED_RANGE_COUNT AS RESEARCHED_RANGE_COUNT
      COMMENT = 'The number of times a vehicle range has been researched.'
      SAMPLE_VALUES ('114', '19', '156'),

    EV_RANGE_BY_MAKE.TOTAL_VEHICLES AS TOTAL_VEHICLES
      COMMENT = 'The total number of vehicles associated with each electric vehicle make.'
      SAMPLE_VALUES ('64', '71', '2533'),

    EV_RANGE_BY_MAKE.UNRESEARCHED_RANGE_COUNT AS UNRESEARCHED_RANGE_COUNT
      COMMENT = 'The number of electric vehicle range entries that have not yet been researched for a given make.'
      SAMPLE_VALUES ('329', '334', '0'),

    EV_DENSITY_BY_ZIP.DENSITY_ZIP_CODE AS ZIP_CODE
      COMMENT = 'The Washington State zip code the registration counts apply to.'
      SAMPLE_VALUES ('98052', '98144', '99301'),

    EV_DENSITY_BY_ZIP.DENSITY_COUNTY AS COUNTY
      COMMENT = 'The county containing the zip code.'
      SAMPLE_VALUES ('King', 'Snohomish', 'Spokane'),

    EV_DENSITY_BY_ZIP.DENSITY_CITY AS CITY
      COMMENT = 'The city associated with the zip code.'
      SAMPLE_VALUES ('Seattle', 'Redmond', 'Tacoma'),

    EV_DENSITY_BY_ZIP.ZIP_LATITUDE AS LATITUDE
      COMMENT = 'The latitude of the zip code centroid. Use this together with ZIP_LONGITUDE when the question asks for a map or geographic distribution.'
      SAMPLE_VALUES ('47.79802', '47.09583', '47.06512'),

    EV_DENSITY_BY_ZIP.ZIP_LONGITUDE AS LONGITUDE
      COMMENT = 'The longitude of the zip code centroid. Use this together with ZIP_LATITUDE when the question asks for a map or geographic distribution.'
      SAMPLE_VALUES ('-117.18147', '-120.26186', '-122.31768')
  )
  AI_SQL_GENERATION 'Filter to IS_WA_REGISTRATION = TRUE for state, county, or city level analysis unless the user explicitly asks about out-of-state registrations. Round numeric averages to one decimal place. When calculating a percentage, multiply by 100 and round to one decimal place so the result reads as a percentage rather than a fraction. For any question asking for a map, geographic distribution, or where vehicles are concentrated, query EV_DENSITY_BY_ZIP and return ZIP_LATITUDE and ZIP_LONGITUDE alongside the count.'
  AI_QUESTION_CATEGORIZATION 'When a question involves electric range averages, note in the answer that vehicles whose range has not been researched are excluded from the calculation. When a question involves mapping or geographic distribution, note that coordinates are zip code centroids representing registration density rather than the actual location of individual vehicles.'
  AI_VERIFIED_QUERIES (
    "For battery electric vehicle makes ranked by fleet size, what is the average range and how many vehicles have researched vs. unresearched range data?" AS (
      QUESTION 'For battery electric vehicle makes ranked by fleet size, what is the average range and how many vehicles have researched vs. unresearched range data?'
      VERIFIED_AT 1786911247
      VERIFIED_BY 'Josh Hickok'
      ONBOARDING_QUESTION false
      SQL 'SELECT
  MAKE,
  AVG_RANGE,
  RESEARCHED_RANGE_COUNT,
  UNRESEARCHED_RANGE_COUNT
FROM
  ev_range_by_make
WHERE
  EV_TYPE LIKE ''Battery%''
ORDER BY
  TOTAL_VEHICLES DESC'),

    "For battery electric vehicles, which makes have the most vehicles on the road, and what is their average range along with how many have researched versus unresearched range data?" AS (
      QUESTION 'For battery electric vehicles, which makes have the most vehicles on the road, and what is their average range along with how many have researched versus unresearched range data?'
      VERIFIED_AT 1786911269
      VERIFIED_BY 'Josh Hickok'
      ONBOARDING_QUESTION false
      SQL 'SELECT
  MAKE,
  AVG_RANGE,
  RESEARCHED_RANGE_COUNT,
  UNRESEARCHED_RANGE_COUNT
FROM
  ev_range_by_make
WHERE
  EV_TYPE LIKE ''Battery%''
ORDER BY
  TOTAL_VEHICLES DESC'),

    "Which counties have the most registered electric vehicles?" AS (
      QUESTION 'Which counties have the most registered electric vehicles?'
      VERIFIED_AT 1786911288
      VERIFIED_BY 'Josh Hickok'
      ONBOARDING_QUESTION false
      SQL 'SELECT
  COUNTY,
  SUM(VEHICLE_COUNT) AS TOTAL
FROM
  ev_adoption_by_county
GROUP BY
  COUNTY
ORDER BY
  TOTAL DESC'),

    "How many battery electric vehicles are there compared to plug-in hybrids?" AS (
      QUESTION 'How many battery electric vehicles are there compared to plug-in hybrids?'
      VERIFIED_AT 1786911307
      VERIFIED_BY 'Josh Hickok'
      ONBOARDING_QUESTION false
      SQL 'SELECT
  EV_TYPE,
  COUNT(*) AS VEHICLE_COUNT
FROM
  ev_vehicles
WHERE
  IS_WA_REGISTRATION
GROUP BY
  EV_TYPE'),

    "How has EV adoption changed by model year?" AS (
      QUESTION 'How has EV adoption changed by model year?'
      VERIFIED_AT 1786911320
      VERIFIED_BY 'Josh Hickok'
      ONBOARDING_QUESTION false
      SQL 'SELECT
  MODEL_YEAR,
  SUM(VEHICLE_COUNT) AS TOTAL
FROM
  ev_adoption_by_county
GROUP BY
  MODEL_YEAR
ORDER BY
  MODEL_YEAR'),

    "How many vehicles are missing electric range data?" AS (
      QUESTION 'How many vehicles are missing electric range data?'
      VERIFIED_AT 1786911345
      VERIFIED_BY 'Josh Hickok'
      ONBOARDING_QUESTION false
      SQL 'SELECT
  EV_TYPE,
  COUNT(*)                          AS TOTAL,
  COUNT(ELECTRIC_RANGE)             AS WITH_RANGE,
  COUNT(*) - COUNT(ELECTRIC_RANGE)  AS MISSING_RANGE
FROM
  ev_vehicles
GROUP BY
  EV_TYPE'),

    "How many Teslas are registered in King County?" AS (
      QUESTION 'How many Teslas are registered in King County?'
      VERIFIED_AT 1786911369
      VERIFIED_BY 'Josh Hickok'
      ONBOARDING_QUESTION false
      SQL 'SELECT
  COUNT(*) AS VEHICLE_COUNT
FROM
  ev_vehicles
WHERE
  MAKE              = ''TESLA''
  AND COUNTY        = ''King''
  AND IS_WA_REGISTRATION'),

    "What are the most common EV models?" AS (
      QUESTION 'What are the most common EV models?'
      VERIFIED_AT 1786911379
      VERIFIED_BY 'Josh Hickok'
      ONBOARDING_QUESTION false
      SQL 'SELECT
  MAKE,
  MODEL,
  COUNT(*) AS VEHICLE_COUNT
FROM
  ev_vehicles
WHERE
  IS_WA_REGISTRATION
GROUP BY
  MAKE,
  MODEL
ORDER BY
  VEHICLE_COUNT DESC'),

    "How many vehicles qualify for the clean fuel vehicle tax exemption?" AS (
      QUESTION 'How many vehicles qualify for the clean fuel vehicle tax exemption?'
      VERIFIED_AT 1786911408
      VERIFIED_BY 'Josh Hickok'
      ONBOARDING_QUESTION false
      SQL 'SELECT
  CAFV_ELIGIBILITY,
  COUNT(*) AS VEHICLE_COUNT
FROM
  ev_vehicles
WHERE
  IS_WA_REGISTRATION
GROUP BY
  CAFV_ELIGIBILITY'),

    "Show me EV registration density on a map" AS (
      QUESTION 'Show me EV registration density on a map'
      VERIFIED_AT 1786920800
      VERIFIED_BY 'Josh Hickok'
      ONBOARDING_QUESTION false
      SQL 'SELECT
  DENSITY_ZIP_CODE,
  ZIP_LATITUDE,
  ZIP_LONGITUDE,
  ZIP_VEHICLE_COUNT
FROM
  ev_density_by_zip
ORDER BY
  ZIP_VEHICLE_COUNT DESC'),

    "Where are electric vehicles concentrated in Washington?" AS (
      QUESTION 'Where are electric vehicles concentrated in Washington?'
      VERIFIED_AT 1786920810
      VERIFIED_BY 'Josh Hickok'
      ONBOARDING_QUESTION false
      SQL 'SELECT
  DENSITY_ZIP_CODE,
  DENSITY_CITY,
  ZIP_LATITUDE,
  ZIP_LONGITUDE,
  ZIP_VEHICLE_COUNT
FROM
  ev_density_by_zip
ORDER BY
  ZIP_VEHICLE_COUNT DESC')
  )
  WITH EXTENSION (CA = '{"tables":[{"name":"EV_VEHICLES","dimensions":[{"name":"CAFV_ELIGIBILITY"},{"name":"CITY"},{"name":"COUNTY"},{"name":"ELECTRIC_RANGE"},{"name":"ELECTRIC_UTILITY"},{"name":"EV_TYPE"},{"name":"IS_WA_REGISTRATION"},{"name":"LEGISLATIVE_DISTRICT"},{"name":"MAKE"},{"name":"MODEL"},{"name":"MODEL_YEAR"},{"name":"ZIP_CODE"}],"facts":[{"name":"LATITUDE"},{"name":"LONGITUDE"}]},{"name":"EV_ADOPTION_BY_COUNTY","dimensions":[{"name":"COUNTY"},{"name":"EV_TYPE"},{"name":"MODEL_YEAR"},{"name":"VEHICLE_COUNT"}]},{"name":"EV_RANGE_BY_MAKE","dimensions":[{"name":"EV_TYPE"},{"name":"MAKE"},{"name":"RESEARCHED_RANGE_COUNT"},{"name":"TOTAL_VEHICLES"},{"name":"UNRESEARCHED_RANGE_COUNT"}],"facts":[{"name":"AVG_RANGE"},{"name":"MEDIAN_RANGE"}]},{"name":"EV_DENSITY_BY_ZIP","dimensions":[{"name":"DENSITY_ZIP_CODE"},{"name":"DENSITY_COUNTY"},{"name":"DENSITY_CITY"},{"name":"ZIP_LATITUDE"},{"name":"ZIP_LONGITUDE"}],"facts":[{"name":"ZIP_VEHICLE_COUNT"},{"name":"ZIP_BEV_COUNT"},{"name":"ZIP_PHEV_COUNT"}]}],"relationships":[{"name":"EV_VEHICLES_TO_EV_ADOPTION_BY_COUNTY","join_type":"inner"},{"name":"EV_VEHICLES_TO_EV_RANGE_BY_MAKE","join_type":"inner"}]}');