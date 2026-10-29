"""PyInstaller 打包入口。

保持极简：只调用引擎的 main，让 PyInstaller 通过静态导入分析收集依赖。
"""

import sys

from rmrb_engine.__main__ import main

if __name__ == "__main__":
    sys.exit(main())
