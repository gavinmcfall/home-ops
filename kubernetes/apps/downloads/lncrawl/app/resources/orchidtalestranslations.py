# -*- coding: utf-8 -*-
"""Crawler for Orchid Tales Translations (orchidtalestranslations.wordpress.com).

WordPress.com site. Quirk: the table-of-contents links point at the *editor*
URLs (``https://wordpress.com/post/<site>/<id>``) rather than public permalinks.
WordPress.com serves any post publicly at ``?p=<id>``, so we rewrite each link.
Chapter bodies are in ``div.entry-content``.
"""
import logging
import re

from lncrawl.core import Chapter, LegacyCrawler

logger = logging.getLogger(__name__)


class OrchidTalesTranslations(LegacyCrawler):
    base_url = ["https://orchidtalestranslations.wordpress.com/"]
    language = "en"
    has_mtl = False
    has_manga = False

    def initialize(self):
        # WordPress.com throttles aggressive concurrent scraping: the default
        # 5 workers fails ~half the chapters with 429/403. Pace the requests.
        self.init_executor(ratelimit=2)

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
        soup = self.get_soup(chapter["url"])
        content = soup.select_one("div.entry-content")
        return self.cleaner.extract_contents(content)
