# 高质量<免费>交流群

[IPQ技术讨论群](https://qm.qq.com/q/v7nMhzB4oU)

# 高质量<付费>中转站

[LiBwrt-Ai](https://api.zipimg.cn/register?aff=FFPS3UMJ8HJD)

# 本地编译器

https://github.com/VIKINGYFY/OWRT-Tools.git

# 自用修改版插件

https://github.com/VIKINGYFY/packages.git

# OpenWRT-CI

官方版：

https://github.com/immortalwrt/immortalwrt.git

自用版：

https://github.com/VIKINGYFY/immortalwrt.git

大雕版（每次编译同样出一份）：

https://github.com/coolsnowwolf/lede.git

# U-BOOT

高通版-沉心：

https://github.com/chenxin527/uboot-qsdk12.5-build.git

高通版-小猪：

https://github.com/1980490718/u-boot-2016.git

联发科-全新版：

https://github.com/VIKINGYFY/UBOOT-CI/releases

联发科-官方版：

https://drive.wrt.moe/uboot/mediatek

# 固件简要说明

固件每天早上5点自动编译。

固件信息里的时间为编译开始的时间，方便核对上游源码提交时间。

当前仅编译 IPQ53XX(qualcommbe / JDCloud RE-CS-08，即京东云太乙Plus ER2) 系列，共输出六个固件：

| 固件 | 上游 | 插件组合 |
| --- | --- | --- |
| `VIKINGYFY-IPQ53XX-HP` | VIKINGYFY/immortalwrt (owrt) | homeproxy |
| `VIKINGYFY-IPQ53XX-NIKKI` | VIKINGYFY/immortalwrt (owrt) | nikki(mihomo) |
| `VIKINGYFY-IPQ53XX-DPD` | VIKINGYFY/immortalwrt (owrt) | dpd-fw（DPD 加速） |
| `VIKINGYFY-IPQ53XX-SSR` | VIKINGYFY/immortalwrt (owrt) | helloworld / SSR-Plus |
| `LEDE-IPQ53XX-HP` | coolsnowwolf/lede (master) | homeproxy |
| `LEDE-IPQ53XX-NIKKI` | coolsnowwolf/lede (master) | nikki(mihomo) |

所有固件走同一条 `IPQ53XX-Build` 流水线，共用同一台自托管 runner，`max-parallel: 1` 串行构建。

ER2 的硬件修补（MAC 分区名 factory→0:ART、SFP 改 fixed-link 2500base-x、内核 FIT 改 lzma）
对两套源码同样生效；大雕源码的 re-cs-08 是 KERNEL_SIZE 7168k，比自用版更宽松。

全系默认带 Docker；MosDNS 默认不安装。

`VIKINGYFY-IPQ53XX-DPD` 与 `VIKINGYFY-IPQ53XX-SSR` 目前只挂在自用版源码上；
需要大雕版时，在 `Config/builds.json` 的 `builds` 数组里加一行即可。

> `kwrum1/dpd-fw` 不是 flat feed，`Scripts/Packages.sh` 会按其官方
> `openwrt/feed/README.md` 的 Option B，把各包目录以 `PKG_NAME` 链接进 `package/dpd-fw/`。
> 该源部分包依赖上游预编译产物，首次构建请留意构建报告里的 `packages-*.txt`。

## 手动编译

Actions → Run workflow → `IPQ53XX-Build`：

- `SOURCE`：选择上游（ALL / VIKINGYFY / LEDE）
- `PROFILE`：选择插件组合（ALL / homeproxy / nikki / helloworld / dpd）
- 两项都选 ALL 即定时自动编译的全量组合；只想要单个固件就分别选具体值。
- `TEST`（仅输出配置文件）与 `WRT_CLEAN`（彻底重编）同样生效。

# 目录简要说明

workflows——自定义CI配置

Scripts——自定义脚本

Config——自定义配置

## 构建清单

`Config/builds.json` 是唯一真源：

- `sources`：上游仓库与分支
- `feeds`：所有可用包源（名称、仓库、分支、特殊模式、需清理的同名包）
- `commonFeeds`：每个固件都要准备的基础包源
- `profiles`：插件组合 —— 该组合额外安装的包 `packages` 与额外需要的包源 `feeds`
- `builds`：固件列表 —— 产物名 + 上游 + 插件组合

`IPQ53XX-Build.yml` 的 `plan` 作业用 `python3` 读取清单，按手动输入过滤并生成构建矩阵，
再把展开后的包清单与包源交给 `WRT-CORE.yml`；两个脚本只消费数据，不含任何硬编码。

**新增一个插件固件**（无需改脚本）：

1. 在 `feeds` 里声明插件源（若需要）
2. 在 `profiles` 里加一个组合，写 `packages` 与 `feeds`
3. 在 `builds` 里加一行指定产物名、上游、组合
4. 在 `IPQ53XX-Build.yml` 的 `PROFILE` 下拉框加一个选项（仅影响手动单选，ALL 会自动包含新组合）

## 插件控制

- `Config/BASE.txt`：目标平台、设备、构建参数与内核瘦身项（不含包选择项）
- `Config/ENABLE.conf`：全局必装包，一行一个裸包名
- `Config/PRIVATE.txt`：可选本地覆盖（不入库）
- `Scripts/Configure.sh`：唯一的 `.config` 生成器。生成后跑两遍 `make defconfig`，
  把白名单外的**应用层插件**压成 `=n`；`kmod-*` / `lib*` 等依赖类包保持不动，
  由 OpenWrt 的依赖解析决定，避免误伤 `DEPENDS`。再校验白名单并导出包清单报告。

两套源码（含大雕 LEDE 自带的插件）因此受同一份白名单控制，不再需要手写 `=n` 清单。

> 若打包阶段报 `依赖的软件包 xxx 在所有仓库都未提供`，通常是某个依赖包被压成了 `=n`。
> 对照构建报告 `packages-*.txt` 与 `Config/builds.json` 的 profile 包清单即可定位；
> 需要常驻的底层依赖请加进 `Config/ENABLE.conf`，而不是写进某个 profile。

## Star History

<a href="https://www.star-history.com/?repos=vikingyfy%2Fopenwrt-ci&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&legend=top-left" />
 </picture>
</a>
