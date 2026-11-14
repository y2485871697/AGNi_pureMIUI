# haydn / AGNi v7.10：Droidspaces 最小必需配置与 KABI 适配

## 范围与入口

- 目标源码基线：`7dc006fa2217dab1b30ce0a615980f6c5013667f`（任务指定的 AGNi v7.10，配置文件标注 Linux 5.4.297）。
- 配置入口：`arch/arm64/configs/agni_haydn_defconfig`，即 arm64 的 `agni_haydn_defconfig` Kbuild 目标。CI 必须使用这个入口并检查最终生成的 `.config`，不能只检查 defconfig 文本。
- 目标是给 haydn / HyperOS stockvendor 提供一个可供 GitHub 构建试验的最小改动，不是将下游内核改造成 Google GKI，也不是已验证可安装的发布版本。
- 不进行本地编译、模块加载或刷机。源码与用户原厂 5.4.274 内核不同；本改动不能证明与原厂 Android 14 vendor 的整体兼容性。

## 实际改动

`arch/arm64/configs/agni_haydn_defconfig`：

```text
CONFIG_PID_NS=y
CONFIG_POSIX_MQUEUE=y
CONFIG_POSIX_MQUEUE_SYSCTL=y
CONFIG_DEVTMPFS=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
```

`init/Kconfig` 已提供所需实现和依赖，无需修改：

- `PID_NS` 位于 `if NAMESPACES` 内；`NAMESPACES` 依赖 `MULTIUSER`。二者原本均为 `y`，`PID_NS` 不依赖 `USER_NS`。
- `POSIX_MQUEUE` 依赖 `NET`，原本已为 `y`。
- `POSIX_MQUEUE_SYSCTL` 是隐藏的 bool，在 `POSIX_MQUEUE && SYSCTL` 下默认 `y`；`SYSCTL` 原本已为 `y`。此处显式记录其自然生成的配套设置，不另加功能。
- `SYSVIPC=y`、`SYSVIPC_SYSCTL=y`、`IPC_NS=y` 原样保留，不套 SYSVIPC 补丁。
- 按 Droidspaces v7.2.0 的 GKI 5.4+ 最小清单补开 `DEVTMPFS` 与 `NETFILTER_XT_MATCH_ADDRTYPE`，分别提供设备文件系统与 addrtype 匹配支持。
- 不启用 `USER_NS`、`CGROUP_PIDS`、`FAIR_GROUP_SCHED` / `CFS_BANDWIDTH` 等可选功能，也不增加替代隔离机制。

`include/linux/sched/user.h`：将受 `CONFIG_POSIX_MQUEUE` 控制的 `mq_bytes` 从结构中部移动到已有的 `ANDROID_KABI_RESERVE(1)` 槽，用 `ANDROID_KABI_USE(1, unsigned long mq_bytes)` 表达；关闭 MQUEUE 时仍保留槽 1，槽 2 不变。

## 官方补丁来源与下游适配

唯一外部补丁参考为 Droidspaces-OSS **v7.2.0** 官方目录：

<https://github.com/ravindu644/Droidspaces-OSS/tree/v7.2.0/Documentation/resources/kernel-patches/GKI/below-kernel-6.12>

采用其中的字段迁移思路：

<https://github.com/ravindu644/Droidspaces-OSS/blob/v7.2.0/Documentation/resources/kernel-patches/GKI/below-kernel-6.12/002.5.10_or_lower_use_android_abi_padding_for_posix_mqueue.patch>

原补丁：`a0aa446ca326b5d26ac1dec057efd8c07d2bcbff`，作者及原 Signed-off-by 为 **lateautumn233 <lateautumn233@foxmail.com>**，日期 2024-01-27，主题为 `[GKI PATCH 3/4] GKI 5.10 or lower: use Android ABI padding for POSIX_MQUEUE user_struct fields`。这里记录原来源归属，不把原作者的签署冒充为本次提交签署。

没有整包套用 GKI 补丁。实际核对发现，本树 `user_struct` 已包含 `android_kabi.h`、预留槽 1/2，但没有官方补丁上下文中的 `ANDROID_OEM_DATA_ARRAY(1, 2)`。因此只删除旧 `mq_bytes` 声明并条件复用现有槽 1，不新增 OEM/vendor 数据，不复制已注释的废弃声明，也不重复槽 2。

## ABI 判断：哪些问题被处理，哪些没有

### POSIX MQUEUE：可复用现有 padding，但仅是局部 ABI 论证

本树 `include/linux/sched/user.h` 的原布局在 `epoll_watches` 后、`locked_shm` 前条件插入 `unsigned long mq_bytes`。直接开启 MQUEUE 会使 `locked_shm`、`unix_inflight`、`pipe_bufs`、`uidhash_node`、`uid`、`locked_vm`、`ratelimit` 等后续成员移动，并改变结构大小和涉及此类型的符号版本描述。

本次使用原本位于尾部的 64-bit 槽 1。arm64 上 `unsigned long` 为 64-bit，尺寸/对齐可容纳在既有 `u64` 槽内。`include/linux/android_kabi.h` 的 `_ANDROID_KABI_REPLACE`：

- 正常编译时生成覆盖原槽的 union，并以 `_Static_assert` 检查尺寸及对齐；不增加结构尾部空间，不移动已有成员。
- `__GENKSYMS__` 下展开为原预留字段，使 genksyms 看到的 `user_struct` 声明与原 MQUEUE 关闭配置保持一致。这不是关闭 CRC 检查。

槽 1 在本树此结构中尚未被其他字段消费。`kernel/user.c` 的 `alloc_uid()` 使用 `kmem_cache_zalloc()`；静态 `root_user` 未显式初始化的槽也为零。`ipc/mqueue.c` 继续通过 `u->mq_bytes` 计费，并在 `mq_lock` 下更新，无需改动 IPC 算法。

这支持“相对于同树、其余配置不变的 MQUEUE 关闭基线，保留这些已有成员的布局及该类型的 genksyms 表示”的源代码判断。尚未进行实际布局转储、CRC 比较，也不保证厂商模块没有私自使用该预留槽；它不是与原厂内核全量 ABI 相同的证明。

### task_struct 与 ipc_namespace：不需要额外补丁

- `include/linux/sched.h` 的 `task_struct` 中，`sysvsem` / `sysvshm` 受 `SYSVIPC` 控制，而 `SYSVIPC` 本来已开。此结构没有因本次 `PID_NS` / `POSIX_MQUEUE` 开关而新增的条件成员。保留其 Android vendor 数据和 KABI 槽，不挪动它们。
- `include/linux/ipc_namespace.h` 中 `mq_mnt`、`mq_queues_count`、`mq_queues_max`、`mq_msg_max`、`mq_msgsize_max`、`mq_msg_default`、`mq_msgsize_default` 在原树就无条件存在；IPC 和 SysV 字段也已存在。该结构本身没有可用 Android KABI 槽，但本次并不需要增加字段，所以不新增 padding 或伪造其 ABI。
- `ipc/namespace.c` 已调用 `mq_init_ns()`；打开 MQUEUE 后由原有 stub 切换到 `ipc/mqueue.c` 实现。`ipc/Makefile` 已有 MQUEUE 和 sysctl 构建规则。

### PID_NS：布局没有对应新增字段，但模块语义仍有边界

已核对 `include/linux/pid_namespace.h`、`include/linux/pid.h`、`include/linux/nsproxy.h` 和 `include/linux/user_namespace.h`：`pid_namespace`、`pid`、`nsproxy` 的相关成员及 `UCOUNT_PID_NAMESPACES` 均不是随 `PID_NS` 才插入。因此没有需要借槽掩盖的 PID_NS 布局增长。

`kernel/Makefile` 在启用时构建既有 `pid_namespace.o`；`kernel/pid.c` 为初始 PID namespace 设置 `pidns_operations`。`get_pid_ns()` 从 no-op 变成对非初始 namespace 增引用；`put_pid_ns()` 从 inline no-op 变成外部实现，并新增其 `EXPORT_SYMBOL_GPL`。`copy_pid_ns()`、销毁/重启路径及 proc namespace 行为也从 stub 切换到真正实现。

旧的 PID_NS 关闭配置所编译的预构建模块，可能把 no-op 引用管理逻辑内联在二进制里。即使类型布局/CRC 不变，也不能证明它安全处理新建的非初始 PID namespace。反过来，用 PID_NS 开启配置编译的新模块也不能假定旧内核提供 `put_pid_ns` 导出。应核对实际 vendor 模块是否操作这些 namespace，必要时使用匹配的新配置重编译模块；不添加双轨 namespace 或 CRC 伪装机制。

## 必须显式保留的验证边界

本改动保持 `CONFIG_MODVERSIONS=y`，未修改模块加载器，也未采用 force-load 作为 ABI 解决办法。

**但基线本身已经配置了以下非标准模块策略，本次没有顺手改变：**

```text
CONFIG_MODULE_FORCE_LOAD=y
CONFIG_MODULE_FAKE_LOAD_SUCCESS_WITHOUT_LOADING=y
CONFIG_MODULE_TURNOFF_FORCED_LOAD_TAINT=y
CONFIG_MODULE_TURNOFF_SIG_CHECKS=y
```

尤其 `kernel/module.c:load_module()` 在 `CONFIG_MODULE_FAKE_LOAD_SUCCESS_WITHOUT_LOADING` 下直接返回 0，早于签名和符号版本检查，根本不加载模块。因此本配置下仅有 `insmod` 返回成功、没有 taint 或没有模块错误日志，都不能用作模块兼容证据。不能依赖这些原有开关绕过真实 ABI 问题。改变该基线加载策略属于需单独审核的兼容性变更，不与这次 PID/IPC 最小适配混合；当前交付没有宣称 stockvendor 模块已验证可用。

GitHub 实际构建/后续审核至少应分别确认：

1. 最终 `.config` 中上述新增选项有效，`SYSVIPC`、`IPC_NS`、`NAMESPACES`、`NET`、`SYSCTL`、`MODVERSIONS` 仍为 `y`；可选的 USER_NS/CGROUP_PIDS 等没有被间接打开。
2. 编译、链接通过且 KABI 尺寸/对齐断言通过。保存构建日志、最终配置和 `Module.symvers`，不要仅凭 ZIP 生成判断 ABI。
3. 如能取得同树未改配置的构建产物及实际 stockvendor 模块，比较受影响结构布局、导出符号 CRC、vermagic、模块导入项；单个 `user_struct` 的兼容处理不能替代全量比较。
4. 运行时的 PID/IPC namespace 创建、mqueue 挂载及收发、SELinux/权限策略、Android 启动和硬件功能均未验证。CI 编译成功仍不代表这些测试通过。本试验不自动安装或刷机。
