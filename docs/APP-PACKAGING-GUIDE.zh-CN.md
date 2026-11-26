# 应用打包与安装指南（`.deb` 转 `.ipa` 与 BYOIPA 工作流）

[English](APP-PACKAGING-GUIDE.md) | **简体中文**

本指南说明如何在本机将**开源 `.deb` 安装包**或**本人合法获取的本地 `.ipa`（Bring Your Own IPA）**处理为可直接由 **[`trollstore-tv`](https://github.com/comicchang/trollstore-tv)** 安装的 tvOS `.ipa`，使应用在冷重启回到未越狱态后仍可直接运行。

> **合规声明**：本仓库**仅包含原创打包、签名与图标处理脚本**，**不分发**任何第三方专有 `.ipa`、版权二进制、品牌图标或 DRM 解密代码。下文提及的所有第三方工具均仅作为独立外部上游项目提供链接。

---

## 图标反色开关（默认开启）

[`scripts/repack-ipa.sh`](../scripts/repack-ipa.sh) 与 [`scripts/build-youtube-tvos.sh`](../scripts/build-youtube-tvos.sh) 在 macOS 上（检测到 Xcode `actool` 且包内存在 `Assets.car` 时）**默认开启 tvOS 图标反色**，方便在 Apple TV 主屏上将自定义构建与 App Store 原版一眼区分开。

如需保留原始图标不变，只需附加 `--no-invert-icon` 参数即可关闭。

---

## 工作流 A：开源 `.deb` 包转换（以 Kodi tvOS 为例）

许多开源 tvOS 应用（如 [Kodi](https://github.com/xbmc/xbmc) / [kodi.tv](https://kodi.tv/)，GPL-2.0+）官方直接发布面向 `/Applications/*.app` 的 `.deb` 安装包。

### 1. 下载官方 `.deb`

从上游项目官方发布页下载 tvOS `.deb` 包（例如 `org.xbmc.kodi-tvos64` v21.3）。

### 2. 在本机转换为 `.ipa`

```sh
./scripts/deb2ipa.sh --store -o Kodi.ipa /path/to/kodi.deb
```

### 3. 通过 TrollStore TV 安装

使用设备端 `TrollStore`（`trollstorehelper install`）安装 `Kodi.ipa`。`trollstorehelper` 会自动用内置 ChOma 对主程序、内嵌 `.appex` 插件和全部插件 `.dylib` 完成 CoreTrust 签名（`TeamIdentifier=T8ALTGMVXN`），同时完整保留原生 `no-container` 与媒体权限。

### 4. 无损迁移已有 Kodi 用户数据（从越狱版迁移）

若此前在 RootHide 越狱环境下运行过 Kodi，其用户数据（`userdata/`、`addons/`、`.smb/`）位于越狱叠加目录：

```text
/var/containers/Bundle/Application/.jbroot-<ID>/var/mobile/Library/Caches/Kodi
```

由 TrollStore 原生安装的 `no-container=true` 版 Kodi 在**越狱与未越狱态下**统一读写系统真实路径：

1. 先完整备份原有 `Kodi` 目录。
2. 将其拷贝到真实系统路径 `/private/var/mobile/Library/Caches/Kodi`（RootHide SSH 下对应 `/rootfs/private/var/mobile/Library/Caches/Kodi`），并将属主设为 `mobile:mobile`。
3. 打开 Kodi 验证媒体库、插件与 SMB 共享源均完整保留。

---

## 工作流 B：YouTube tvOS + 上游 TizenTube / SponsorBlock（BYOIPA）

tvOS 版 YouTube 使用的是 Google 的 **Cobalt + Starboard + V8** HTML5 引擎而非 `WKWebView`。[`scripts/build-youtube-tvos.sh`](../scripts/build-youtube-tvos.sh) 将以下组件在用户本机串联：
- 你自己从本人账号合法获取并解密的 tvOS `.ipa`（**BYOIPA**）；
- 洁净室开源 ARM64 油猴加载器补丁工具 [`comicchang/tvos-cobalt-userscript`](https://github.com/comicchang/tvos-cobalt-userscript)（MIT）；
- 上游开源油猴脚本 **[`reisxd/TizenTube`](https://github.com/reisxd/TizenTube)**（GPL-3.0，npm `@foxreis/tizentube`；姊妹项目 [`reisxd/TizenTubeCobalt`](https://github.com/reisxd/TizenTubeCobalt)，BSD-3-Clause），在运行时集成 **[`ajayyy/SponsorBlock`](https://github.com/ajayyy/SponsorBlock)**（GPL-3.0 / API CC BY-NC-SA 4.0）与 **[`ajayyy/DeArrow`](https://github.com/ajayyy/DeArrow)**（GPL-3.0），直接通过 jsDelivr 拉取（**冷重启未越狱态下无需任何本地守护进程即可生效**；也可通过 `--userscript-url` 指向自建局域网地址）。以上上游脚本均不入库。

### 第 1 步：用本人 Apple 账号下载官方 IPA

使用开源工具 [`majd/ipatool`](https://github.com/majd/ipatool)（MIT）：

```sh
brew install ipatool
ipatool auth login
ipatool download --bundle-identifier com.google.ios.youtube --platform appletv --purchase -o YouTube-official.ipa
```

### 第 2 步：准备本地未加密 IPA（`cryptid == 0`）

设备端 `TrollStore` 需要未加密的 Mach-O 才能签名。本仓库**不包含**任何解密代码；如需对自己合法拥有硬件与账号的 IPA 做离线解密，请独立参考第三方开源项目 [`EthanArbuckle/fairplay-decrypt`](https://github.com/EthanArbuckle/fairplay-decrypt)（GPL-3.0）。

### 第 3 步：使用 `scripts/build-youtube-tvos.sh` 本地构建

```sh
# 先预演确认步骤（不修改文件）
./scripts/build-youtube-tvos.sh --dry-run /path/to/YouTube-decrypted.ipa

# 构建并存版 YouTube TV IPA（默认开启反色图标）
./scripts/build-youtube-tvos.sh \
  -o YouTubeTV-trollstore.ipa \
  /path/to/YouTube-decrypted.ipa

# 可选：关闭反色，保留原版 YouTube 图标
./scripts/build-youtube-tvos.sh \
  --no-invert-icon \
  -o YouTubeTV-trollstore.ipa \
  /path/to/YouTube-decrypted.ipa
```

脚本内部自动完成两步：
1. 调用 `cobalt-patcher`（校验 `cryptid == 0`，写入 ARM64 油猴加载与 CSP 放行跳板指向 TizenTube，保留 4K/VP9 HDR 门控，改写并存 Bundle ID `com.google.ios.youtube.tvos`）。
2. 调用 [`scripts/repack-ipa.sh`](../scripts/repack-ipa.sh) 附加 `--entitlements sandbox --allow-alt-video-decoder`（默认启用图标反色，传 `--no-invert-icon` 关闭），并将最终 CoreTrust 签名交给设备端 `TrollStore TV`。

### 第 4 步：通过 TrollStore TV 安装

```sh
# 通过设备端 TrollStore TV root helper 安装（RootHide SSH 下先拷入 /rootfs/private/var/tmp）
sudo /rootfs/private/var/containers/Bundle/Application/<TROLLSTORE-UUID>/TrollStore.app/trollstorehelper \
  install /private/var/tmp/YouTubeTV-trollstore.ipa
```

---

## 工作流 C：通用本地 tvOS IPA 定制（`scripts/repack-ipa.sh`）

适用于任意你本机已解密的 tvOS `.ipa` 或 `.app`：

```sh
# 改 Bundle ID/名称 + 默认开启图标反色 + 规范化标准沙箱权限
./scripts/repack-ipa.sh \
  --bundle-id com.example.myapp.custom \
  --display-name "My App Custom" \
  --entitlements sandbox \
  -o MyApp-custom.ipa \
  /path/to/MyApp-unencrypted.ipa

# 如需保留原图标，附加 --no-invert-icon
./scripts/repack-ipa.sh \
  --no-invert-icon \
  --bundle-id com.example.myapp.custom \
  --display-name "My App Custom" \
  --entitlements sandbox \
  -o MyApp-custom.ipa \
  /path/to/MyApp-unencrypted.ipa
```

> **重要注意事项**：
> - 常规应用请保持 `--entitlements sandbox`（切勿盲目强加 `platform-application` + `no-sandbox`，若缺少对应的 `com.apple.security.exception.iokit-user-client-class` 声明，tvOS 17 上可能触发 `Failed to create surface`）。
> - 准备交给设备端 `trollstorehelper` 安装的 IPA，**切勿**先运行 `scripts/sign-coretrust.sh` 预签名；Apple 设备端 Security 框架会拒绝重签已经带有 CoreTrust bypass 签名的 Mach-O（报 `errSecCSInternalError / -67048`）。
