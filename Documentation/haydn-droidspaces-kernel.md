# haydn / AGNi v7.10：Droidspaces FULL / HyperOS-NoKSU / PELT 候选

## 范围与版本边界

- 本次修改基线：`547a4f9de02f22921ba84674d8dc50ce62bd0582`；最初 AGNi v7.10 源码基线为 `7dc006fa2217dab1b30ce0a615980f6c5013667f`。入口仍为 `arch/arm64/configs/agni_haydn_defconfig`。
- 旧最小配置包已有用户实机测试记录，保留其 ZIP，不覆盖，不将旧测试结果外推到本候选。旧云构建 run `43543599924` 的真实 `.config` / `Module.symvers` 用于后续对照；旧 Image 的 IKCONFIG 曾来自 stock_defconfig，不能代表旧真实配置。
- 用户最终选择全部四项，接受按真实依赖关闭 WALT。候选统一标为 `EXPERIMENTAL-Droidspaces-FULL-HyperOS-NoKSU-PELT-<commit12>`；FULL 表示本次目标功能配置，不表示检测全绿、性能无损或已验证 vendor ABI。
- 只实现必需配置、真实已有 ABI 槽适配及构建证据。不修改 CPU 频率/电压/温控表或 Android 用户空间，不写宿主 CPU/pids 配额，不启用 RT_GROUP_SCHED，不本地编译、不连接手机、不刷机、不覆盖旧 ZIP。

## 配置与真实接线

新增配置：

```text
CONFIG_FAIR_GROUP_SCHED=y
CONFIG_CFS_BANDWIDTH=y
CONFIG_CGROUP_PIDS=y
CONFIG_USER_NS=y
CONFIG_IP6_NF_NAT=y
CONFIG_IP6_NF_TARGET_MASQUERADE=y
# CONFIG_SCHED_WALT is not set
```

`init/Kconfig` 的 `CFS_BANDWIDTH` 真实依赖是 `FAIR_GROUP_SCHED && !SCHED_WALT`。保持该依赖，不假装本树存在可直接启用的 WALT+CFS 完整实现。RT_GROUP_SCHED 仍关闭。

原最小版必需/推荐配置、`COMPAT=y`、`COMPAT_VDSO=y` 与 `MODVERSIONS=y` 均保留，包括 PID_NS、POSIX_MQUEUE / POSIX_MQUEUE_SYSCTL、DEVTMPFS、NETFILTER_XT_MATCH_ADDRTYPE、SYSVIPC、IPC/UTS/NET namespace、seccomp 及现有网络/文件系统支持。CI 检查 olddefconfig 后真实生效值，不仅查看 defconfig 文本。NoKSU/KPM/SUSFS 继续由 CI 显式禁用并断言；固定 KernelSU gitlink 仅为已有 Kconfig source 依赖，不删除 wiring。

- CPU quota 与 pids 使用本树现有 CFS bandwidth / cgroup pids 实现；编入控制器不等于给 Android 宿主设置限额。是否挂载/委派及容器配额由正常运行策略决定，不能为了开控制器顺手改宿主策略。
- USER_NS 使用 `kernel/user_namespace.c` 及 `kernel/Makefile` 的既有接线，由 stub 切到原生创建、UID/GID 映射与能力隔离。`cred.user_ns`、`user_namespace` 的相关字段和 `nsproxy` 成员本来就存在，无需 padding。创建/映射仍受内核权限、sysctl 和 SELinux 约束；增加原生隔离能力也增加攻击面。
- `net/ipv6/netfilter/Kconfig` 的 IP6_NF_NAT 依赖 conntrack 并选择通用 NF_NAT / NETFILTER_XT_NAT；IP6_NF_TARGET_MASQUERADE 是选择通用 MASQUERADE target 的兼容选项。已有 IPV6、IP6_NF_IPTABLES、NF_CONNTRACK、NF_NAT、NF_NAT_MASQUERADE、NETFILTER_XT_NAT、NETFILTER_XT_TARGET_MASQUERADE 保持 `y`；不添加本树不存在的 NF_NAT_IPV6 / NF_CONNTRACK_IPV6。

## 调度、boost 与性能边界

`kernel/sched/Makefile` 只有在 CONFIG_SCHED_WALT 下才进入 `walt/`。关闭后，其 Makefile 中的 walt、boost、sched_avg、qc_vas、core_ctl、trace 以及该目录 CPU_FREQ 下的 cpu-boost 均不编入，调度使用本树已有非 WALT / PELT 路径。保留 task_struct 的真实 wts 存储并不会恢复这些运行逻辑。

这不是仅多几个容器开关：任务利用率估计、频率反馈、瞬时 boost、核心控制及负载平衡路径会变化。游戏帧时间、突发响应、温度、电耗可能受影响，**不能承诺性能无损或与旧已测包等效**。不通过额外频率/温控/电压补丁掩盖差异；相同环境下比较旧包与候选才有意义。

## ABI 适配与明确未解决的部分

### sched_entity：只消费四个真实既有槽

删除结构中部原 FAIR_GROUP_SCHED 条件字段，将 depth、parent、cfs_rq、my_q 分别放进原本的 ANDROID_KABI_RESERVE(1..4)，启用时使用 ANDROID_KABI_USE，关闭时仍为原 reserve。avg 和其他既有成员不因这四字段被前移/后移。

arm64 上 depth 是 4 字节 int，槽是 8 字节 u64，union 保持 8 字节尺寸/对齐，depth 后余下 4 字节是未使用 padding，不作为额外字段或状态。其他三项为 8 字节指针；宏自带尺寸/对齐静态断言。匿名 union 的首个有效成员是对应字段；静态 init_task 的未显式字段零初始化，组实体走既有 kzalloc 与 init_tg_cfs_entry() 对四字段的赋值，任务的 set_task_rq()/既有调度初始化仍按字段名操作。不读取 depth 槽的 padding，不添加联合体整槽别名初始化。

这是真实占用既有空间的局部布局处理，不是新增假 reserve，也不是伪造 CRC。不能由此推导整个内核 ABI 稳定；编译断言与实际布局转储仍需后续云构建核实。

### task_struct：保留真实已有 WALT 存储，不恢复执行

`include/linux/sched.h` 将本树已有 walt_task_struct 类型及 task_struct.wts 存储保留在非 WALT 配置中；不新建 sidecar/映射机制，不把任意字节数冒充真实类型。该类型仍使用本树原字段/数组和 NR_CPUS/RTMM 条件。WALT API 的声明/stub 和所有调度运行路径继续受 CONFIG_SCHED_WALT 控制。关闭 WALT 后 init_task 原 WALT 专用初始化不执行，保留区为静态零值；fork 的既有复制不赋予它 WALT 运行意义。这仅避免 wts 删除导致的外露字段位移，绝非完整 task_struct/vendor ABI 保证。

### MQUEUE：首版适配原样保留

`include/linux/sched/user.h` 的 mq_bytes 继续用原有 `ANDROID_KABI_USE(1, unsigned long mq_bytes)`，关闭时仍为 reserve 1，reserve 2 不变。首版把它从中部移到真实尾部 u64 槽，避免移动 locked_shm 等成员；arm64 unsigned long 尺寸/对齐匹配，alloc_uid() 和静态 root_user 的零初始化满足初值。此处不再改动。

来源：Droidspaces-OSS **v7.2.0** 官方目录及字段迁移参考：

<https://github.com/ravindu644/Droidspaces-OSS/tree/v7.2.0/Documentation/resources/kernel-patches/GKI/below-kernel-6.12>

<https://github.com/ravindu644/Droidspaces-OSS/blob/v7.2.0/Documentation/resources/kernel-patches/GKI/below-kernel-6.12/002.5.10_or_lower_use_android_abi_padding_for_posix_mqueue.patch>

原补丁 `a0aa446ca326b5d26ac1dec057efd8c07d2bcbff`，作者及原 Signed-off-by：lateautumn233 <lateautumn233@foxmail.com>，日期 2024-01-27。记录归属不冒充签署。本树无其 OEM_DATA_ARRAY 上下文，所以首版仅消费实际存在的槽，并非整包套用 GKI 补丁。

### 无槽的控制器/调度结构与模块语义

CGROUP_PIDS 使 CGROUP_SUBSYS_COUNT 增长，css_set / cgroup 的数组随之扩张；没有可用 reserve，不硬塞、不用宏伪装。FAIR_GROUP_SCHED/CFS_BANDWIDTH 和关闭 WALT 还会改变 task_group、cfs_rq、rq 等配置相关结构。**旧 vendor 模块 ABI 未承诺保持**，需要真实旧/新产物及模块导入项对照，必要时匹配配置重编译模块。

USER_NS 的字段原本存在不等于模块语义完全相同：旧预编译模块可能内联 no-op get/put_user_ns，不能由字段/CRC 相同证明它安全处理非初始 namespace。首版 PID_NS 的真实引用计数、销毁及 put_pid_ns 导出同样与旧 stub 不同。ipc_namespace 的 mqueue 字段和 pid/nsproxy 相关成员原本存在，不能消除上述行为边界。

MODVERSIONS=y 保持，模块加载器不改，不加入强制加载或版本检查绕过。本次也不顺手改变基线已有的 MODULE_FORCE_LOAD、MODULE_FAKE_LOAD_SUCCESS_WITHOUT_LOADING、MODULE_TURNOFF_FORCED_LOAD_TAINT、MODULE_TURNOFF_SIG_CHECKS 策略。尤其 `kernel/module.c:load_module()` 的既有 fake-success 路径直接返回 0 而不加载模块：insmod 成功、无 taint 或无模块错误日志都不是 ABI 验证。AnyKernel do.modules=0 保持，不自动替换 vendor 模块。

## 真实构建证据

`kernel/Makefile` 改为从真实 `$(KCONFIG_CONFIG)` 嵌入 IKCONFIG，不修改 stock_defconfig 涂绿。CI 用本树 scripts/extract-ikconfig 从新 Image 提取 embedded.config，与最终真实 .config 逐字节 cmp；提取失败、为空或不一致都禁止生成/保留安装 ZIP。

保存真实 .config、嵌入配置、Module.symvers 和既有来源/工具链日志。仅当已有 DEBUG_INFO、vmlinux 和 pahole 可用时导出 sched_entity/task_struct/css_set/cgroup/task_group/cfs_rq/rq 及 user namespace 相关布局；不扩大运行配置、不上传整个 vmlinux。失败/跳过原因另记，不伪称 ABI 检查通过，也不掩盖实际编译错误。后续审核比较真实旧/新 Module.symvers 的导出/CRC，并结合 vermagic、模块导入项和布局；不拿旧伪 IKCONFIG 或 fake-load 返回值作证。

## 后续验收（实现时均未执行）

1. **云构建门禁**：最终 .config 保留旧必需/推荐项及 ARM32 COMPAT，全部新增项为 y，WALT/RT_GROUP_SCHED 关闭，KSU/KPM/SUSFS 关闭；编译链接和 Image 配置 cmp 通过。保存并审查布局与 Module.symvers 的真实旧/新差异。ZIP 生成不代表启动或 vendor ABI 通过。
2. **CPU quota**：另行授权的备用机上，在实际使用的 cgroup 层级（v1 cpu.cfs_quota_us / cpu.cfs_period_us，或已委派的 v2 cpu.max）建立独立测试组，仅移入测试进程。用固定 CPU 亲和性的忙循环，对照无配额与例如 50% 单核配额的 CPU 时间/墙钟比，观察 cpu.stat 节流计数增长；恢复 unlimited 并清理测试组。不能只验证文件存在，也不能给 Android 宿主/系统组写限额。
3. **pids**：独立测试 cgroup 设置小的 pids.max，记录 pids.current；受控创建子进程到上限，确认 fork/clone 返回 EAGAIN 且 pids.events（若提供）增长，退出子进程后计数回落并可再次创建。包括线程计数行为，清理测试组；不在根/Android 系统组试验或制造 fork bomb。
4. **原生 USER_NS**：正常 SELinux enforcing 和正常 sandbox 下，经实际 Droidspaces 路径创建 CLONE_NEWUSER，记录父子 /proc/<pid>/ns/user inode、uid_map/gid_map、setgroups 策略及容器内外 UID/GID、能力边界。合法映射成功、越权映射被拒绝；确认不是 proot/关闭 sandbox 回退。失败时区分 sysctl、映射授权、SELinux 与内核缺失，不以 permissive 替代验收。
5. **NAT66**：先确认外侧有可用 IPv6，再用隔离 netns/veth 和独立测试规则链，经实际容器出口验证 ip6tables nat MASQUERADE 可添加、计数增长、conntrack、出站源地址转换及回包。测试 TCP/UDP、DNS 与必要 ICMPv6/PMTU，不仅菜单或 ping；仅清理测试对象，不 flush Android/netd 全局规则。区分上游 IPv6、转发/路由、用户态 backend、SELinux 与内核 NAT 故障。
6. **整体回归/性能**：复测 PID/IPC namespace、mqueue 挂载收发、seccomp、32 位程序、启动及 Wi-Fi/移动数据/相机/音频等；相同环境比较旧包与候选的游戏帧时间、突发响应、频率/核心状态、温度和电耗。全绿不替代隔离/限额/网络实测，不关闭 sandbox/SELinux 绕过问题。无候选实机记录前不得称已验证可用；此文档/CI 不授权刷机或操作主力机。
