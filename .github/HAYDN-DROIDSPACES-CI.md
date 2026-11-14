# EXPERIMENTAL-Droidspaces-FULL-HyperOS-NoKSU-PELT CI (haydn / AGNi v7.10)

This is a **cloud-build experiment**, not a device installation procedure. It targets only
haydn, HyperOS and **NoKSU**, based on AGNi v7.10. It does not build AOSP/90Hz variants,
install Magisk, publish a Release, connect to a device, or flash anything. A successful
build is not evidence of bootability, stock-HyperOS vendor-module ABI compatibility or
Droidspaces runtime compatibility.

This candidate starts from `547a4f9de02f22921ba84674d8dc50ce62bd0582` and enables
CPU quota, pids, native USER_NS and IPv6 NAT. CFS_BANDWIDTH really depends on
FAIR_GROUP_SCHED and !SCHED_WALT in this tree: WALT is disabled, not patched around.
The previously device-tested minimal WALT ZIP remains separate and must not be
overwritten or treated as evidence that this FULL candidate is device-tested.
FULL describes requested feature coverage, not a performance, all-green or vendor-ABI
promise. Do not change CPU frequency/voltage/thermal tables, Android userspace or host
cgroup limits to make the candidate pass.

## Run exactly the reviewed revision

In the fork's GitHub Actions page, choose
**EXPERIMENTAL-Droidspaces-FULL-HyperOS-NoKSU-PELT**, then **Run workflow**, selecting the reviewed
`droidspaces-haydn-v7.10` revision. There are no variant inputs. The workflow only has
`workflow_dispatch`; pushes and pull requests do not start a build. One dispatched job
builds one kernel variant. Do not dispatch more than once without reviewing the first
run. No secrets or write permission are required.

Entry point: `.github/workflows/build-haydn-droidspaces.yml` invokes
`bash scripts/ci-build-haydn.sh` **with no arguments**. The script refuses non-GitHub-hosted
environments. Do not run a local kernel compilation. The hosted job calls:

1. `make O=out-haydn-ci ... agni_haydn_defconfig`;
2. `scripts/config --file out-haydn-ci/.config --disable KSU --disable KSU_NEXT --disable KSU_SUSFS --disable KPM`;
3. `make O=out-haydn-ci ... olddefconfig` and effective-config validation;
4. the original author's default `make -j$(nproc) O=out-haydn-ci ...` target;
5. `make -j$(nproc) O=out-haydn-ci ... dtbs` (ensures device trees, not another variant);
6. extracting IKCONFIG from `Image` with this tree's `scripts/extract-ikconfig` and
   comparing it byte-for-byte with final `.config` (failure means no installer ZIP);
7. optionally exporting key layouts using existing debug information and pahole;
8. packaging the resulting `Image`, `dtb.img` and `dtbo.img` using **the source tree's
   `anykernel3`**, without executing its recovery scripts on the build host.

The full command-line tool overrides are recorded in `PROVENANCE.txt`. We deliberately
do not run `build_kernel_haydn.sh` or source `AGNi_version.sh`: those upstream scripts
use a personal Snapdragon LLVM path, perform two variants and/or rewrite source
configs. There is no `menuconfig`, source config synchronization, `savedefconfig`,
all-features fragment, downloaded installer replacement, or local zipsigner.

## Compiler provenance and dependency limits

The upstream script references local **Snapdragon LLVM 14.1.4** and does not provide an
unattended public download with a verifiable checksum. This job instead uses Google's
official AOSP **Clang 14**, `clang-r450784d`, not an unspecified third-party toolchain.
This is **not claimed to be the author's identical compiler**. Compatibility must be
established by the real cloud build and later separately authorized device testing.

* Repository: <https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86>
* Commit: `f3480869e8aea2016f5c9263a2c73f3c467cc731`
* Reference used to establish provenance: `android-13.0.0_r1`
* Subdirectory: `clang-r450784d`
* Subtree Git object: `12362e20aad2323231ad6031de145fbbcc533df5`
* Evidence: [tag/commit](https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/refs/tags/android-13.0.0_r1),
  [subtree](https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/f3480869e8aea2016f5c9263a2c73f3c467cc731/clang-r450784d/).

A fresh sparse Git checkout validates the commit and subtree, checks fetched Git objects,
and records SHA-256 for every downloaded regular file. No mutable branch, unverified
archive, toolchain cache or installation script is used. The original toolchain notices
are retained in diagnostics. LLVM tools are supplied through command-line Make overrides
because this fork's Makefile otherwise expects Snapdragon-prefixed executables.
The host-only C++ flag is overridden to standard `-O2 -flto=thin`, avoiding the
fork's `-flto=$(BUILDJOBS)` form which is not a standard AOSP Clang LTO mode; this
does not change the kernel's selected LTO configuration.

Actions are pinned to supplied, verified release commits: checkout v7.0.1 and
upload-artifact v7.0.2. Host utilities come from Ubuntu 22.04's configured official APT
repositories, not random binary URLs. **APT packages and GitHub's hosted runner image
are distribution-maintained, not a hermetically pinned container snapshot**; the exact
installed package versions and hosted image revision are saved. Kernel/compiler/action
sources are fixed; bit-for-bit reproducibility across future runner updates is not
claimed. The source repository's license and AnyKernel licensing/comments are preserved.

## Configuration and ABI guardrails

The effective `.config`, **after `olddefconfig`**, must have all of
`CONFIG_NAMESPACES`, `CONFIG_PID_NS`, `CONFIG_IPC_NS`, `CONFIG_UTS_NS`,
`CONFIG_NET_NS`, `CONFIG_SYSVIPC`, `CONFIG_POSIX_MQUEUE`, `CONFIG_DEVTMPFS`,
`CONFIG_NETFILTER_XT_MATCH_ADDRTYPE`, `CONFIG_SECCOMP`, `CONFIG_SECCOMP_FILTER`,
`CONFIG_CGROUPS` and `CONFIG_MODVERSIONS` equal to `y`. All enabled `CONFIG_KSU*`, `CONFIG_SUSFS*` and `CONFIG_KPM` settings are rejected.
`CONFIG_COMPAT` and `CONFIG_COMPAT_VDSO` must remain enabled.
The FULL effective configuration additionally requires `USER_NS`, `FAIR_GROUP_SCHED`,
`CFS_BANDWIDTH`, `CGROUP_PIDS`, `IP6_NF_NAT` and `IP6_NF_TARGET_MASQUERADE` equal to `y`.
`SCHED_WALT` and `RT_GROUP_SCHED` must be disabled. Existing namespace/IPC/seccomp,
filesystem, CPUSETS/MEMCG/CPUACCT/FREEZER, ARM32 COMPAT and network dependencies are
asserted too, including `IPV6`, `IP6_NF_IPTABLES`, `NF_CONNTRACK`, `NF_NAT`,
`NF_NAT_MASQUERADE`, `NETFILTER_XT_NAT` and `NETFILTER_XT_TARGET_MASQUERADE`.
There are no nonexistent `NF_NAT_IPV6`/`NF_CONNTRACK_IPV6` settings. Source configs must
remain unchanged during the build. Enabling controllers does not set host quotas.

The baseline's custom module policies are **not silently corrected**. Provenance records
`CONFIG_MODVERSIONS`, `CONFIG_MODULE_FORCE_LOAD`,
`CONFIG_MODULE_FAKE_LOAD_SUCCESS_WITHOUT_LOADING` and related signing/unloading settings
from the effective config. Forced loads and an `insmod` success return (especially the
fake-success policy) do **not** establish stock-vendor ABI compatibility. `Module.symvers`
is diagnostic evidence, not a substitute for that verification. The first-version
POSIX-mqueue slot adaptation is retained. sched_entity consumes its four real existing
KABI slots for group fields without moving avg; task_struct retains its real wts payload
without enabling WALT code. But CGROUP_PIDS grows css_set/cgroup arrays with no available
reserve, and task_group/cfs_rq/rq change too: full old-vendor ABI is NOT promised.
USER_NS's existing fields do not make its new reference/permission semantics identical
to the old stubs. MODVERSIONS stays enabled; no fake reserve, CRC trick or sidecar is added.
See `Documentation/haydn-droidspaces-kernel.md` for implementation boundaries.

The bundled AnyKernel has `do.modules=0`; CI preserves that policy and does not install
replacement vendor modules. If the default target emits `.ko` files, they are provided
in a separate **DIAGNOSTIC-ONLY** archive, not inserted into the installer. The original
AnyKernel code has existing-Magisk handling; CI adds neither Magisk nor KSU, but cannot
guarantee that an untested installation will preserve root or boot successfully.

## Artifacts and failure behavior

The Actions artifact is named
`EXPERIMENTAL-Droidspaces-FULL-HyperOS-NoKSU-PELT-<commit12>-<run>-<attempt>`
(14-day retention). AnyKernel's staged display label, ZIP, warning and PROVENANCE
share the same candidate label with commit12. The static workflow name identifies FULL/PELT;
the run display includes the complete commit SHA. Early pre-checkout failures may use the
full SHA fallback artifact label rather than a short SHA.
A successful build includes:

* `AGNi_kernel-haydn-v7.10-EXPERIMENTAL-Droidspaces-FULL-HyperOS-NoKSU-PELT-<commit12>.zip`;
* separate nonempty `Image`, `dtb.img`, `dtbo.img`, effective `.config` and extracted `embedded.config`;
* `SHA256SUMS`, `PROVENANCE.txt`, original kernel license and experimental warning;
* diagnostic `Module.symvers`, `System.map`, module lists, build/config/toolchain logs,
  compiler manifests/checksums, host package versions, and ZIP-content/integrity checks;
* a diagnostic-only modules archive if modules were produced.

SHA256SUMS covers the top-level payloads/manifests/config, not changing logs. ZIP payload
hashes are checked against the standalone files. Missing expected boot images or
Module.symvers fails the job. The full object tree, vmlinux and compiler binaries are
not uploaded. On failure, no installer ZIP or success checksum is retained; `always()`
still uploads available diagnostics, with each script log truncated to its final 16 MiB.
APT failure still leaves its dependency log when possible. Abrupt runner termination
can prevent final diagnostics and is not represented as a successful build.

**Not yet verified by implementation alone:** hosted download/build success, resultant
kernel/vendor ABI, preserved Magisk state on-device, booting, and Droidspaces workloads.
No device testing or flashing is authorized by this workflow.

## ARM32 vDSO and configuration evidence

The fixed AOSP Clang/LLD also builds the enabled ARM32 compatibility vDSO.
The shared make arguments explicitly set `LLVM=1`,
`CROSS_COMPILE_COMPAT=arm-linux-gnueabi-`, `CC_COMPAT` with the ARM target,
and `LD_COMPAT` to LLD; no second compiler download or disabling COMPAT is needed.

The previous `kernel/Makefile` embedded `arch/arm64/configs/stock_defconfig`, not the
real build configuration. This candidate fixes the dependency to `$(KCONFIG_CONFIG)`;
stock_defconfig is not edited. The script archives the real final `.config`, the input
defconfig and `embedded.config` extracted from the built Image, with hashes and a
mandatory `cmp`. Extraction failure, empty output or mismatch fails before packaging;
the failure trap removes any ZIP/success checksum. The old Image's embedded configuration
must not be used as the old baseline: use its archived real `.config` instead.

Existing `CONFIG_DEBUG_INFO=y`/DWARF information can supply optional layout evidence.
When pahole and vmlinux are available, diagnostics export sched_entity, task_struct,
css_set, cgroup, task_group, cfs_rq, rq, cred, user_namespace and nsproxy. Missing
prerequisites or per-type decode failures are recorded in layout-status/layout files;
they are not mislabeled as ABI passes, nor used to hide a kernel build failure. No new
runtime debug configuration, baseline download permission or vmlinux upload is added.
Review must compare actual old/new Module.symvers exports/CRCs and relevant module imports.

## Runtime acceptance is separate from green configuration checks

Disabling WALT stops building its boost/qc_vas/core_ctl/cpu-boost paths and selects this
tree's existing non-WALT/PELT scheduling path. Gaming, burst response, frequency feedback,
thermals and battery behavior may change. No unchanged-performance claim is made.
Keep the tested old ZIP and compare only under the same device/workload conditions.

On a separately authorized spare device, retain SELinux enforcing and normal sandboxing.
Verify actual CPU quota throttling and recovery in a dedicated test cgroup (not the
Android host group), controlled pids-limit EAGAIN/count recovery, native USER_NS
inode/UID/GID-map/capability isolation (no proot or disabled-sandbox fallback), and real
NAT66 source translation/return traffic with rule counters/conntrack and an IPv6 upstream.
Do not flush Android/netd rules or change host limits. Restore only test objects.
Recheck boot, ARM32, namespaces/mqueue/seccomp and hardware functions; compare frame times,
response, temperatures and energy use rather than claiming lossless performance.
Detailed bounded acceptance criteria are in `Documentation/haydn-droidspaces-kernel.md`.
These tests have not been executed by this implementation or workflow.

## Pinned Kconfig dependency

Checkout initializes the existing `KernelSU` gitlink at its committed revision.
`drivers/Kconfig` unconditionally parses `drivers/kernelsu/Kconfig` via the
tracked symlink, so the Kconfig source is required even for this NoKSU build.
This does not enable or compile KernelSU: KSU/KPM/SUSFS are explicitly disabled
before olddefconfig and the final effective configuration rejects them.
The dependency revision is recorded in PROVENANCE.txt; upstream Kconfig wiring
is retained rather than deleted for this build.
