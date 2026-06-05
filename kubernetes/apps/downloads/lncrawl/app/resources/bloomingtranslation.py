# -*- coding: utf-8 -*-
"""Crawler for Blooming Translation (bloomingtranslation.home.blog).

WordPress.com-hosted translator site. The novel landing post lists every
chapter as a dated permalink (``/YYYY/MM/DD/mdd-chapter-N-...``) inside
``div.entry-content``. Chapter bodies are in ``div.entry-content``.
"""
import logging
import re
import threading
import time

from lncrawl.core import Chapter, LegacyCrawler

logger = logging.getLogger(__name__)


class BloomingTranslation(LegacyCrawler):
    base_url = ["https://bloomingtranslation.home.blog/"]
    language = "en"
    has_mtl = False
    has_manga = False

    # lncrawl downloads chapters as parallel child-jobs (runner_concurrency,
    # default 5) that call the crawler directly, bypassing its taskman — so a
    # crawler-level executor/ratelimit has no effect. WordPress.com 429s under
    # that concurrency (~47% failures). A shared lock + min-interval caps the
    # request rate across all concurrent job threads.
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
        raw_title = title_tag.get_text(strip=True) if title_tag else "Blooming Translation Novel"
        self.novel_title = " ".join(raw_title.split())  # collapse \xa0 / whitespace

        cover = soup.select_one("div.entry-content img, .wp-post-image")
        if cover and cover.get("src"):
            self.novel_cover = self.absolute_url(cover.get("src"))

        content = soup.select_one("div.entry-content") or soup
        self.volumes.append({"id": 1, "title": self.novel_title})

        seen = set()
        for a in content.select("a[href]"):
            href = self.absolute_url(a.get("href"))
            if not href or href in seen:
                continue
            if re.search(r"/20\d\d/\d\d/\d\d/", href) and "chapter" in href.lower():
                seen.add(href)
                # anchor text is just "Part 1"/"Part 2"; build a real title from
                # the URL slug, e.g. .../mdd-chapter-211-part-2 -> "Chapter 211 Part 2"
                m = re.search(r"/20\d\d/\d\d/\d\d/(.+?)/?$", href)
                slug = (m.group(1) if m else "").replace("mdd-", "")
                slug_title = " ".join(re.sub(r"[^a-zA-Z0-9]+", " ", slug).split()).title()
                title = slug_title or a.get_text(strip=True) or "Chapter %d" % (
                    len(self.chapters) + 1
                )
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
            # Strip images. These are text novels; the only <img> is the
            # translator's ko-fi/support badge, repeated in most chapters. lncrawl
            # derives chapter_images.id from the image URL, so that one shared
            # image collides on the UNIQUE id and fails ~half the chapters with
            # "Failed to fetch chapter" (sqlite3.IntegrityError).
            for img in content.select("img"):
                img.decompose()
        return self.cleaner.extract_contents(content)
