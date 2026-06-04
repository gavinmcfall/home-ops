# -*- coding: utf-8 -*-
"""Crawler for Orchid Tales Translations (orchidtalestranslations.wordpress.com).

WordPress.com site. Quirk: the table-of-contents links point at the *editor*
URLs (``https://wordpress.com/post/<site>/<id>``) rather than public permalinks.
WordPress.com serves any post publicly at ``?p=<id>``, so we rewrite each link.
Chapter bodies are in ``div.entry-content``.
"""
import logging
import re
import threading
import time

from lncrawl.core import Chapter, LegacyCrawler

logger = logging.getLogger(__name__)


class OrchidTalesTranslations(LegacyCrawler):
    base_url = ["https://orchidtalestranslations.wordpress.com/"]
    language = "en"
    has_mtl = False
    has_manga = False

    # lncrawl downloads chapters as parallel child-jobs (runner_concurrency,
    # default 5) that bypass the crawler taskman, so a crawler-level ratelimit
    # has no effect. Cap the request rate across all job threads with a shared
    # lock + min-interval to avoid mass 429/403 failures.
    _rate_lock = threading.Lock()
    _next_request = 0.0
    _min_interval = 0.5  # seconds between requests (~2/s)

    def _pace(self):
        cls = type(self)
        with cls._rate_lock:
            now = time.monotonic()
            if now < cls._next_request:
                time.sleep(cls._next_request - now)
                now = time.monotonic()
            cls._next_request = now + cls._min_interval

    def read_novel_info(self):
        # lncrawl reuses the cached crawler instance and may call this more than
        # once (preview + download); reset so chapters don't accumulate.
        self.chapters.clear()
        self.volumes.clear()
        soup = self.get_soup(self.novel_url)

        title_tag = soup.select_one("h1.entry-title, .entry-title")
        raw_title = title_tag.get_text(strip=True) if title_tag else "Orchid Tales Novel"
        self.novel_title = " ".join(raw_title.split())

        content = soup.select_one("div.entry-content") or soup
        self.volumes.append({"id": 1, "title": self.novel_title})

        seen = set()
        for a in content.select("a[href]"):
            href = a.get("href") or ""
            text = a.get_text(strip=True)
            # editor link -> public ?p=<id> permalink
            m = re.search(r"/post/[^/]+/(\d+)", href)
            if m:
                href = self.home_url.rstrip("/") + "/?p=" + m.group(1)
            else:
                href = self.absolute_url(href)
            # only keep this novel's chapter links (skip "Book 1" / external)
            if not href or href in seen:
                continue
            if "chapter" not in text.lower():
                continue
            seen.add(href)
            self.chapters.append(
                Chapter(
                    id=len(self.chapters) + 1,
                    volume=1,
                    url=href,
                    title=text or "Chapter %d" % (len(self.chapters) + 1),
                )
            )

    def download_chapter_body(self, chapter):
        self._pace()
        soup = self.get_soup(chapter["url"])
        content = soup.select_one("div.entry-content")
        return self.cleaner.extract_contents(content)
