# 设备侧新发现：jbctl trustcache add 的 app 容器路径黑名单

## 现象

对位于 app 容器内的二进制直接执行 `jbctl trustcache add <path>`：

- 返回码 **0（假成功）**
- 但 `jbctl trustcache info` 中**查不到**该 cdhash
- 运行结果仍是 `code signature invalid (errno=1)`

对位于 `/rootfs/private/var/tmp/` 或 `/rootfs/var/tmp/` 的二进制，同样的直接调用则**能真正写入**缓存。

## 结论

`jbctl trustcache add` 对 `/var/containers/Bundle/Application/**`（及其 `/private/var/containers/...` 别名）存在**静默路径黑名单**：调用成功但不落盘。

在基于 RootHide 的越狱环境下，标准绕过思路是：
先尝试原路径，失败则复制到 `/rootfs/var/tmp` 再 add，并把 **jbctl 可能就地 patch 后的文件写回原路径**。

## 正确配方（已在真机验证）

对 app 容器内的每个可执行文件：

1. `cp -p <target> /rootfs/var/tmp/tsltv-rx-<basename>`
2. `ldid -S<ent> -Cadhoc -Hsha1 -Hsha256 /rootfs/var/tmp/tsltv-rx-<basename>`
3. `jbctl trustcache add /var/tmp/tsltv-rx-<basename>`
4. **重新读取** `/rootfs/var/tmp/tsltv-rx-<basename>` 的 cdhash，确认 `jbctl trustcache info` 能命中
5. 只有命中才把该文件写回原路径（`rm -f <target>; cp -p <tmp> <target>; chmod 755 <target>`）
6. 删除临时文件

第 4 步不可省略：jbctl 在 add 过程中会就地 patch 文件并重算 cdhash，若跳过命中校验就写回，会得到「文件 cdhash 与缓存不一致」的假成功。

## 对 RelaxinTest 的应用

`com.aapl.relaxin.test` 的 `RelaxinTV`、`Frameworks/RelaxinEngine.framework/RelaxinEngine`、
`libjailbreak.dylib`、`libchoma.dylib`、`libxpf.dylib` 全部按上述配方处理后：

- 5 个 cdhash 全部命中 trustcache
- `uiopen --bundleid com.aapl.relaxin.test` 拉起成功，进程存活
- launchd 注册 `UIKitApplication:com.aapl.relaxin.test`
- 无新增 CrashReporter `.ips`
- 无 basebin/bootstrap 写入副作用
