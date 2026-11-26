# Apple TV 真机探针安装配方

本文记录在 Apple TV 4K 真机上安装、签名、信任并拉起独立探针的已实证流程。
配套脚本：`scripts/install-probe.sh`；构建脚本：`scripts/build-probe.sh`。

## 1. 真机环境

| 项目 | 值 |
| --- | --- |
| 设备 | Apple TV 4K |
| 系统 | tvOS 17.0 |
| 地址 | `192.0.2.10` |
| 越狱 | roothide / Relaxin |
| SSH 用户 | `mobile` |
| 探针 Bundle ID | `com.tsltv.verify.demo` |
| 仓库 | `trollstore-tv-tools`（本仓库） |

`install-probe.sh` 使用以下参数，默认值即上表：

```sh
DEVICE=192.0.2.10
USER=mobile
BUNDLE_ID=com.tsltv.verify.demo
TSVERIFY=~/.local/share/tsltv-tools/tsverify
TARGET="$USER@$DEVICE"
REMOTE_DIR=/rootfs/private/var/tmp/tsltv-verify-demo
```

本地构建产物路径为：

```sh
ROOT=$(pwd)
APP_DIR="$ROOT/build/Demo.app"
```

设备端脚本中另有同名变量，表示设备上的路径：

```sh
APP_DIR="$REMOTE_DIR/Demo.app"
ENTITLEMENTS="$REMOTE_DIR/entitlements.plist"
MAIN_BINARY="$APP_DIR/Demo"
FRAMEWORK_BINARY="$APP_DIR/Frameworks/ProbeKit.framework/ProbeKit"
TSVERIFY="$REMOTE_DIR/tsverify"
```

`TSVERIFY` 可通过环境变量覆盖；`DEVICE`、`USER`、`BUNDLE_ID` 同样按环境变量参数化。
脚本支持 `--dry-run`，只打印命令，不连接设备、不创建或修改文件。

## 2. 探针工程结构

```text
trollstore-tv-tools/
├── src/probe/
│   ├── main.m
│   ├── ProbeKit.h
│   ├── ProbeKit.m
│   ├── demo.ent
│   └── Demo.app/
│       ├── Info.plist
│       ├── Assets.car
│       └── Frameworks/
│           └── ProbeKit.framework/
├── scripts/
│   ├── build-probe.sh
│   └── install-probe.sh
├── build/
│   └── Demo.app/
│       ├── Demo
│       ├── Info.plist
│       ├── Assets.car
│       └── Frameworks/
│           └── ProbeKit.framework/
│               └── ProbeKit
└── docs/
    ├── DEVICE-RECIPE.md
    ├── probe-run.log
    └── probe-boot.log
```

`build-probe.sh` 生成 `build/Demo.app`。构建脚本本身不安装、不隐式签名、不写生产路径。
安装脚本只使用设备临时目录 `/rootfs/private/var/tmp/tsltv-verify-demo`。

## 3. 七步安装配方

以下命令按固定顺序执行，顺序不可交换。第 1 步由 SSH 用户触发 `sudo` 清理；
第 2 步由 SSH 用户执行 `scp`；第 3 至第 7 步在设备端同一个 root shell 内执行。
`sudo` 凭据通过交互式提示获取，不写入任何文件。

### 步骤 1：清理并重建暂存目录

```sh
ssh -t "$TARGET" "sudo rm -rf '$REMOTE_DIR' && sudo mkdir -p '$REMOTE_DIR' && sudo chown '$USER' '$REMOTE_DIR' && chmod 700 '$REMOTE_DIR'"
```

清理必须发生在复制之前，避免旧二进制、旧 entitlements 或旧签名残留。

### 步骤 2：复制应用与 tsverify

```sh
scp -r "$APP_DIR" "$TSVERIFY" "$TARGET:$REMOTE_DIR/"
```

复制后设备上的路径为：

```text
/rootfs/private/var/tmp/tsltv-verify-demo/Demo.app
/rootfs/private/var/tmp/tsltv-verify-demo/tsverify
```

### 步骤 3：在设备端写入 entitlements

关键点：`application-identifier` 必须是不带 Team 前缀的 Bundle ID。
设备端完整 XML 如下：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>com.tsltv.verify.demo</string>
<key>get-task-allow</key><true/>
<key>platform-application</key><true/>
<key>com.apple.private.security.no-sandbox</key><true/>
<key>com.apple.private.security.no-container</key><true/>
<key>com.apple.private.security.container-required</key><false/>
</dict></plist>
```

写入位置为 `$ENTITLEMENTS`，即
`/rootfs/private/var/tmp/tsltv-verify-demo/entitlements.plist`。
不要写成 `TEAMID.com.tsltv.verify.demo`。

### 步骤 4：双哈希 ad-hoc 签名

分别对主程序和内嵌框架执行：

```sh
"$LDID" -S"$ENTITLEMENTS" -Cadhoc -Hsha1 -Hsha256 "$MAIN_BINARY"
"$LDID" -S"$ENTITLEMENTS" -Cadhoc -Hsha1 -Hsha256 "$FRAMEWORK_BINARY"
```

`-Hsha1` 与 `-Hsha256` 必须同时存在，缺一不可。只做单哈希会导致启动链路失败。
`ldid` 优先位于越狱根：

```sh
JB=$(ls -d /var/containers/Bundle/Application/.jbroot-* 2>/dev/null | head -n 1)
LDID="$JB/usr/bin/ldid"
```

若该路径不存在，安装脚本再回退到 PATH 中的 `ldid`。

### 步骤 5：注入 jailbreak trustcache

优先直接信任原文件：

```sh
JB=$(ls -d /var/containers/Bundle/Application/.jbroot-* 2>/dev/null | head -n 1)
JBCTL="$JB/usr/bin/jbctl"
```

若原路径被 `jbctl` 的 app bundle 黑名单拦截，则复制到 `/rootfs/var/tmp/tsltv-ts.*`，
对逻辑路径 `/var/tmp/<name>` 执行 `trustcache add`，成功后把可能被 patch 的文件写回原路径：

```sh
trust_one() {
    original_path=$1
    temporary_name=$2
    if "$JBCTL" trustcache add "$original_path" >/dev/null 2>&1; then
        chmod 755 "$original_path"
        return 0
    fi
    temporary_path="/rootfs/var/tmp/$temporary_name"
    rm -f "$temporary_path"
    cp "$original_path" "$temporary_path" || return 1
    if "$JBCTL" trustcache add "/var/tmp/$temporary_name" >/dev/null 2>&1; then
        rm -f "$original_path"
        cp "$temporary_path" "$original_path" || return 1
        chmod 755 "$original_path"
        rm -f "$temporary_path"
        return 0
    fi
    rm -f "$temporary_path"
    return 1
}

trust_one "$MAIN_BINARY" tsltv-ts.main
trust_one "$FRAMEWORK_BINARY" tsltv-ts.ProbeKit
```

两个二进制都必须完成信任注入。

### 步骤 6：通过 tsverify 完成 MCM 安装与注册

```sh
chmod 755 "$TSVERIFY"
DEPLOY_OUTPUT=$("$TSVERIFY" deploy /var/tmp/tsltv-verify-demo/Demo.app "$BUNDLE_ID")
printf '%s\n' "$DEPLOY_OUTPUT"
APP_PATH=$(printf '%s\n' "$DEPLOY_OUTPUT" | sed -n 's/.*app_bundle=\([^[:space:]]*\).*/\1/p' | tail -n 1)
```

`tsverify deploy` 必须以 root 运行。输入路径使用 `/var/tmp/tsltv-verify-demo/Demo.app`，
这是设备端工具要求的暂存路径；暂存目录本身位于 `/rootfs/private/var/tmp/tsltv-verify-demo`。
`DEPLOY_OUTPUT` 中的 `app_bundle=` 是后续 `uicache -p` 要使用的安装后路径。

### 步骤 7：注册并拉起

```sh
uicache -p "$APP_PATH"
uiopen --bundleid "$BUNDLE_ID"
```

`uicache` 使用步骤 6 解析出的 `$APP_PATH`，不要再用源路径。
`uiopen` 返回成功只表示 LaunchServices 接受了请求，不等于进程已进入 `main`；
最终判据必须依据下面的日志和进程证据。

## 4. 两次失败的根因

### 4.1 第一次：rpath 指向错误目录

初始构建把 rpath 写成了：

```text
@executable_path/../Frameworks
```

主程序位于 `Demo.app/Demo`，内嵌框架实际位于 `Demo.app/Frameworks/ProbeKit.framework`。
`@executable_path/..` 会跳出 app bundle，dyld 因找不到框架直接报：

```text
Library not loaded: @rpath/ProbeKit.framework/ProbeKit
```

进程在进入 `main` 之前就失败，因此不会出现 `probe.log`。
正确值为：

```text
@executable_path/Frameworks
```

`scripts/build-probe.sh` 已按此修正。

### 4.2 第二次：误把问题归因于 T8 证书链

第二次拉起失败曾被误判为需要 TrollStore 2 的 T8/TrollStore 2 证书链。
实测可用路径并不需要 T8 证书，而是：

1. `ldid` 双哈希 ad-hoc 签名；
2. jailbreak `trustcache` 注入；
3. 生产 `tsltv` 风格的 entitlements（`application-identifier` 不带 Team 前缀）。

单哈希 ad-hoc、Team 前缀或不完整的 entitlements 都会导致进程无法进入 `main`。
两次失败都不是截图、休眠或 LaunchServices 问题。

## 5. 验证判据

### 5.1 `probe.log` 期望节点

正常拉起的 `/rootfs/private/var/tmp/tsltv-probe.log` 至少应包含：

```text
stage=main
stage=csops
stage=framework_ok
stage=did_finish_launching
stage=layout_complete
stage=view_did_appear
stage=first_frame
stage=http_8787 status=200
stage=heartbeat_2s
stage=did_become_active
```

同时检查 `/rootfs/private/var/tmp/tsltv-probe-boot.log`：

```text
ctor pid=<pid> uid=501
```

该 `pid` 应与 `probe.log` 中的 `pid` 一致，证明构造函数和主程序属于同一进程。

### 5.2 进程存活

以日志中的 `pid` 为准检查进程，而不是只相信 `uiopen` 的返回码。
`heartbeat_2s` 说明进程至少存活到心跳节点；仍需在采集日志时确认该 PID 仍存在。
如果进程已退出但日志完整，应继续查看 CrashReporter，而不能判定为启动成功。

### 5.3 CrashReporter 增量口径

在拉起前记录 CrashReporter 目录中 `.ips` 文件名与时间快照，拉起并等待数秒后再次记录：

- 只有启动后新出现、且属于 `Demo` 或 `com.tsltv.verify.demo` 的 `.ips` 才算本次失败。
- 启动前已存在或重复计数的旧 `.ips` 不算。
- 日志完整、进程存活且没有新增 `.ips`，才可判定本次运行通过。
- 出现新 `.ips` 时，以其中的异常类型、终止原因和崩溃线程作为下一步排查依据。

## 6. 失败排查表

| 现象 | 含义 | 下一步 |
| --- | --- | --- |
| dyld 报 `Library not loaded: @rpath/ProbeKit.framework/ProbeKit` | 主程序找不到内嵌框架，通常是 rpath 错或打包漏文件 | 检查 `build/Demo.app/Frameworks/ProbeKit.framework/ProbeKit` 是否存在；确认主程序 `LC_RPATH` 为 `@executable_path/Frameworks`，不是 `@executable_path/../Frameworks`；重新运行 `scripts/build-probe.sh` |
| 没有 `probe.log` | 进程未进入 `main`，可能停在 dyld、签名、信任或 LaunchServices 之前 | 先看 `tsltv-probe-boot.log` 是否有 ctor；检查 ldid 双哈希、`jbctl trustcache add` 是否成功、rpath 是否正确，并查看启动后新增的 CrashReporter `.ips` |
| `probe-boot.log` 只有 ctor，没有 `stage=main` | 构造函数已执行，进程在进入 `main` 前退出或崩溃 | 检查新增 `.ips`、进程退出原因、内嵌框架加载和代码签名；不要仅凭 ctor 判定成功 |
| `http_8787` 不为 200 | 应用可能已进入 UI 生命周期，但探针 HTTP 服务未正常响应 | 检查 8787 端口监听和 `127.0.0.1:8787` 的响应、服务启动阶段日志、端口占用和网络权限；对照 `stage=http_8787 status=200` 的完整日志 |

补充：如果 `uicache -p` 或 `uiopen` 返回非零，先保留命令输出和 CrashReporter/日志证据，
再检查 `APP_PATH` 是否来自本次 `deploy` 的 `app_bundle=`，避免对错误的安装路径执行缓存刷新。
