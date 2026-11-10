#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# 从 Config/builds.json 生成 GitHub Actions 构建矩阵。
# 用法: plan-builds.py <builds.json> <SOURCE|ALL> <PROFILE|ALL>
# 输出: {"include": [...]}，写入 stdout；错误写入 stderr 并返回非 0。

import json
import sys
from pathlib import Path


def fail(message: str) -> int:
    print(f"::error::{message}", file=sys.stderr)
    return 1


def main() -> int:
    if len(sys.argv) != 4:
        return fail("用法: plan-builds.py <builds.json> <SOURCE|ALL> <PROFILE|ALL>")

    cfg_path = Path(sys.argv[1])
    source = sys.argv[2] or "ALL"
    profile = sys.argv[3] or "ALL"

    if not cfg_path.is_file():
        return fail(f"缺少 {cfg_path}")

    cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    sources = cfg["sources"]
    profiles = cfg["profiles"]
    feeds = cfg["feeds"]
    common = cfg["commonFeeds"]

    # 清单自检：任何悬空引用都在这里报清楚，而不是等到编译中途
    build_names = [b["name"] for b in cfg["builds"]]
    duplicates = sorted({n for n in build_names if build_names.count(n) > 1})
    if duplicates:
        return fail(
            f"builds 中 name 重复（tag 由 name + 日期组成，重复会覆盖 Release）: {', '.join(duplicates)}"
        )
    for build in cfg["builds"]:
        if build["source"] not in sources:
            return fail(f"{build['name']} 引用了未知 source: {build['source']}")
        if build["profile"] not in profiles:
            return fail(f"{build['name']} 引用了未知 profile: {build['profile']}")
    for name, prof in profiles.items():
        if not prof.get("packages"):
            return fail(f"profile {name} 没有 packages")
        for key in prof.get("feeds", []):
            if key not in feeds:
                return fail(f"profile {name} 引用了未知 feed: {key}")
    for key in common:
        if key not in feeds:
            return fail(f"commonFeeds 引用了未知 feed: {key}")

    include = []
    for build in cfg["builds"]:
        if source != "ALL" and build["source"] != source:
            continue
        if profile != "ALL" and build["profile"] != profile:
            continue

        src = sources[build["source"]]
        prof = profiles[build["profile"]]
        feed_keys = sorted(set(common) | set(prof.get("feeds", [])))
        include.append({
            "name": build["name"],
            "source": build["source"],
            "profile": build["profile"],
            "repo": src["repo"],
            "branch": src["branch"],
            "packages": prof["packages"],
            "feeds": [feeds[key] for key in feed_keys],
        })

    if not include:
        return fail(
            f"没有匹配的构建组合 (SOURCE={source}, PROFILE={profile}); "
            f"可用 sources: {', '.join(sources)} / 可用 profiles: {', '.join(profiles)}"
        )

    print(json.dumps({"include": include}, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
