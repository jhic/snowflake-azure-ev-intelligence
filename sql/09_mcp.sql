USE ROLE ACCOUNTADMIN;


CREATE OR REPLACE MCP SERVER EV_INTELLIGENCE.AI.EV_MCP
FROM SPECIFICATION
$$
tools:
  - name: ev_agent
    identifier: EV_INTELLIGENCE.AI.EV_AGENT
    type: CORTEX_AGENT_RUN
    description: "Answers questions about Washington State electric vehicle registrations, EV owner's manuals, and vehicle photos."
$$;

GRANT USAGE ON MCP SERVER EV_INTELLIGENCE.AI.EV_MCP TO ROLE EV_MCP_ROLE;