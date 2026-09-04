from __future__ import annotations

import random
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .config import USER_AGENT


class Fetcher:
    def __init__(self, delay_seconds: float = 0.8, retries: int = 3, timeout: int = 30) -> None:
        self.delay_seconds = delay_seconds
        self.retries = retries
        self.timeout = timeout
        self._last_request = 0.0

    def get(self, url: str) -> str:
        error: Exception | None = None
        for attempt in range(self.retries):
            elapsed = time.monotonic() - self._last_request
            if elapsed < self.delay_seconds:
                time.sleep(self.delay_seconds - elapsed + random.uniform(0.0, 0.15))
            request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/html,application/xhtml+xml"})
            try:
                with urlopen(request, timeout=self.timeout) as response:
                    self._last_request = time.monotonic()
                    return response.read().decode("utf-8", "replace")
            except HTTPError as exc:
                error = exc
                if exc.code not in {408, 429, 500, 502, 503, 504}:
                    raise
                retry_after = exc.headers.get("Retry-After")
                wait = float(retry_after) if retry_after and retry_after.isdigit() else 2 ** attempt
            except (URLError, TimeoutError) as exc:
                error = exc
                wait = 2 ** attempt
            time.sleep(wait + random.uniform(0.0, 0.25))
        assert error is not None
        raise error

