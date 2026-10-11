#!/usr/bin/env python3
"""
Weekly digest agent for the China Semiconductor Tracker
(live at https://fabs-china.pranaykotas.com).

Ported from the India tracker's weekly_digest.py. Architecture is identical:
  1. Python fetches search snippets via Google News RSS (free, no API key)
  2. Claude synthesizes the snippets against the live data/facilities.yml
     state into a structured digest (no search tools — cheap, bounded)
  3. Output is written as HTML for readable email delivery by the workflow

Key differences from the India version:
  - Queries run in CHINESE against Google News' zh-CN edition (the sources
    that actually cover fab construction on time: 集微网 reprints, 财联社,
    新浪/搜狐 finance, 东方财富, EET-China, 观察者网) plus a handful of
    English queries for the foreign-invested fabs and BIS designations.
  - Facility summary is built from the China YAML schema (name_en/name_zh,
    investment.total_rmb_100m, entity_list{...}, etc).

Run from the repo root:
    ANTHROPIC_API_KEY=... python scripts/weekly_digest.py
"""

import base64
import os
import sys
import time
from datetime import date, datetime, timezone, timedelta
from urllib.parse import quote_plus

import re
import xml.etree.ElementTree as ET

import anthropic
import markdown
import requests
import yaml

# ---------------------------------------------------------------------------
# Search queries — (query, locale) pairs.
#   locale "zh" -> Google News zh-CN (ceid=CN:zh-Hans)
#   locale "en" -> Google News en-US
# ---------------------------------------------------------------------------
QUERIES = [
    # Domestic foundries, tracked company by company
    ("中芯国际 扩产 OR 晶圆厂 OR 投产", "zh"),
    ("中芯北方 OR 中芯南方 OR SN2 增资 OR 收购", "zh"),
    ("华虹 无锡 OR 12英寸 OR 华力", "zh"),
    ("晶合集成 四期 OR 扩产", "zh"),
    ("粤芯半导体", "zh"),
    ("芯联集成 碳化硅 OR 四期", "zh"),
    ("积塔半导体 临港", "zh"),
    ("华润微 重庆 OR 深圳 OR 功率半导体", "zh"),
    ("士兰微 碳化硅 OR 12英寸 OR 集华", "zh"),
    ("燕东微电子 OR 北电集成 28纳米", "zh"),
    ("万国半导体 重庆", "zh"),
    ("和舰 苏州 晶圆", "zh"),
    ("罕王微电子 OR 臻芯微", "zh"),
    ("芯恩 青岛", "zh"),
    # Memory
    ("长江存储", "zh"),
    ("长鑫存储 OR 长鑫科技 DRAM", "zh"),
    ("福建晋华", "zh"),
    ("武汉新芯 OR 新芯股份", "zh"),
    ("昇维旭 存储", "zh"),
    # OSAT / advanced packaging
    ("长电科技 封测 OR 临港", "zh"),
    ("通富微电 HBM OR 先进封装", "zh"),
    ("华天科技 先进封装", "zh"),
    ("盛合晶微 2.5D OR 先进封装", "zh"),
    # Compound semiconductors
    ("英诺赛科 氮化镓", "zh"),
    ("三安光电 碳化硅 OR 湖南三安", "zh"),
    ("安意法半导体 重庆", "zh"),
    ("长飞先进 碳化硅", "zh"),
    # Foreign-invested fabs in China
    ("台积电 南京 OR 上海 fab", "zh"),
    ("三星 西安 半导体", "zh"),
    ("SK海力士 无锡 OR 大连 OR 重庆", "zh"),
    ("德州仪器 成都 工厂", "zh"),
    ("三安集成 OR 泉州三安 化合物", "zh"),
    # Enumeration sources — the class of report that lists ALL fabs,
    # which is how the October 2026 completeness audit was actually done
    ("芯思想 OR icview 中国 晶圆厂 统计 OR 产能调查", "zh"),
    ("site:icviews.cn 晶圆厂 OR 产线 OR 投产", "zh"),
    ("集微咨询 OR JW 中国晶圆厂 产能 排名", "zh"),
    ("SEMI 晶圆厂 报告 中国大陆", "zh"),
    ("site:semi.org.cn 晶圆厂 OR 产线 OR 通线", "zh"),
    ("中国半导体行业协会 集成电路 制造 数据", "zh"),
    # Catch-all: new fab projects this tracker may not have yet
    ("晶圆厂 开工 OR 通线 OR 投产 项目", "zh"),
    ("12英寸 生产线 启动 投资", "zh"),
    ("碳化硅 产线 通线 OR 投产", "zh"),
    ("先进封装 基地 开工 OR 投产", "zh"),
    # English: designations + cross-checks on the big stories
    ("SMIC fab construction China", "en"),
    ("YMTC OR CXMT NAND DRAM expansion", "en"),
    ("China semiconductor Entity List", "en"),
]

SYNTHESIS_PROMPT = """\
You are the editor of the China Semiconductor Tracker weekly digest
(live at https://fabs-china.pranaykotas.com, maintained by Pranay
Kotasthane, Takshashila Institution).

## Current state of tracked facilities

```yaml
{facilities_summary}
```

## All tracked facility names (every facility must appear in the digest)

{facility_names}

## Search results from the past week

{search_results}

## Your task

Compare the search results against the current YAML state and write the
weekly digest. Only include updates that represent a CHANGE from what is
already in the YAML. Before flagging anything, check the facility's FULL
milestones[] list above (not just the most recent entry) — outlets
frequently re-report an old groundbreaking, line-out (通线), or
inauguration days or weeks later with a fresh publish date. If the event,
investment figure, or partner in a result already appears anywhere in that
facility's milestones/investment/partners, it is NOT an update — put it
under "Confirmed: no news", not "Likely updates needed".

Chinese-language snippets may name facilities by company short-name (e.g.
中芯西青 = SMIC Tianjin, 长存 = YMTC, 长鑫 = CXMT, 华力 = HLMC, 新芯 = XMC) —
map them to the right facility before deciding whether it is new.

Every facility listed above must appear in exactly one section of the digest.

Use exactly this format:

---

### Likely updates needed

For each high-confidence update (clear source URL, clear change from YAML state):

**[Facility name]**
- What changed: 1-2 sentences
- Source: [URL] (date)
- Suggested YAML edit:
  ```yaml
  <show only the changed fields, and ALWAYS include sources[] and milestones[] entries>
  ```

### Possibly relevant (lower confidence)

Short bullets for items with weaker sources or unclear relevance. Include source URL.

### New facilities / expansions not yet tracked

Announcements for facilities NOT currently in the YAML. If a big named
expansion phase of an existing site (e.g. a new 期 phase) is reported and
the tracker splits phases into separate entries, flag it here.

### Confirmed: no news

List every facility from "All tracked facility names" that does not appear
in any section above. Every facility must be accounted for — do not leave
any out.

---

Rules:
- Every claim must cite a URL from the search results above. No invented sources.
- Do not infer updates that aren't in the results.
- A search snippet alone is weak evidence for a STATUS change: if a result
  suggests SMIC/ YMTC/ CXMT etc. reached a new node or was (de)listed, mark
  it "Possibly relevant" and say it needs verification against a primary
  source, not "Likely updates needed", unless the snippet is from the
  company's own disclosure (年报/公告/上交所/深交所 filing).
- YAML schema: id, name_en, name_zh, company_en, partners[],
  location{{city,province}}, type (Fab|Memory|Assembly & Packaging|Compound
  Semiconductor|Research Fab), category (State-Backed|Private|JV|
  Foreign-Invested), capability, investment.{{total_rmb_100m,
  total_usd_million,source}}, status (Announced|Approved|Under Construction|
  Operational|On Hold|Cancelled), entity_list.{{status,date_added,list}},
  milestones[].date+event, dates.{{announced,approved,construction_start,
  original_expected_completion,date_completion}},
  sources[].{{url,title,date}}
- Every "Suggested YAML edit" MUST include both:
  1. A milestones[] entry for the new event (if applicable)
  2. A sources[] entry with the article URL, title, and date — like this:
     milestones:
       - date: "YYYY-MM-DD"
         event: "Description of what happened"
     sources:
       - url: <use the real article URL from the search results, not a proxy URL>
         title: <article headline>
         date: "YYYY-MM-DD"
- Today's date: {today}
"""

HTML_TEMPLATE = """\
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body {{ font-family: Arial, Helvetica, sans-serif; max-width: 680px; margin: 0 auto;
          padding: 20px; color: #222; line-height: 1.5; }}
  h2   {{ color: #620d3c; border-bottom: 2px solid #620d3c; padding-bottom: 6px; }}
  h3   {{ color: #620d3c; border-bottom: 1px solid #ddd; padding-bottom: 4px; margin-top: 28px; }}
  code {{ background: #f4f4f4; padding: 2px 5px; border-radius: 3px; font-size: 0.88em; }}
  pre  {{ background: #f4f4f4; padding: 12px; border-radius: 6px; overflow-x: auto;
          font-size: 0.85em; border-left: 3px solid #f1a222; }}
  pre code {{ background: none; padding: 0; }}
  a    {{ color: #1565C0; }}
  hr   {{ border: none; border-top: 1px solid #eee; margin: 24px 0; }}
  ul   {{ padding-left: 20px; }}
  li   {{ margin-bottom: 6px; }}
  strong {{ color: #111; }}
  p    {{ margin: 8px 0; }}
</style>
</head>
<body>
<h2>{subject}</h2>
{content}
</body>
</html>"""

LOCALE_PARAMS = {
    "zh": "hl=zh-CN&gl=CN&ceid=CN:zh-Hans",
    "en": "hl=en-US&gl=US&ceid=US:en",
}


def load_yaml(path: str) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def build_facilities_summary(facilities_yaml: str) -> str:
    """Extract only the comparison-relevant fields from the full YAML."""
    data = yaml.safe_load(facilities_yaml)
    summary = []
    for f in data.get("facilities", []):
        milestones = f.get("milestones") or []
        # Send the FULL milestone history, not just the last one — otherwise
        # the synthesis step can't tell an already-logged event apart from
        # genuine news and re-flags recycled articles as "new" updates.
        milestone_log = [
            f"{m.get('date', '')} — {m.get('event', '')}" for m in milestones
        ]
        dates = f.get("dates") or {}
        investment = f.get("investment") or {}
        entity = f.get("entity_list") or {}
        summary.append({
            "id": f.get("id"),
            "name_en": f.get("name_en"),
            "name_zh": f.get("name_zh"),
            "company_en": f.get("company_en"),
            "type": f.get("type"),
            "status": f.get("status"),
            "capability": f.get("capability"),
            "investment_rmb_100m": investment.get("total_rmb_100m"),
            "investment_usd_m": investment.get("total_usd_million"),
            "partners": f.get("partners") or [],
            "entity_list": f"{entity.get('status')} ({entity.get('date_added')}, {entity.get('list')})",
            "original_expected_completion": dates.get("original_expected_completion", ""),
            "date_completion": dates.get("date_completion", ""),
            "milestones": milestone_log,
        })
    return yaml.dump(summary, allow_unicode=True, sort_keys=False)


def resolve_google_news_url(url: str) -> str:
    """
    Resolve a Google News RSS proxy URL to the real article URL.

    Strategy 1: base64 decode the URL blob (fast, no network request).
    Strategy 2: HTTP GET to the non-RSS Google News URL (follows HTTP redirect).
    """
    if "news.google.com" not in url:
        return url

    # Strategy 1: decode base64 blob — older Google News format embeds URL directly
    match = re.search(r"news\.google\.com/(?:rss/)?articles/([^?&/]+)", url)
    if match:
        encoded = match.group(1)
        encoded += "=" * (-len(encoded) % 4)
        try:
            data = base64.urlsafe_b64decode(encoded)
            for prefix in (b"https://", b"http://"):
                idx = data.find(prefix)
                if idx != -1:
                    end = idx
                    while end < len(data) and 0x20 <= data[end] < 0x80:
                        end += 1
                    candidate = data[idx:end].decode("ascii", errors="ignore").rstrip(".,)")
                    if "." in candidate and "news.google.com" not in candidate and len(candidate) > 15:
                        return candidate
        except Exception:
            pass

    # Strategy 2: HTTP GET — non-RSS Google News URLs do HTTP redirect
    web_url = re.sub(r"/rss/articles/", "/articles/", url).split("?")[0]
    try:
        resp = requests.get(
            web_url,
            timeout=10,
            allow_redirects=True,
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/124.0.0.0 Safari/537.36"
                ),
                "Accept": "text/html,application/xhtml+xml",
            },
        )
        if "news.google.com" not in resp.url:
            return resp.url
    except Exception:
        pass

    return url


def fetch_article_info(url: str) -> tuple[str, datetime | None]:
    """
    Return (resolved_url, published_date).
    Resolves Google News proxy URLs and extracts article:published_time meta tag.
    """
    resolved = resolve_google_news_url(url)

    patterns = [
        r'<meta[^>]+property=["\']article:published_time["\'][^>]+content=["\']([^"\']+)["\']',
        r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']article:published_time["\']',
        r'"datePublished"\s*:\s*"([^"]+)"',
        r'<meta[^>]+name=["\']pubdate["\'][^>]+content=["\']([^"\']+)["\']',
    ]
    try:
        resp = requests.get(
            resolved, timeout=8, stream=True,
            headers={"User-Agent": "Mozilla/5.0"}
        )
        resolved = resp.url  # pick up any further redirects
        chunk = b""
        for data in resp.iter_content(chunk_size=1024):
            chunk += data
            if len(chunk) >= 5120:
                break
        text = chunk.decode("utf-8", errors="ignore")
        for pattern in patterns:
            m = re.search(pattern, text, re.IGNORECASE)
            if m:
                raw = m.group(1).strip()
                raw = re.sub(
                    r"(\d{2}:\d{2}:\d{2})(\+\d{2}:\d{2}|Z)?$",
                    lambda x: x.group(0) if x.group(2) else x.group(1) + "+00:00",
                    raw,
                )
                return resolved, datetime.fromisoformat(raw.replace("Z", "+00:00"))
        return resolved, None
    except Exception:
        pass
    return resolved, None


def fetch_snippets(queries: list[tuple[str, str]], max_results: int = 3) -> str:
    """
    Fetch news via Google News RSS (free, no API key). Mixed Chinese (zh-CN)
    and English (en-US) editions per query locale. Only articles from the
    past 7 days are returned.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    lines = []

    for query, locale in queries:
        lines.append(f"\n### Query: {query} [{locale}]")
        try:
            url = (
                f"https://news.google.com/rss/search"
                f"?q={quote_plus(query)}&{LOCALE_PARAMS[locale]}"
            )
            resp = requests.get(url, timeout=10, headers={"User-Agent": "Mozilla/5.0"})
            resp.raise_for_status()

            root = ET.fromstring(resp.content)
            items = root.findall(".//item")
            found = 0
            for item in items:
                if found >= max_results:
                    break
                title = (item.findtext("title") or "").strip()
                link = (item.findtext("link") or "").strip()
                pub_date_str = (item.findtext("pubDate") or "").strip()

                # Parse and filter by RSS date
                try:
                    pub_date = datetime.strptime(pub_date_str, "%a, %d %b %Y %H:%M:%S %Z")
                    pub_date = pub_date.replace(tzinfo=timezone.utc)
                    if pub_date < cutoff:
                        continue
                    date_label = pub_date.strftime("%Y-%m-%d")
                except ValueError:
                    date_label = pub_date_str

                # Resolve proxy URL + verify original article publish date
                resolved_url, actual_date = fetch_article_info(link)
                if actual_date and actual_date < cutoff:
                    continue  # old article re-surfaced by aggregator

                lines.append(f"  - {title} ({date_label})")
                lines.append(f"    URL: {resolved_url}")
                found += 1

            if found == 0:
                lines.append("  (no results in past 7 days)")

        except Exception as e:
            lines.append(f"  (search failed: {e})")

        time.sleep(0.5)

    return "\n".join(lines)


def to_html(subject: str, digest_md: str) -> str:
    """Convert markdown digest to a styled HTML email body."""
    content = markdown.markdown(
        digest_md,
        extensions=["fenced_code"],
    )
    return HTML_TEMPLATE.format(subject=subject, content=content)


def generate_digest(facilities_yaml: str, today: str) -> str:
    print("  Fetching search snippets via Google News RSS...")
    search_results = fetch_snippets(QUERIES)

    facilities_summary = build_facilities_summary(facilities_yaml)

    data = yaml.safe_load(facilities_yaml)
    facility_names = [f.get("name_en", "") for f in data.get("facilities", [])]
    names_list = "\n".join(f"- {name}" for name in facility_names)

    prompt = SYNTHESIS_PROMPT.format(
        facilities_summary=facilities_summary,
        facility_names=names_list,
        search_results=search_results,
        today=today,
    )

    print(f"  Sending to Claude for synthesis (~{len(prompt.split()):,} words)...")
    client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=8192,
        messages=[{"role": "user", "content": prompt}],
    )

    text_blocks = [b.text for b in response.content if hasattr(b, "text") and b.text]
    return text_blocks[-1] if text_blocks else "No digest generated."


def main():
    try:
        with open("data/facilities.yml") as f:
            facilities_yaml = f.read()
    except FileNotFoundError:
        print("ERROR: data/facilities.yml not found. Run from repo root.", file=sys.stderr)
        sys.exit(1)

    today = date.today().isoformat()
    subject = f"[China Semi Tracker] Weekly digest — {today}"

    print(f"Generating weekly digest for {today}...")
    digest = generate_digest(facilities_yaml, today)

    os.makedirs("data", exist_ok=True)

    # Plain text file: subject on line 1 (workflow extracts it for email header)
    with open("data/digest.txt", "w") as f:
        f.write(subject + "\n")

    # HTML file: full styled email body
    with open("data/digest.html", "w") as f:
        f.write(to_html(subject, digest))

    print(f"Done. Written to data/digest.html ({len(digest):,} chars)")


if __name__ == "__main__":
    main()
