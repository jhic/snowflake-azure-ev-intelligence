import json
import os
from typing import Any, Dict, List, Optional, Tuple

import altair as alt
import pandas as pd
import pydeck as pdk
import requests
import streamlit as st
from snowflake.snowpark.context import get_active_session

try:
    import _snowflake
except ImportError:
    _snowflake = None

SEMANTIC_VIEW = "EV_INTELLIGENCE.AI.EV_SEMANTIC"
ANALYST_ENDPOINT = "/api/v2/cortex/analyst/message"
REQUEST_TIMEOUT_MS = 60000
TOKEN_PATH = "/snowflake/session/token"

ACCENT = "#29B5E8"
ACCENT_DARK = "#11567F"
MAX_BARS = 15

STARTER_QUESTIONS = [
    "Which counties have the most registered EVs?",
    "What is the average electric range by make?",
    "How has EV adoption changed by model year?",
    "Show me EV registration density on a map",
]

session = get_active_session()

st.set_page_config(
    page_title="EV Intelligence",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="expanded",
)


def call_analyst(messages: List[Dict[str, Any]]) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    body = {"messages": messages, "semantic_view": SEMANTIC_VIEW}

    if _snowflake is not None:
        try:
            response = _snowflake.send_snow_api_request(
                "POST", ANALYST_ENDPOINT, {}, {}, body, None, REQUEST_TIMEOUT_MS
            )
        except Exception as exc:
            return None, f"Could not reach Cortex Analyst: {exc}"
        status = response.get("status")
        raw = response.get("content", "")
    else:
        host = os.getenv("SNOWFLAKE_HOST")
        if not host or not os.path.isfile(TOKEN_PATH):
            return None, "No Snowflake session credentials found in this runtime."
        with open(TOKEN_PATH) as handle:
            token = handle.read().strip()
        try:
            response = requests.post(
                f"https://{host}{ANALYST_ENDPOINT}",
                headers={
                    "Authorization": f"Bearer {token}",
                    "X-Snowflake-Authorization-Token-Type": "OAUTH",
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
                json=body,
                timeout=REQUEST_TIMEOUT_MS / 1000,
            )
        except Exception as exc:
            return None, f"Could not reach Cortex Analyst: {exc}"
        status = response.status_code
        raw = response.text

    try:
        parsed = json.loads(raw) if isinstance(raw, str) else raw
    except json.JSONDecodeError:
        return None, f"Cortex Analyst returned a response that could not be read (status {status})."

    if status != 200:
        detail = parsed.get("message") if isinstance(parsed, dict) else None
        return None, detail or f"Cortex Analyst returned status {status}."

    return parsed, None


def split_content(content: List[Dict[str, Any]]) -> Tuple[List[str], Optional[str], List[str]]:
    texts: List[str] = []
    sql: Optional[str] = None
    suggestions: List[str] = []

    for block in content:
        kind = block.get("type")
        if kind == "text":
            texts.append(block.get("text", ""))
        elif kind == "sql":
            sql = block.get("statement")
        elif kind == "suggestions":
            suggestions.extend(block.get("suggestions", []))

    return texts, sql, suggestions


def find_coordinate_columns(df: pd.DataFrame) -> Optional[Tuple[str, str]]:
    lat_col = None
    lon_col = None

    for column in df.columns:
        if not pd.api.types.is_numeric_dtype(df[column]):
            continue
        upper = column.upper()
        values = df[column].dropna()
        if values.empty:
            continue
        if lat_col is None and "LAT" in upper and values.between(-90, 90).all():
            lat_col = column
        elif lon_col is None and ("LON" in upper or "LNG" in upper) and values.between(-180, 180).all():
            lon_col = column

    if lat_col and lon_col:
        return lat_col, lon_col
    return None


def find_measure_column(df: pd.DataFrame, exclude: List[str]) -> Optional[str]:
    for column in df.columns:
        if column in exclude:
            continue
        if pd.api.types.is_numeric_dtype(df[column]):
            return column
    return None


HEAT_COLORS = [
    [199, 233, 249],
    [143, 211, 244],
    [82, 187, 238],
    [41, 181, 232],
    [23, 122, 176],
    [17, 86, 127],
]


def build_map(df: pd.DataFrame, lat_col: str, lon_col: str, measure: Optional[str], mode: str) -> pdk.Deck:
    data = df.dropna(subset=[lat_col, lon_col]).copy()
    data = data.rename(columns={lat_col: "lat", lon_col: "lon"})

    if measure:
        data = data.rename(columns={measure: "measure"})
        largest = float(data["measure"].max()) or 1.0
        data["radius"] = (data["measure"] / largest) ** 0.5 * 2200 + 150
        tooltip_measure = f"{measure}: {{measure}}"
    else:
        data["measure"] = 1
        data["radius"] = 400
        tooltip_measure = ""

    label_cols = [c for c in data.columns if c not in ("lat", "lon", "measure", "radius")]
    label = label_cols[0] if label_cols else None
    tooltip_text = f"{{{label}}}\n{tooltip_measure}" if label else tooltip_measure

    view = pdk.ViewState(
        latitude=float(data["lat"].mean()),
        longitude=float(data["lon"].mean()),
        zoom=6,
        pitch=0,
    )

    if mode == "Heatmap":
        layer = pdk.Layer(
            "HeatmapLayer",
            data=data,
            get_position=["lon", "lat"],
            get_weight="measure",
            radius_pixels=55,
            intensity=1,
            threshold=0.03,
            color_range=HEAT_COLORS,
            opacity=0.8,
        )
        return pdk.Deck(layers=[layer], initial_view_state=view, map_style=None)

    layer = pdk.Layer(
        "ScatterplotLayer",
        data=data,
        get_position=["lon", "lat"],
        get_radius="radius",
        radius_min_pixels=2,
        radius_max_pixels=24,
        get_fill_color=[41, 181, 232, 90],
        get_line_color=[17, 86, 127, 170],
        line_width_min_pixels=1,
        stroked=True,
        filled=True,
        pickable=True,
    )

    return pdk.Deck(
        layers=[layer],
        initial_view_state=view,
        map_style=None,
        tooltip={"text": tooltip_text} if tooltip_text else None,
    )


def is_year(name: str, values: pd.Series) -> bool:
    if not pd.api.types.is_numeric_dtype(values):
        return False
    if "YEAR" not in name.upper():
        return False
    return values.between(1900, 2100).all()


def plan_chart(df: pd.DataFrame) -> Optional[Tuple[str, str, str]]:
    if df.shape[0] < 2 or df.shape[1] != 2:
        return None

    label, value = df.columns[0], df.columns[1]

    if not pd.api.types.is_numeric_dtype(df[value]):
        return None

    if is_year(label, df[label]):
        return label, value, "line"

    if pd.api.types.is_numeric_dtype(df[label]) and df[label].nunique() != len(df):
        return None

    return label, value, "bar"


def build_chart(df: pd.DataFrame, label: str, value: str, kind: str) -> alt.Chart:
    data = df.rename(columns={label: "label", value: "value"})

    if kind == "line":
        data = data.sort_values("label")
        line = (
            alt.Chart(data)
            .mark_line(color=ACCENT, strokeWidth=3, point=alt.OverlayMarkDef(color=ACCENT_DARK, size=60))
            .encode(
                x=alt.X("label:Q", title=label.replace("_", " ").title(), axis=alt.Axis(format="d")),
                y=alt.Y("value:Q", title=value.replace("_", " ").title()),
                tooltip=[
                    alt.Tooltip("label:Q", title=label.replace("_", " ").title(), format="d"),
                    alt.Tooltip("value:Q", title=value.replace("_", " ").title(), format=","),
                ],
            )
        )
        area = line.mark_area(color=ACCENT, opacity=0.15).encode(
            x=alt.X("label:Q"), y=alt.Y("value:Q")
        )
        return (area + line).properties(height=380)

    data = data.sort_values("value", ascending=False).head(MAX_BARS)

    base = alt.Chart(data).encode(
        y=alt.Y("label:N", sort="-x", title=None),
        x=alt.X("value:Q", title=value.replace("_", " ").title(), axis=alt.Axis(format=",")),
        tooltip=[
            alt.Tooltip("label:N", title=label.replace("_", " ").title()),
            alt.Tooltip("value:Q", title=value.replace("_", " ").title(), format=","),
        ],
    )

    bars = base.mark_bar(cornerRadiusEnd=3).encode(
        color=alt.Color("value:Q", scale=alt.Scale(range=[ACCENT, ACCENT_DARK]), legend=None)
    )

    labels = base.mark_text(align="left", dx=5, color="#4A5568").encode(
        text=alt.Text("value:Q", format=",.0f")
    )

    height = max(220, 30 * len(data))
    return (bars + labels).properties(height=height)


def render_result(sql: str, key: str) -> None:
    if st.toggle("Show generated SQL", key=f"sql_{key}"):
        st.code(sql, language="sql")

    try:
        df = session.sql(sql).to_pandas()
    except Exception as exc:
        st.error(f"The generated query did not run: {exc}")
        return

    if df.empty:
        st.info("That query returned no rows. Try widening the filters or asking about a different slice.")
        return

    coords = find_coordinate_columns(df)

    if coords:
        lat_col, lon_col = coords
        measure = find_measure_column(df, [lat_col, lon_col])
        map_tab, data_tab = st.tabs(["Map", "Data"])
        with map_tab:
            mode = st.radio(
                "View",
                ["Heatmap", "Points"],
                horizontal=True,
                label_visibility="collapsed",
                key=f"mapmode_{key}",
            )
            st.pydeck_chart(
                build_map(df, lat_col, lon_col, measure, mode), use_container_width=True
            )
            st.caption(
                "Zip code centroids weighted by registration count. "
                "This shows where vehicles are registered, not where individual vehicles are."
            )
        with data_tab:
            st.dataframe(df, use_container_width=True)
        return

    plan = plan_chart(df)

    if not plan:
        st.dataframe(df, use_container_width=True)
        return

    label, value, kind = plan
    chart_tab, data_tab = st.tabs(["Chart", "Data"])

    with chart_tab:
        st.altair_chart(build_chart(df, label, value, kind), use_container_width=True)
        if kind == "bar" and len(df) > MAX_BARS:
            st.caption(f"Showing the top {MAX_BARS} of {len(df)}. Full results are in the Data tab.")

    with data_tab:
        st.dataframe(df, use_container_width=True)


def render_suggestions(suggestions: List[str], prefix: str) -> None:
    st.markdown("**Try asking:**")
    for i, suggestion in enumerate(suggestions):
        if st.button(suggestion, key=f"{prefix}_{i}"):
            st.session_state.pending = suggestion
            st.rerun()


def render_message(message: Dict[str, Any], index: int) -> None:
    with st.chat_message(message["role"]):
        if message["role"] == "user":
            st.markdown(message["content"][0]["text"])
            return

        texts, sql, suggestions = split_content(message["content"])

        for text in texts:
            st.markdown(text)

        if sql:
            render_result(sql, f"history_{index}")

        if suggestions:
            render_suggestions(suggestions, f"history_{index}")


def submit(question: str) -> None:
    st.session_state.messages.append(
        {"role": "user", "content": [{"type": "text", "text": question}]}
    )

    with st.chat_message("user"):
        st.markdown(question)

    with st.chat_message("analyst"):
        with st.spinner("Working out the query"):
            parsed, error = call_analyst(st.session_state.messages)

        if error:
            st.error(error)
            st.session_state.messages.pop()
            return

        content = parsed.get("message", {}).get("content", [])
        texts, sql, suggestions = split_content(content)

        for text in texts:
            st.markdown(text)

        if sql:
            render_result(sql, f"live_{len(st.session_state.messages)}")

        if suggestions:
            render_suggestions(suggestions, f"live_{len(st.session_state.messages)}")

        st.session_state.messages.append({"role": "analyst", "content": content})


if "messages" not in st.session_state:
    st.session_state.messages = []
if "pending" not in st.session_state:
    st.session_state.pending = None

st.title("⚡ EV Intelligence")
st.caption("Ask about Washington State electric vehicle registrations in plain language.")

with st.sidebar:
    st.subheader("Starter questions")
    for i, question in enumerate(STARTER_QUESTIONS):
        if st.button(question, key=f"starter_{i}", use_container_width=True):
            st.session_state.pending = question
            st.rerun()

    st.divider()
    st.caption(f"Semantic view: `{SEMANTIC_VIEW}`")
    st.caption(f"Runtime: {'warehouse' if _snowflake is not None else 'container'}")

    if st.button("Clear conversation", use_container_width=True):
        st.session_state.messages = []
        st.session_state.pending = None
        st.rerun()

for index, message in enumerate(st.session_state.messages):
    render_message(message, index)

typed = st.chat_input("Ask a question about the EV data")

if st.session_state.pending:
    question = st.session_state.pending
    st.session_state.pending = None
    submit(question)
elif typed:
    submit(typed)