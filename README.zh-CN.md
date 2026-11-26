# TrollStore TV Tools

[![CI](https://github.com/comicchang/trollstore-tv-tools/actions/workflows/ci.yml/badge.svg)](https://github.com/comicchang/trollstore-tv-tools/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%20%E2%86%92%20tvOS%2017.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)

[English](README.md) | **简体中文**

面向 **Apple TV 4K（`AppleTV14,1` / tvOS 17.0 `21J354`）** 的宿主机 **CoreTrust 批量签名**、**干净室 tvOS 诊断探针** 与 **冷重启后验收工具箱**。

> 如需 Apple TV 端永久签名安装器本体，请见 **[`trollstore-tv`](https://github.com/comicchang/trollstore-tv)**（tvOS 17.0 CoreTrust 冷重启免越狱存活）或 **[`trollstore-lite-tv`](https://github.com/comicchang/trollstore-lite-tv)**（任意已越狱 tvOS 17.x+，带 `:8787` 网页商店与离线油猴托管）。

---

## 如何选择仓库？

| 仓库 | 定位 | 适用环境 | 许可证 |
| --- | --- | --- | --- |
| **`trollstore-tv-tools`** *（本仓库）* | 宿主机打包（`.deb` 转 `.ipa`、BYOIPA、图标反色）、批量 CoreTrust 签名、探针与冷重启验收 | macOS / Linux → tvOS 17.0 | 纯 MIT |
| [`trollstore-tv`](https://github.com/comicchang/trollstore-tv) | Apple TV 端 CoreTrust 永久签名安装器本体（`TrollStore.app` + `trollstorehelper`，冷重启未越狱直接运行） | **仅限 tvOS 17.0（`21J354`）** | MIT + BSD-4-Clause（`uicache.m`） |
| [`trollstore-lite-tv`](https://github.com/comicchang/trollstore-lite-tv) | 洁净室内核信任缓存安装器（零 CoreTrust 漏洞，带电视界面、`:8787` 网页商店与离线油猴托管） | **任意已越狱 tvOS 17.x+** | 纯 MIT |

---

## 包含工具与模块

| 工具 / 模块 | 用途 | 运行环境 |
| --- | --- | --- |
| [`scripts/deb2ipa.sh`](scripts/deb2ipa.sh) | 将开源 tvOS `.deb` 包（如 Kodi 官方 `.deb`）一键无损转换为纯净 `.ipa` | macOS / Linux |
| [`scripts/build-youtube-tvos.sh`](scripts/build-youtube-tvos.sh) | YouTube tvOS 的 BYOIPA 构建脚本：联动 [`tvos-cobalt-userscript`](https://github.com/comicchang/tvos-cobalt-userscript) 与上游开源 [TizenTube](https://github.com/reisxd/TizenTube)（含 [SponsorBlock](https://github.com/ajayyy/SponsorBlock) / [DeArrow](https://github.com/ajayyy/DeArrow)）（默认开启图标反色，`--no-invert-icon` 可关闭） | macOS / Linux（`uv`） |
| [`scripts/repack-ipa.sh`](scripts/repack-ipa.sh) | 通用 BYOIPA 重打包工具：修改 Bundle ID/名称、默认开启图标反色（`--no-invert-icon` 可关闭）、规范化标准沙箱权限，产出可直接交由 `TrollStore TV` 安装的 `.ipa` | macOS / Linux |
| [`scripts/invert-tvos-icon.sh`](scripts/invert-tvos-icon.sh) | 逐像素 RGBA8 反色 tvOS 分层图标 `Assets.car` 并用 Xcode `actool` 原生重编 | macOS（Xcode） |
| [`scripts/fetch-fastpathsign.sh`](scripts/fetch-fastpathsign.sh) | 从锁定上游提交（`f1ebe52`）可复现构建宿主机 `vendor/fastPathSign`（已 gitignore） | macOS（clang + OpenSSL） |
| [`scripts/sign-coretrust.sh`](scripts/sign-coretrust.sh) | 宿主机批量 CoreTrust 签名：自动扫描 `.app`/`.ipa` 主程序 + `Frameworks/` + `*.dylib`，校验 `CDHash` 与 `TeamIdentifier=T8ALTGMVXN`，支持 `-o out.ipa` 重打包 | 仅 macOS 宿主机 |
| [`scripts/stage2-verify.sh`](scripts/stage2-verify.sh) | 冷重启后只读验收脚本（绝不自动重启；核查越狱态、trustcache、CDHash、CrashReporter 增量，可选 `--launch`） | macOS → Apple TV（SSH） |
| [`scripts/build-probe.sh`](scripts/build-probe.sh) | 编译干净室 `Demo.app` + 内嵌 `ProbeKit.framework` arm64 tvOS 诊断探针 | macOS（Xcode tvOS SDK） |
| [`scripts/install-probe.sh`](scripts/install-probe.sh) | 越狱态探针安装脚本（仅交互式 `sudo`，不保存密码） | macOS → Apple TV（SSH） |
| [`src/probe/`](src/probe/main.m) | 极简 tvOS 探针源码，完整记录构造函数、`csops`、内嵌框架调用、UIKit 生命周期、本地回环 HTTP 与心跳 | tvOS 17.0 arm64 |
| [`tests/run.sh`](tests/run.sh) | 本地与 CI 自动化门禁（`sh -n`、`shellcheck`、plist 校验、`--dry-run`、隐私/二进制防线、Markdown 断链、探针实编） | macOS / Linux CI |

---

## 真机实测亮点（Apple TV 4K / tvOS 17.0 `21J354`）

- **零 trustcache CoreTrust 签名**：宿主机批量签名后的多二进制应用（`TeamIdentifier=T8ALTGMVXN`）无需写入越狱 trustcache 即可正常运行，详见 [`docs/CORETRUST-BYPASS-VERIFIED.md`](docs/CORETRUST-BYPASS-VERIFIED.md)。
- **最小沙箱 entitlements 可用**：仅需 `application-identifier` + `com.apple.private.security.container-required`，无需越狱专属权限。
- **冷重启未越狱存活已实证**：在只读 SSV tvOS 17.0 上冷重启进入未越狱态后，`TrollStore.app` 与多二进制 CoreTrust 应用均可直接打开，详见 [`docs/REBOOT-VERIFICATION.md`](docs/REBOOT-VERIFICATION.md)。

---

## 环境准备

- **通用依赖（macOS / Linux）**：POSIX `sh`、`zip`/`unzip`、`tar`、`ar` 或 `dpkg-deb`、`python3`（Linux 下用于 plist 处理）。
- **macOS 完整版 Xcode**（`invert-tvos-icon.sh`、`build-probe.sh` 以及 `repack-ipa.sh` / `build-youtube-tvos.sh` 自动反色图标所需）：含 AppleTVOS SDK（`actool`、`clang`、`codesign`、`plutil`）。
- **OpenSSL + `pkg-config`**（仅 `fetch-fastpathsign.sh` 需要）：`brew install openssl@3 pkg-config`。
- **[`uv`](https://docs.astral.sh/uv/)**（仅 `build-youtube-tvos.sh` 调用 `tvos-cobalt-userscript` 时需要）。

---

## 全部脚本使用说明

所有脚本均支持 `-h` / `--help`，涉及写入或远端 SSH 的脚本均支持 `--dry-run` 预演。

### 1. 开源 `.deb` 转 `.ipa`（`scripts/deb2ipa.sh`）

自动提取 `/Applications/*.app`（清理 `.jbroot` 软链）并封装为可直接交由 `TrollStore TV` 安装的纯净 `.ipa`：

```sh
# 预演步骤
./scripts/deb2ipa.sh --dry-run /path/to/org.xbmc.kodi-tvos64.deb

# 转换 Kodi .deb 为 .ipa（--store 使用零压缩极速打包，适合大体积应用）
./scripts/deb2ipa.sh --store -o Kodi.ipa /path/to/org.xbmc.kodi-tvos64.deb
```

### 2. YouTube tvOS + TizenTube / SponsorBlock 构建（`scripts/build-youtube-tvos.sh`）

严格遵循 **BYOIPA**，仅处理**你本机自行解密的官方 IPA（`cryptid == 0`）**；完整 4 步获取与安装教程见 [`docs/APP-PACKAGING-GUIDE.zh-CN.md`](docs/APP-PACKAGING-GUIDE.zh-CN.md)：

```sh
# 预演构建流程
./scripts/build-youtube-tvos.sh --dry-run /path/to/YouTube-decrypted.ipa

# 构建并存版 YouTube TV IPA（默认开启图标反色，方便与原版区分）
./scripts/build-youtube-tvos.sh -o YouTubeTV-trollstore.ipa /path/to/YouTube-decrypted.ipa

# 关闭图标反色保留原图标（--no-invert-icon），或自定义/自托管油猴脚本 URL
./scripts/build-youtube-tvos.sh \
  --no-invert-icon \
  --userscript-url https://cdn.jsdelivr.net/npm/@foxreis/tizentube/dist/userScript.js \
  -o YouTubeTV-trollstore.ipa \
  /path/to/YouTube-decrypted.ipa
```

常用参数：`--bundle-id`、`--display-name`、`--app-name`、`--profile`、`--userscript-url`、`--fallback-url`、`--extra-csp`、`--invert-icon`（默认开启）/ `--no-invert-icon`、`--no-4k-patch`、`--no-hdr-patches`、`--store`、`-o`。

### 3. 通用本地 IPA 重打包与定制（`scripts/repack-ipa.sh`）

修改 Bundle ID / 桌面名称、默认开启 tvOS 图标反色（`--no-invert-icon` 关闭）、规范化标准沙箱权限：

```sh
./scripts/repack-ipa.sh \
  --bundle-id com.example.myapp.custom \
  --display-name "My App Custom" \
  --entitlements sandbox \
  -o MyApp-custom.ipa \
  /path/to/MyApp-unencrypted.ipa
```

常用参数：`--bundle-id`、`--display-name`、`--invert-icon` / `--no-invert-icon`、`--entitlements sandbox|preserve|<plist>`、`--allow-alt-video-decoder`、`--store`、`--dry-run`、`-o`。

### 4. 独立 tvOS 分层图标反色工具（`scripts/invert-tvos-icon.sh`）

逐像素 RGBA8 反色 tvOS `Assets.car`（解决 `CIColorInvert` 对 `gray gamma 22` 单色图标无效的问题），并调用 Xcode `actool` 原生重编：

```sh
./scripts/invert-tvos-icon.sh --dry-run -o /tmp/Assets-inverted.car /path/to/Assets.car
./scripts/invert-tvos-icon.sh -o Assets-inverted.car /path/to/Assets.car
```

### 5. 构建宿主机 `fastPathSign` 与批量 CoreTrust 签名（`scripts/fetch-fastpathsign.sh` + `scripts/sign-coretrust.sh`）

`fastPathSign` 必须在 **macOS 宿主机**运行（丢到 Apple TV 直接执行会报 `Killed: 9`）：

```sh
# 首次构建 vendor/fastPathSign（从锁定上游 f1ebe52 复现；--force 强制重建）
./scripts/fetch-fastpathsign.sh

# 预演模式（不修改文件）
./scripts/sign-coretrust.sh --dry-run --entitlements minimal path/to/App.app

# 使用最小沙箱权限批量签名（主程序 + Frameworks/ + *.dylib）并输出重打包 IPA
./scripts/sign-coretrust.sh --entitlements minimal -o SignedApp.ipa InputApp.ipa
```

> **重要提示**：若计划交由设备端 `TrollStore TV`（`trollstorehelper`）安装，**请勿**预先运行 `sign-coretrust.sh`，直接传入未签名或普通 ad-hoc 签名 IPA 即可。

### 6. 干净室 tvOS 诊断探针（`scripts/build-probe.sh` + `scripts/install-probe.sh`）

```sh
# 编译 Demo.app + 内嵌 ProbeKit.framework（tvOS arm64）
./scripts/build-probe.sh

# 预演或部署到已越狱 Apple TV（仅交互式 sudo，不保存密码）
./scripts/install-probe.sh --dry-run
DEVICE=192.0.2.10 ./scripts/install-probe.sh
```

### 7. 冷重启后只读验收（`scripts/stage2-verify.sh`）

默认完全只读，绝不自动重启设备：

```sh
# 预演远端命令
./scripts/stage2-verify.sh --dry-run

# 只读采集设备状态（越狱态、trustcache、Mach-O CDHash、CrashReporter 增量）
./scripts/stage2-verify.sh --device 192.0.2.10 --user mobile

# 可选拉起测试（仅在连接电视显示时使用）
./scripts/stage2-verify.sh --device 192.0.2.10 --launch
```

### 8. 本地自动化校验套件（`tests/run.sh`）

```sh
./tests/run.sh
```

---

## 技术文档导航

- [`docs/APP-PACKAGING-GUIDE.zh-CN.md`](docs/APP-PACKAGING-GUIDE.zh-CN.md) / [English](docs/APP-PACKAGING-GUIDE.md) — **应用打包与安装指南（`.deb` 转 `.ipa` 与 BYOIPA 自助构建流程）**（含 Kodi 数据无损迁移、YouTube BYOIPA 全流程与外部工具链接）
- [`docs/REBOOT-VERIFICATION.md`](docs/REBOOT-VERIFICATION.md) — 冷重启前防变砖核查清单、未越狱存活实证与排障笔记（`IOSurfaceRootUserClient`、Monochrome tvOS `Assets.car` 反色）
- [`docs/CORETRUST-BYPASS-VERIFIED.md`](docs/CORETRUST-BYPASS-VERIFIED.md) — 零 trustcache CoreTrust 签名实测数据（全权限 + 最小权限）
- [`docs/DEVICE-RECIPE.md`](docs/DEVICE-RECIPE.md) — 越狱态探针安装配方与排障对照表
- [`docs/UPSTREAM-FLOW-AUDIT.md`](docs/UPSTREAM-FLOW-AUDIT.md) — 上游 TrollStore 签名与安装流程源码审计
- [`docs/CONTAINER-BLACKLIST-NOTE.md`](docs/CONTAINER-BLACKLIST-NOTE.md) — `jbctl trustcache add` 容器路径黑名单绕过说明
- [`docs/evidence/probe-run.log`](docs/evidence/probe-run.log) 与 [`docs/evidence/probe-boot.log`](docs/evidence/probe-boot.log) — 干净室探针运行日志证据

---

## 致谢与第三方开源项目引用

以下第三方开源项目**均未打包或拷贝源码进本仓库**，仅按需在用户本机单独构建/调用、运行时通过 URL 加载或在文档中作为外部生态工具引用：

| 项目 | 作者 / 维护者 | 许可证 | 作用 |
| --- | --- | --- | --- |
| [`opa334/TrollStore`](https://github.com/opa334/TrollStore) | Lars Fröder (`opa334`) | MIT | CoreTrust 签名与安装流程架构参考 |
| [`straight-tamago/TrollStore-tvOS`](https://github.com/straight-tamago/TrollStore-tvOS) | `straight-tamago` | MIT | 由 `scripts/fetch-fastpathsign.sh` 从锁定提交 `f1ebe52` 本地编译的 `Exploits/fastPathSign` 上游源码 |
| [`opa334/ChOma`](https://github.com/opa334/ChOma) | Lars Fröder、`@alfiecg_dev`、`@LinusHenze`、Google TAG 及贡献者 | MIT | `fastPathSign` 与 `trollstore-tv` 所使用的 Mach-O / CoreTrust 签名库 |
| [`reisxd/TizenTube`](https://github.com/reisxd/TizenTube) | Reis Can (`reisxd`) | GPL-3.0 | 默认运行时拉取的 YouTube TV 去广告与增强油猴脚本（npm `@foxreis/tizentube` via jsDelivr），不入库 |
| [`reisxd/TizenTubeCobalt`](https://github.com/reisxd/TizenTubeCobalt) | Reis Can (`reisxd`) | BSD-3-Clause | `reisxd` 维护的 Cobalt 姊妹项目 |
| [`ajayyy/SponsorBlock`](https://github.com/ajayyy/SponsorBlock) | Ajay Ramachandran (`ajayyy`) 及贡献者 | GPL-3.0 / CC BY-NC-SA 4.0（API 数据库） | 社区广告/赞助片段跳过服务（[sponsor.ajay.app](https://sponsor.ajay.app)），由 TizenTube 在运行时集成 |
| [`ajayyy/DeArrow`](https://github.com/ajayyy/DeArrow) | Ajay Ramachandran (`ajayyy`) 及贡献者 | GPL-3.0 | 社区去标题党/缩略图净化服务（[dearrow.ajay.app](https://dearrow.ajay.app)），由 TizenTube 在运行时集成 |
| [`comicchang/tvos-cobalt-userscript`](https://github.com/comicchang/tvos-cobalt-userscript) | Comic Chang | MIT | `scripts/build-youtube-tvos.sh` 调用的洁净室 ARM64 Cobalt 油猴加载器补丁工具 |
| [`majd/ipatool`](https://github.com/majd/ipatool) | Majd Alfhaily (`majd`) | MIT | 文档引用的外部 CLI，用于以本人 Apple 账号下载官方 `.ipa` |
| [`EthanArbuckle/fairplay-decrypt`](https://github.com/EthanArbuckle/fairplay-decrypt) | Ethan Arbuckle | GPL-3.0 | 仅作外部文档参考链接的第三方 FairPlay 解密项目，本仓库零代码引入 |
| [`xbmc/xbmc`](https://github.com/xbmc/xbmc)（[Kodi](https://kodi.tv/)） | XBMC Foundation / Team Kodi | GPL-2.0+ | 文档与 `.deb` 转 `.ipa` 流程中引用的开源 tvOS 媒体中心 |
| [`owngoal-dev/Relaxin`](https://github.com/owngoal-dev/Relaxin) 与 [`roothide`](https://github.com/roothide) | owngoal-dev、roothide | MIT | 探针测试与首次引导所用的 tvOS 17 RootHide 越狱环境 |
| [`ProcursusTeam/ldid`](https://github.com/ProcursusTeam/ldid) | Procursus Team | GPL-3.0 | 文档引用的外部设备端权限检查工具 |
| [`openssl/openssl`](https://github.com/openssl/openssl) | OpenSSL Project | Apache-2.0 | 本机编译 `vendor/fastPathSign` 时的加密库依赖 |
| [`astral-sh/uv`](https://github.com/astral-sh/uv) | Astral | MIT / Apache-2.0 | `scripts/build-youtube-tvos.sh` 运行 `cobalt-patcher` 的 Python 环境工具 |

关联仓库：
- [`comicchang/trollstore-tv`](https://github.com/comicchang/trollstore-tv) — tvOS 17.0 设备端 CoreTrust 永久签名安装器本体（`TrollStore.app` + `trollstorehelper`）。
- [`comicchang/trollstore-lite-tv`](https://github.com/comicchang/trollstore-lite-tv) — 面向已越狱 tvOS 17.x 的洁净室信任缓存安装器。

---

## 安全边界与开源协议

- 所有脚本默认只读、绝不自动重启设备、绝不写入 `/Applications`、绝不内置密码/私钥或第三方编译二进制。
- 采用 [MIT](LICENSE) 协议；详见 [NOTICE](NOTICE)、[CHANGELOG.md](CHANGELOG.md)、[CONTRIBUTING.md](CONTRIBUTING.md) 与 [SECURITY.md](SECURITY.md)。
