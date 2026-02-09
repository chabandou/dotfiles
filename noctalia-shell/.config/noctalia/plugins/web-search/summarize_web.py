#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from html.parser import HTMLParser

try:
    import trafilatura
except Exception:  # pragma: no cover - optional dependency
    trafilatura = None

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122 Safari/537.36"


def fetch(url: str, timeout: int = 20) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", "ignore")


def normalize_url(url: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    if not parsed.netloc:
        return url
    clean = parsed._replace(fragment="")
    return urllib.parse.urlunsplit(clean)


def decode_ddg_url(href: str) -> str | None:
    if not href:
        return None
    href = href.strip()
    if href.startswith("//"):
        href = "https:" + href
    if href.startswith("/"):
        href = urllib.parse.urljoin("https://duckduckgo.com", href)

    parsed = urllib.parse.urlparse(href)
    if parsed.scheme not in ("http", "https"):
        return None

    if "duckduckgo.com" in parsed.netloc and parsed.path.startswith("/l/"):
        qs = urllib.parse.parse_qs(parsed.query)
        target = qs.get("uddg", [None])[0]
        if not target:
            return None
        return urllib.parse.unquote(target)

    if "duckduckgo.com" in parsed.netloc:
        return None

    return href


class DDGResultParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.results = []
        self._seen = set()
        self._in_link = False
        self._in_snippet = False
        self._link_text = []
        self._snippet_text = []
        self._link_href = ""
        self._link_is_result = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = {k: v for k, v in attrs}
        if tag == "a":
            href = attrs_dict.get("href") or ""
            css_class = attrs_dict.get("class") or ""
            self._link_href = href
            self._in_link = True
            self._link_text = []
            self._link_is_result = "result" in css_class or "result-link" in css_class
        elif tag in ("span", "div"):
            css_class = attrs_dict.get("class") or ""
            if "snippet" in css_class:
                self._in_snippet = True
                self._snippet_text = []

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._in_link:
            title = "".join(self._link_text).strip()
            url = decode_ddg_url(self._link_href)
            is_ddg_redirect = self._link_href.startswith("/l/") or "/l/?" in self._link_href or "duckduckgo.com/l/" in self._link_href
            if url and title and (self._link_is_result or is_ddg_redirect):
                url = normalize_url(url)
                if url not in self._seen:
                    self._seen.add(url)
                    self.results.append({"title": title, "url": url, "snippet": ""})
            self._in_link = False
            self._link_text = []
            self._link_href = ""
            self._link_is_result = False
        elif tag in ("span", "div") and self._in_snippet:
            snippet = " ".join("".join(self._snippet_text).split())
            if snippet and self.results and not self.results[-1]["snippet"]:
                self.results[-1]["snippet"] = snippet
            self._in_snippet = False
            self._snippet_text = []

    def handle_data(self, data: str) -> None:
        if self._in_link:
            self._link_text.append(data)
        if self._in_snippet:
            self._snippet_text.append(data)


def parse_ddg_results_html(html: str, limit: int) -> list:
    parser = DDGResultParser()
    parser.feed(html)
    return parser.results[:limit]


def normalize_text(text: str, max_chars: int) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > max_chars:
        return text[:max_chars].rstrip() + "…"
    return text


def strip_html_tags(html: str) -> str:
    class TagStripper(HTMLParser):
        def __init__(self) -> None:
            super().__init__()
            self._chunks: list[str] = []

        def handle_data(self, data: str) -> None:
            self._chunks.append(data)

        def get_text(self) -> str:
            return " ".join("".join(self._chunks).split())

    stripper = TagStripper()
    stripper.feed(html)
    return stripper.get_text()


def html_to_text(html: str, max_chars: int) -> str:
    text = ""
    if trafilatura:
        text = trafilatura.extract(
            html,
            include_comments=False,
            include_tables=False,
            favor_recall=True,
        ) or ""
    if not text:
        text = strip_html_tags(html)
    return normalize_text(text, max_chars)


def build_prompt(query: str, sources: list) -> str:
    prompt_lines = [
        "Summarize the sources to answer the query.",
        "Return 3 short bullet points. Max 500 characters total.",
        "No preamble, no citations.",
        "",
        f"Query: {query}",
        "",
        "Sources:"
    ]
    for idx, src in enumerate(sources, 1):
        prompt_lines.append(f"{idx}) {src['title']}")
        prompt_lines.append(f"Content: {src['content']}")
        prompt_lines.append("")
    return "\n".join(prompt_lines)


def ollama_generate(model: str, prompt: str, timeout: int = 60) -> str:
    payload = json.dumps({
        "model": model,
        "prompt": prompt,
        "stream": False
    }).encode("utf-8")

    req = urllib.request.Request(
        "http://localhost:11434/api/generate",
        data=payload,
        headers={"Content-Type": "application/json"}
    )

    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read().decode("utf-8", "ignore"))
    return data.get("response", "").strip()

def ollama_list_models(timeout: int = 2) -> list[str]:
    try:
        with urllib.request.urlopen("http://localhost:11434/api/tags", timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8", "ignore"))
        models = data.get("models", []) if isinstance(data, dict) else []
        names = [m.get("name") for m in models if isinstance(m, dict) and m.get("name")]
        return names
    except Exception:
        return []

def ollama_has_model(model: str) -> bool:
    names = ollama_list_models()
    if not names:
        return True  # Don't block if tags endpoint is unavailable
    return model in names

def ollama_ready(timeout: float = 1.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen("http://localhost:11434/api/tags", timeout=1) as resp:
                if getattr(resp, "status", 200) == 200:
                    return True
        except Exception:
            time.sleep(0.2)
    return False


def ensure_ollama_running() -> tuple[bool, str]:
    if ollama_ready(0.2):
        return True, ""

    if shutil.which("ollama") is None:
        return False, "ollama not found in PATH"

    try:
        subprocess.Popen(
            ["ollama", "serve"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception as exc:
        return False, f"failed to start ollama ({exc})"

    if ollama_ready(6.0):
        return True, ""

    return False, "ollama did not start"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--query", required=True)
    parser.add_argument("--sources", type=int, default=3)
    parser.add_argument("--model", default="llama3.2:3b")
    parser.add_argument("--max-chars", type=int, default=1800)
    parser.add_argument("--output-file", default="~/.cache/noctalia/web-search-last.json")
    args = parser.parse_args()

    output_file = args.output_file.strip() if args.output_file else ""
    def write_output(payload: dict) -> None:
        if not output_file:
            return
        try:
            path = os.path.expanduser(output_file)
            directory = os.path.dirname(path)
            if directory:
                os.makedirs(directory, exist_ok=True)
            tmp_path = path + ".tmp"
            with open(tmp_path, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, ensure_ascii=False, indent=2)
            os.replace(tmp_path, path)
        except Exception:
            return

    total_start = time.monotonic()

    query = args.query.strip()
    if not query:
        error_msg = "ERROR: empty query"
        print(error_msg)
        write_output({"error": error_msg})
        return 1

    if trafilatura is None:
        error_msg = f"ERROR: missing dependency 'trafilatura' for {sys.executable} (try: {sys.executable} -m pip install --user trafilatura)"
        print(error_msg)
        write_output({"error": error_msg, "query": query})
        return 1

    try:
        search_start = time.monotonic()
        ddg_url = "https://lite.duckduckgo.com/lite/?q=" + urllib.parse.quote(query)
        ddg_html = fetch(ddg_url)
        results = parse_ddg_results_html(ddg_html, args.sources)
        search_ms = int((time.monotonic() - search_start) * 1000)
    except Exception as exc:
        error_msg = f"ERROR: failed to fetch search results ({exc})"
        print(error_msg)
        write_output({"error": error_msg, "query": query})
        return 1

    if not results:
        error_msg = "ERROR: no search results"
        print(error_msg)
        write_output({"error": error_msg, "query": query})
        return 1

    sources = []
    snippet_sources = []
    fetch_start = time.monotonic()
    for result in results:
        try:
            page_html = fetch(result["url"])
            content = html_to_text(page_html, args.max_chars)
            if not content:
                continue
            sources.append({
                "title": result["title"],
                "url": result["url"],
                "content": content
            })
        except Exception:
            if result.get("snippet"):
                snippet_sources.append({
                    "title": result["title"],
                    "url": result["url"],
                    "content": result["snippet"]
                })
            continue
    fetch_ms = int((time.monotonic() - fetch_start) * 1000)

    if not sources:
        if snippet_sources:
            sources = snippet_sources
        else:
            error_msg = "ERROR: failed to fetch source pages"
            print(error_msg)
            write_output({
                "error": error_msg,
                "query": query,
                "timings_ms": {
                    "search": search_ms,
                    "fetch": fetch_ms,
                },
                "results": results,
            })
            return 1

    prompt = build_prompt(query, sources)

    ok, err = ensure_ollama_running()
    if not ok:
        error_msg = f"ERROR: {err}"
        print(error_msg)
        write_output({
            "error": error_msg,
            "query": query,
            "timings_ms": {
                "search": search_ms,
                "fetch": fetch_ms,
            },
            "results": results,
            "sources": sources,
        })
        return 1

    if not ollama_has_model(args.model):
        error_msg = f"ERROR: ollama model not found: {args.model} (run: ollama pull {args.model} or change the plugin model setting)"
        print(error_msg)
        write_output({
            "error": error_msg,
            "query": query,
            "timings_ms": {
                "search": search_ms,
                "fetch": fetch_ms,
            },
            "results": results,
            "sources": sources,
        })
        return 1

    try:
        llm_start = time.monotonic()
        summary = ollama_generate(args.model, prompt)
        llm_ms = int((time.monotonic() - llm_start) * 1000)
    except Exception as exc:
        error_msg = f"ERROR: ollama request failed ({exc})"
        print(error_msg)
        write_output({
            "error": error_msg,
            "query": query,
            "timings_ms": {
                "search": search_ms,
                "fetch": fetch_ms,
            },
            "results": results,
            "sources": sources,
        })
        return 1

    summary = summary.strip()
    if not summary:
        print("ERROR: empty summary")
        return 1

    total_ms = int((time.monotonic() - total_start) * 1000)
    payload = {
        "summary": summary,
        "query": query,
        "model": args.model,
        "timings_ms": {
            "search": search_ms,
            "fetch": fetch_ms,
            "ollama": llm_ms,
            "total": total_ms,
        },
        "counts": {
            "results": len(results),
            "sources": len(sources),
        },
        "results": results,
        "sources": sources,
    }
    write_output(payload)
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
