"""下载任务的运行控制：暂停 / 恢复 / 取消。

引擎把下载放到工作线程里跑，主线程继续读 stdin，所以需要一个可以从
另一个线程"踩刹车"的对象：每下完一版调一次 `checkpoint()`。
"""

from __future__ import annotations

import threading
import time


class Cancelled(Exception):
    """任务被用户取消。"""


class IssueControl:
    def __init__(self) -> None:
        self._pause = threading.Event()
        self._cancel = threading.Event()

    def pause(self) -> None:
        self._pause.set()

    def resume(self) -> None:
        self._pause.clear()

    def cancel(self) -> None:
        self._cancel.set()
        self._pause.clear()  # 取消要能唤醒正在暂停的任务

    @property
    def cancelled(self) -> bool:
        return self._cancel.is_set()

    @property
    def paused(self) -> bool:
        return self._pause.is_set()

    def checkpoint(self) -> None:
        """每版之间调用一次：暂停则原地等，取消则抛出。"""
        while self._pause.is_set() and not self._cancel.is_set():
            time.sleep(0.1)
        if self._cancel.is_set():
            raise Cancelled
