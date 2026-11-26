# CoreTrust bypass 链实测（survive-reboot 技术前提）

## 结论

在本机 tvOS 17.0 上，**CoreTrust bypass 签名（`fastPathSign --entitlements`）足以让应用被 AMFI 接受并运行，且完全不需要写入 jailbreak trustcache**。

这与此前的「ldid 双哈希 ad-hoc + `jbctl trustcache add`」是两条独立可用路径：

| 路径 | 是否写 trustcache | 依赖 jailbreak 常驻 | 用途 |
|---|---|---|---|
| ldid 双哈希 ad-hoc + trustcache | 是（每个二进制 1 槽位） | 是 | 当前会话快速验证；trustcache 重启后是否存活未验证 |
| CoreTrust bypass（fastPathSign） | **否** | **否**（只需签名链被 AMFI 接受） | **survive-reboot 的技术前提** |

## 实测证据

### 探针 `com.tsltv.verify.demo`

- 签名：`fastPathSign --entitlements <ent> Demo` / `ProbeKit`
- 签名后特征：`Authority=TrollStore 2 iPhone Certification Authority` + `Apple iPhone OS Application Signing` 链，`TeamIdentifier=T8ALTGMVXN`
- trustcache：**634 → 634，未变化**；探针 cdhash `c65b9d06…` **不在** trustcache
- 启动：`uiopen --bundleid com.tsltv.verify.demo` 返回 0，进程存活 PID 33155
- 日志完整：
  ```
  ctor pid=33155 uid=501
  stage=main → stage=csops rc=0 flags=0x22007305 → stage=framework_ok
  → stage=did_finish_launching → stage=layout_complete (1920x1080)
  → stage=view_did_appear → stage=first_frame → stage=did_become_active
  → stage=http_8787 status=200 bytes=7181 error=none → stage=heartbeat_2s
  ```
- 新增 `Demo-*.ips`：0

### `com.aapl.relaxin.test`

- 5 个二进制（RelaxinTV、RelaxinEngine、libjailbreak、libchoma、libxpf）全部用 `fastPathSign` 在宿主机重签后回推
- 签名后 cdhash / team / 缓存命中：

  | 二进制 | cdhash | team | trustcache 命中 |
  |---|---|---|---|
  | RelaxinTV | `95b2feae…` | T8ALTGMVXN | 0 |
  | RelaxinEngine | `fd3d715e…` | T8ALTGMVXN | 0 |
  | libjailbreak.dylib | `8aef9a7a…` | T8ALTGMVXN | 0 |
  | libchoma.dylib | `0cb42ec1…` | T8ALTGMVXN | 0 |
  | libxpf.dylib | `a763fe34…` | T8ALTGMVXN | 0 |

- trustcache：634 → 634 未变化
- 启动：`uiopen --bundleid com.aapl.relaxin.test` 返回 0，进程存活 PID 33622
- 新增 `RelaxinTV-*.ips`：0

## 最小 entitlements 变体（阶段 2 风险显著降低）

除上面的 `platform-application`/`no-sandbox`/`no-container` 组合外，还验证了**不带任何越狱专属 entitlement** 的最小集：

```xml
<key>application-identifier</key><string>com.tsltv.verify.demo</string>
<key>com.apple.private.security.container-required</key><string>com.tsltv.verify.demo</string>
```

- 签名：宿主机 `fastPathSign --entitlements ent-min.plist`（主程序 + ProbeKit）
- trustcache：**634 → 634 未变化**
- 启动：成功，进程存活 PID 34806
- 因为此时 app 被正常沙箱化，`/var/tmp` 写入被拒；探针已加 `NSTemporaryDirectory()` 回退，日志落在数据容器的 `tmp/probe.log`：
  ```
  stage=main home=/var/mobile/Containers/Data/Application/<CONTAINER-UUID>
  stage=csops rc=0 flags=0x22007305
  stage=framework_ok / did_finish_launching / layout_complete 1920x1080
  stage=view_did_appear / first_frame / did_become_active
  stage=http_8787 status=200 bytes=7181 / heartbeat_2s
  ```
- 新增 `Demo-*.ips`：0

结论：CoreTrust bypass 链**不需要越狱专属 entitlements** 即可运行。阶段 2 的主要剩余不确定性因此收敛为「重启后 AMFI 是否仍接受该签名链」，而不是权限集本身。

## 注意：设备端 fastPathSign 不可直接运行

把宿主机 `fastPathSign` 拷到设备执行会得到 `Killed: 9`（该二进制自身未获信任）。
正确做法：**在宿主机签名，再把签好的二进制回推设备**。

## 与上游语义的关系

上游 `RootHelper.signApp` 的顺序是：
1. 逐个 bundle 的 Info.plist → `signAdhoc`（ldid，带 entitlements）
2. `signAdhoc(appPath, nil)` → `ldid -s` 递归整包
3. 对每个 Mach-O → `apply_coretrust_bypass`

我们验证的第 2 条路径等价于「步骤 3 单独执行」：`fastPathSign` 自带 adhoc 前置处理，因此对未签名二进制也能完成 bypass。
这与上游并不冲突，只是**跳过了 ldid 阶段**；本项目在独立工程中把它作为无 trustcache 依赖的验收路径。

## 后续冷重启验证结果

冷重启后的未越狱态存活验证已于 2026-11-26 实测通过（`TrollStore.app` 与多二进制 CoreTrust 签名应用均可在未越狱态直接打开），完整验收记录与排障笔记见 [`REBOOT-VERIFICATION.md`](REBOOT-VERIFICATION.md)。
