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

当前仅编译 IPQ53XX(qualcommbe / JDCloud RE-CS-08，即京东云太乙Plus ER2) 系列，两套源码共输出四个固件：
- IPQ53XX-WIFI-NO-homeproxy：默认携带 homeproxy
- IPQ53XX-WIFI-NO-NIKKI：默认携带 nikki(mihomo)
- LEDE-IPQ53XX-WIFI-NO-homeproxy：大雕源码(coolsnowwolf/lede master) + homeproxy
- LEDE-IPQ53XX-WIFI-NO-NIKKI：大雕源码(coolsnowwolf/lede master) + nikki(mihomo)

两套源码走同一条 WRT-CORE 流水线，共用同一台自托管 runner，四个构建按队列逐个跑，
所以一轮完整编译的耗时约为原来的两倍。

ER2 的硬件修补（MAC 分区名 factory→0:ART、SFP 改 fixed-link 2500base-x、内核 FIT 改 lzma）
对两套源码同样生效；大雕源码的 re-cs-08 是 KERNEL_SIZE 7168k，比自用版更宽松。

全系默认带 Docker 与 MosDNS。

## 单独跑某个编译

定时自动编译固定跑全部 4 个固件（每个 workflow 内部的两个配置也全跑）。

手动编译时每个固件都能单独跑：

- Actions → Run workflow，先选流水线（QCB-IPQ53XX-WIFI-NO 或 LEDE-IPQ53XX-WIFI-NO），
  再把 CONFIG 下拉框选成具体配置；默认值 ALL 表示该流水线的两个配置都跑。
- 只想出大雕固件就只跑 LEDE 那条，反之亦然。
- TEST（仅输出配置文件）与 WRT_CLEAN（彻底重编）对单选的配置同样生效。
# 目录简要说明

workflows——自定义CI配置

Scripts——自定义脚本

Config——自定义配置

## Star History

<a href="https://www.star-history.com/?repos=vikingyfy%2Fopenwrt-ci&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&legend=top-left" />
 </picture>
</a>
