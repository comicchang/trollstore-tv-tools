# TrollStore 上游安装/签名流程与错误做法审计

日期：2026-11-25

本文只对照上游 TrollStore 源码与当前独立工程的实际做法；不把宿主机工具的“命令返回成功”误当成设备上的安装/信任成功。文中的路径均为源码路径；源码结论给出文件和行号范围，二进制证书文件另注明其为二进制资产。

## 1. 上游真实调用链

### 1.1 从 TrollStore UI 到 RootHelper

1. `TrollStore/TSApplicationsManager.m:99-127` 的 `installIpa:force:log:` 组装 `install`、`force`、`custom`/`installd` 和 IPA 路径参数，并通过 `spawnRoot(rootHelperPath(), ...)` 调用 root helper。这里的 `installIpa` 是 UI 侧包装，不是解包和签名的实现。
2. RootHelper 命令行入口在 `RootHelper/main.m:1600-1630`：命令为 `install` 时读取 `force`、`installd`、`skip-uicache`，最后调用 `installIpa(...)`。
3. `RootHelper/main.m:1190-1228` 的 `installIpa` 先检查 IPA 可访问性（166），创建临时目录，解包 IPA（解包失败为 168），再调用 `installApp(tmpPackagePath, YES, force, NO, useInstalldMethod, skipUICache)`，并原样返回其返回值。

因此实际链路是：

```text
TSApplicationsManager installIpa
  -> trollstorehelper install
    -> RootHelper installIpa
      -> extract
      -> installApp
        -> signApp（当 sign == YES）
          -> signAdhoc（每个 bundle 主可执行文件）
          -> signAdhoc（整个 app bundle）
          -> apply_coretrust_bypass（每个可执行文件）
        -> MCM/LSDB 安装或更新
        -> marker、权限修复、registerPath/uicache
```

### 1.2 `installApp` 的关键行为和返回码

`RootHelper/main.m:872-1094` 的 `installApp` 先从 `Payload` 找到 `.app`（167），读取 bundle id（176），拒绝系统/不可变 bundle id（179），检查 `Info.plist`（172），然后调用 `signApp`。签名失败时，182 和 184 被记录为非致命状态，其余返回值立即向上返回。安装阶段通过 MCM（必要时先用 `LSApplicationWorkspace` 做占位安装）创建/复制容器；更新已有容器时会检查是否为 TrollStore 应用，否则 171。复制失败为 178，写 marker 失败为 177，注册/uicache 失败为 181（见 `RootHelper/main.m:872-1094`）。

上游 UI 的错误码文字在 `TrollStore/TSApplicationsManager.m:19-95`；安装控制器把 171 视为可 force 重试，把 182/184 视为安装成功但需要提示，分别见 `TrollStore/TSInstallationController.m:25-75`。

要求的返回值含义如下：

| 返回值 | 含义 | 证据 |
|---|---|---|
| 166 | IPA 不存在或不可访问 | `RootHelper/main.m:1190-1200`；`TSApplicationsManager.m:24-27` |
| 167 | IPA/Payload 中找不到应用 bundle | `RootHelper/main.m:872-878`；`TSApplicationsManager.m:28-31` |
| 171 | 同 bundle id 已安装，但不是 TrollStore 应用（或为空容器之外的非 TrollStore 应用），且未 force | `RootHelper/main.m:922-941`；`TSApplicationsManager.m:38-41` |
| 172 | 应用没有可读取的 `Info.plist` | `RootHelper/main.m:888-891`；`TSApplicationsManager.m:42-45` |
| 173 | 无法使用 ldid（`isLdidInstalled` 失败） | `RootHelper/main.m:506-508`；`TSApplicationsManager.m:46-49` |
| 174 | 主可执行文件不存在 | `RootHelper/main.m:552-557`；`TSApplicationsManager.m:50-53` |
| 175 | ldid 返回非零，签名失败 | `RootHelper/main.m:506-549`；`TSApplicationsManager.m:54-61` |
| 176 | `Info.plist` 缺少 `CFBundleIdentifier`/`CFBundleExecutable` 等必要值 | `RootHelper/main.m:552-555, 878-882`；`TSApplicationsManager.m:62-65` |
| 180 | 主 Mach-O 是加密的，不能做 CoreTrust bypass | `RootHelper/main.m:720-748`；`TSApplicationsManager.m:69-72` |
| 182 | 安装成功，但需要启用 Developer Mode（非致命） | `RootHelper/main.m:797-801, 1062-1074`；`TSApplicationsManager.m:73-76` |
| 184 | 主程序可用，但其他 binary（扩展、插件等）加密（非致命警告） | `RootHelper/main.m:748-759, 1077-1081`；`TSApplicationsManager.m:77-80` |
| 185 | CoreTrust bypass 返回非零，签名失败 | `RootHelper/main.m:748-761`；`TSApplicationsManager.m:81-84` |

补充区分：`installApp` 的 170 是创建容器失败、177 是 marker 写入失败、178 是复制 bundle 失败、181 是注册/uicache 失败、183 是启用 Developer Mode 失败；这些也在 `RootHelper/main.m:872-1094` 与 `TSApplicationsManager.m:32-95` 中有对应实现。

## 2. `signApp` 的真实三段式

上游非 embedded、非 `TROLLSTORE_LITE` 的实现位于 `RootHelper/main.m:552-871`。它不是“拿一个宿主机签名器直接签整个 IPA”，而是以下三段（第三段含两个连续动作）：

### 第一段：逐个 bundle 读取 `Info.plist` 并按 binary 签名

`RootHelper/main.m:577-705` 枚举 app bundle 中的每一个 `Info.plist`。对每个 bundle：

- 读取 `CFBundleIdentifier` 和 `CFBundleExecutable`，定位该 bundle 的主可执行文件（`main.m:577-593`）。
- `FMWK` framework 暂不在这段处理（`main.m:595-599`）。
- 从 binary 提取原 entitlements；如果是 app 的主程序且原本没有 entitlements，使用 fallback：`application-identifier = TROLLTROLL.*`、`com.apple.developer.team-identifier = TROLLTROLL`、`get-task-allow = true`、keychain groups `TROLLTROLL.*` 与 `com.apple.token`（`main.m:601-629`）。
- 按 CoreTrust 容器规则处理 `com.apple.private.security.container-required`：默认需要容器；若既没有 `no-container` 也没有 `no-sandbox`，将其值写为该 bundle 的 bundle id（`main.m:631-696`）。
- 调用 `signAdhoc(bundleMainExecutablePath, entitlementsToUse)`（`main.m:701-706`）。

这里的 `signAdhoc` 是 `RootHelper/main.m:506-549` 的 ldid 包装：有 entitlements 时把 plist 写到临时文件并执行 `ldid -S<plist> <binary>`；没有 entitlements 时执行 `ldid -s <binary>`。ldid 不存在返回 173，ldid 非零返回 175。

### 第二段：整包递归签名

第一段完成后，上游执行 `signAdhoc(appPath, nil)`（`RootHelper/main.m:711-714`）。注释明确说明这里依赖 ldid 对整个 bundle 的递归签名，用来覆盖 bundle 中其余需要签名的内容；失败仍返回 175。

### 第三段：对每个可执行文件做 CoreTrust bypass

随后重新枚举 bundle；对每个可解析为 Mach-O 的文件，取 preferred slice，复制到临时文件，调用 `apply_coretrust_bypass`，成功后再覆盖原文件（`RootHelper/main.m:716-793`）。主程序的加密错误是 180；其他 binary 加密只产生 184 警告；bypass 其他失败是 185。

上游 `fastPathSign` 的宿主机入口也体现同一顺序：先 `codesign_sign_adhoc`，再提取 slice 并 `apply_coretrust_bypass`，见 `Exploits/fastPathSign/src/main.m:80-125`。但设备上真正可复现的实现仍应按 RootHelper 的 ldid + trustcache 链路执行，不能把宿主机 fastPathSign 的返回 0 当成设备可用。

## 3. Entitlements 规则

### 3.1 上游规则

- 主程序没有原 entitlements 时，fallback 是 `TROLLTROLL.*` / `TROLLTROLL`，并且启用 `get-task-allow` 与 keychain groups（`RootHelper/main.m:601-629`）。
- `com.apple.private.security.container-required` 默认需要容器；如果没有 `com.apple.private.security.no-container` 和 `com.apple.private.security.no-sandbox`，就写入当前 bundle 的 bundle id（`RootHelper/main.m:631-696`）。
- `itemId=995367539` 在遍历每个 `Info.plist` 时写入，随后原子写回该 plist（`RootHelper/main.m:577-584`）。这不是只给 app 根目录写一次，而是每个找到的 bundle plist 都写。
- TrollStore 本身的静态 entitlements 在 `TrollStore/entitlements.plist:1-39`，包含 `application-identifier=com.opa334.TrollStore`、`platform-application`、no-sandbox、容器/安装相关私有权限等；TrollStore 的构建通过 `TrollStore/Makefile:1-18` 的 `TARGET_CODESIGN` 与 `TrollStore_CODESIGN_FLAGS` 使用该文件。
- TrollStore Lite 分支还会把 `jb.pmap_cs_custom_trust` 设为 `PMAP_CS_APP_STORE`（`RootHelper/main.m:698-702`）；这是 Lite 专用分支，不能误当成上游完整 CoreTrust 流程。

### 3.2 本工程当前生产风格

典型越狱态安装脚本的 `gen_ent` 会生成 bundle id 对应的 `application-identifier`（不带 Team 前缀）、`get-task-allow`、`platform-application`、no-sandbox/no-container、`container-required=false` 以及网络权限；`sign_one` 实际命令是：

```sh
ldid -S"$2" -Cadhoc -Hsha1 -Hsha256 "$1"
```

`trust_one` 位于 `:103-130`，优先直接 `jbctl trustcache add`；若 app bundle 路径被黑名单，则复制到 `/rootfs/var/tmp` 绕道，并将可能被 jbctl patch 的文件写回原路径、设为 755。这就是本文结论中“生产 tsltv 风格”的精确定义。

## 4. CoreTrust bypass 的语义与 TeamID

`Exploits/fastPathSign/src/coretrust_bug.c:229-343` 的 `apply_coretrust_bypass` 语义如下：

1. 加密 Mach-O 返回 2；object/dSYM 返回 3（`coretrust_bug.c:229-252`）。
2. 读取 code signature。没有可解析的 signature 时打印 `Error: no code signature found, please fake-sign the binary at minimum before running the bypass.` 并返回 -1（`coretrust_bug.c:254-261`）。因此**必须先有 ldid 伪签产生的可解析 code signature**。如果伪签阶段失败，ldid 路径是 175；如果已经进入 bypass 才发现无 signature，bypass 自身是 -1，`signApp` 对外映射为 185（`RootHelper/main.m:506-549, 748-761`）。这两个错误层次不能混淆。
3. 找到主 CodeDirectory；若存在 alternate CodeDirectory，则把 alternate 作为 real CD、删除原主 CD；否则主 CD 就是 real CD。real CD 必须是 SHA256，否则失败（`coretrust_bug.c:263-293`）。
4. 把 real CD 改成 `alternateCodeDirectory` 并追加到 superblob 尾部，同时把模板 `AppStoreCodeDirectory` 作为新的主 `CodeDirectory` 插入索引 0（`coretrust_bug.c:295-308`）。修改后的顺序是 App Store CD（SHA1）、requirements/entitlements、真实 CD（SHA256）。
5. TeamID 不是由 ldid 的 `--team-identifier` 决定：bypass 从 App Store CodeDirectory 读取 TeamID，再写入 real CD（`coretrust_bug.c:310-327`）。随后把 real CD flags 清零，去掉 ad-hoc 等问题 flags（`coretrust_bug.c:329-330`）。
6. 更新 load commands、CD page hashes 和签名 blob 后写回 Mach-O（`coretrust_bug.c:332-374`）。

所以，上游 bypass 后两个 CodeDirectory 的 TeamID 一致，Team 取自 App Store CD，而不是来自宿主机命令行传入的 Team。对真机样本而言，观察到的 Team 是 `T8ALTGMVXN`。这正是不能把 `--team-identifier T8ALTGMXVN` 当作绕过 TeamID 控制的根本原因。

ChOma 的设计说明也直接描述了这条链：伪签 → 替换 SHA1 App Store CD → 更新 SHA256 CD → 写入双 SignerInfo 签名，见 `ChOma/README.md:26-42`。

## 5. 证书来源与两条链的区别

审计要求涉及的证书来源是 `Victim/victim.p12` 与 `ChOma/cert.p12`，其目标 identity 记录为 `OU=T8ALTGMVXN`、`CN=TrollStore iPhone OS Application Signing`。`Victim/make_cert.sh:1-24` 明确生成 root CA、code-signing CA 和 application-signing leaf，并将 leaf 导出为 `victim.p12`，friendly name 为 `TrollStore iPhone OS Application Signing`；对 `Victim/victim.p12` 的证书主题检查结果为 `OU=T8ALTGMVXN`、`CN=TrollStore iPhone OS Application Signing`（二进制资产，无源码行号）。`ChOma/cert.p12` 是上游随仓库提供的二进制证书资产（无源码行号）；ChOma README 对其用途的说明在 `ChOma/README.md:26-42`。

需要特别区分两个历史 Team/CA 名称：

- `T8ALTGMVXN` 是这里的 CoreTrust bypass 链/应用签名 identity；`apply_coretrust_bypass` 的 App Store CD TeamID 才是最终写入 CD 的值（`coretrust_bug.c:310-327`）。
- `T8ALTGMXVN` 是 TrollStore 2 CA 链的 Team 名称。它不是通过 ldid 的 `--team-identifier` 就能注入 CoreTrust bypass 主 CD 的 Team；后者由 `AppStoreCodeDirectory` 提供（`coretrust_bug.c:295-327`）。

## 6. 我们此前的 5 个错误做法与纠正

### 错误 1：直接用宿主机 `fastPathSign` 签未签名 binary

错误：把宿主机 fastPathSign 当作设备安装链的全部，或者直接对没有 code signature 的 binary 做 bypass。宿主机入口虽然会先调用 `codesign_sign_adhoc`（`Exploits/fastPathSign/src/main.m:80-101`），但其 ad-hoc 签名与目标设备、目标 entitlements、信任缓存并不是同一件事；而 bypass 本身明确要求先 fake-sign（`coretrust_bug.c:254-261`）。

纠正：先对主程序和每个 framework binary 用 ldid 生成可解析的 ad-hoc code signature，再按 `tsltv` 的 `sign_one`（`src/cli/tsltv:93-96`）双哈希签名，并用 `trust_one`（`src/cli/tsltv:103-130`）写入设备 trustcache。不要把宿主机命令成功返回 0 当成设备信任成功。

### 错误 2：用 `--team-identifier` 试图指定 `T8ALTGMXVN`

错误：以为 ldid 的 TeamID 参数能控制最终 Mach-O 的 Team，或以为传 `T8ALTGMXVN` 就能得到所需 bypass 链。ldid 参数最多影响 ldid 自己产生的签名内容；fastPathSign/bypass 的 Team 取自 App Store CD。bypass 的 TeamID 代码明确在 `coretrust_bug.c:310-327`。

纠正：不要把 `--team-identifier` 当作 CoreTrust bypass 的 Team 控制接口；先弄清目标 App Store CD 的 TeamID 与实际信任缓存是否匹配，并使用已验证的生产链。

### 错误 3：把 TrollStore 2 CA（`T8ALTGMXVN`）与 CoreTrust bypass 链（`T8ALTGMVXN`）混为一谈

错误：看到 `T8ALTGMXVN` 就认为它是所有 TrollStore 签名/绕过场景的 Team，或看到 `T8ALTGMVXN` 就误以为需要伪造 TrollStore 2 CA。两者的来源、CD 注入路径和验证条件不同。

纠正：分别审计“证书链”和“CoreTrust CD 模板”两条链；`coretrust_bug.c:295-327` 决定最终 CD 顺序和 Team，`Victim/make_cert.sh:5-24` 与 `ChOma/cert.p12` 则是证书来源事实。

### 错误 4：单独用 `victim.p12` 执行 `ldid -K` 就认为可信

错误：只执行 `ldid -K./Victim/victim.p12` 会生成 TrollStore CA 链签名，但没有经过 CoreTrust bypass，也没有设备 trustcache；该签名不会因此自动被设备信任。上游构建也把 `victim.p12` 仅用于特定 persistence helper 注入（`Makefile:45-54`），不是普适安装流程。

纠正：需要按 `sign_one` + `trust_one` 的完整路径处理每个需要运行的 Mach-O；不能以 `-K` 签名命令返回成功代替 trustcache/安装注册/启动验证。

### 错误 5：把 rpath 写成 `@executable_path/../Frameworks`

错误：探针曾因 `@executable_path/../Frameworks` 导致 dyld 报 `Library not loaded: @rpath/ProbeKit.framework/ProbeKit`，在进入 `main` 前失败，因此没有 probe log。当前构建脚本已经改为 bundle 内部的 `@executable_path/Frameworks`（`scripts/build-probe.sh:25-33`）。

纠正：framework 必须位于 app bundle 内的 `Frameworks`，主程序的 rpath 使用 `@executable_path/Frameworks`；不要用 `../Frameworks` 假定 framework 位于 app bundle 外。

## 7. 结论

真机可用的独立链路不是“宿主机 fastPathSign + 一个 Team 参数”，而是：

```text
ldid 双哈希 ad-hoc 签名（SHA1 + SHA256）
  -> jbctl trustcache add（必要时 /rootfs/var/tmp 绕道）
  -> 生产 tsltv 风格 entitlements
  -> MCM 安装/注册
```

这与越狱态安装链路中 `gen_ent`、`sign_one`、`trust_one` 的语义一致。探针最终成功日志中出现的 `stage=main`、`stage=framework_ok`、`stage=http_8787 status=200` 等证据位于 `docs/evidence/probe-run.log:1-12`；这证明的是“签名 + 信任 + 启动/运行时”整条链成功，而不是证明某个单独宿主机签名命令成功。

审计结论不能反推为“CoreTrust bypass 在所有 tvOS 设备上都无需信任缓存”或“任意 CA/任意 Team 都能替代真实模板”。上游 bypass 的 CD/Team/签名更新逻辑见 `coretrust_bug.c:229-374`；生产 tsltv 的设备信任注入和路径黑名单绕道见 `src/cli/tsltv:103-130`。两者必须同时满足，才可复现已验证的启动结果。
