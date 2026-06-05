# -*- coding: utf-8 -*-
"""Crawler for Dreams of Jianghu (dreamsofjianghu.ca).

Standard WordPress translator site. A novel's table-of-contents page holds the
full chapter list as dated permalinks (``/YYYY/MM/DD/...-chapter-N/``) inside
``div.entry-content``. Chapter bodies live in ``div.entry-content`` too.
"""
import logging
import re
import threading
import time
import urllib.parse

from lncrawl.core import Chapter, LegacyCrawler

logger = logging.getLogger(__name__)


class DreamsOfJianghu(LegacyCrawler):
    base_url = ["https://dreamsofjianghu.ca/"]
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

        # The TOC page <h1> is just "Table of Contents", so derive the title
        # from the parent slug of the URL, e.g.
        # /八宝妆-eight-treasures-trousseau/table-of-contents/ -> Eight Treasures Trousseau
        slug = ""
        parts = [p for p in self.novel_url.split("/") if p]
        for p in parts:
            if p in ("table-of-contents", "toc"):
                break
            slug = p
        slug = urllib.parse.unquote(slug)  # decode %e5%85.. CJK escapes
        ascii_slug = re.sub(r"[^a-zA-Z0-9]+", " ", slug).strip()
        self.novel_title = " ".join(ascii_slug.split()).title() or "Dreams of Jianghu Novel"

        content = soup.select_one("div.entry-content") or soup
        self.volumes.append({"id": 1, "title": self.novel_title})

        seen = set()
        for a in content.select("a[href]"):
            href = self.absolute_url(a.get("href"))
            if not href or href in seen:
                continue
            # chapter permalinks are dated and contain 'chapter'
            if re.search(r"/20\d\d/\d\d/\d\d/", href) and "chapter" in href.lower():
                seen.add(href)
                title = a.get_text(strip=True) or "Chapter %d" % (len(self.chapters) + 1)
                self.chapters.append(
                    Chapter(
                        id=len(self.chapters) + 1,
                        volume=1,
                        url=href,
                        title=title,
                    )
                )

    def download_chapter_body(self, chapter):
        self._pace()
        soup = self.get_soup(chapter["url"])
        content = soup.select_one("div.entry-content")
        if content:
            # Strip images. These are text novels; embedded <img> are ko-fi/
            # support badges or dividers repeated across chapters. lncrawl derives
            # chapter_images.id from the image URL, so a shared image collides on
            # the UNIQUE id and fails chapters with sqlite3.IntegrityError.
            for img in content.select("img"):
                img.decompose()
        return self.cleaner.extract_contents(content)
