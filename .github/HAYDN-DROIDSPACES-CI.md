# Experimental haydn / Droidspaces CI (AGNi v7.10)

This is a **cloud-build experiment**, not a device installation procedure. It targets only
haydn, HyperOS and **NoKSU**, based on AGNi v7.10. It does not build AOSP/90Hz variants,
install Magisk, publish a Release, connect to a device, or flash anything. A successful
build is not evidence of bootability, stock-HyperOS vendor-module ABI compatibility or
Droidspaces runtime compatibility.

## Run exactly the reviewed revision

In the fork's GitHub Actions page, choose **Experimental haydn Droidspaces
HyperOS-NoKSU**, then **Run workflow**, selecting the reviewed
`droidspaces-haydn-v7.10` revision. There are no variant inputs. The workflow only has
`workflow_dispatch`; pushes and pull requests do not start a build. One dispatched job
builds one kernel variant. Do not dispatch more than once without reviewing the first
run. No secrets or write permission are required.

Entry point: `.github/workflows/build-haydn-droidspaces.yml` invokes
`bash scripts/ci-build-haydn.sh` **with no arguments**. The script refuses non-GitHub-hosted
environments. Do not run a local kernel compilation. The hosted job calls:

1. `make O=out-haydn-ci ... agni_haydn_defconfig`;
2. `scripts/config --file out-haydn-ci/.config --disable KSU --disable KSU_NEXT`;
3. `make O=out-haydn-ci ... olddefconfig` and effective-config validation;
4. the original author's default `make -j$(nproc) O=out-haydn-ci ...` target;
5. `make -j$(nproc) O=out-haydn-ci ... dtbs` (ensures device trees, not another variant);
6. packaging the resulting `Image`, `dtb.img` and `dtbo.img` using **the source tree's
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
The script does not turn on optional container/resource features and does not modify
baseline resource-controller choices. Newly enabled `CGROUP_PIDS` or `CFS_BANDWIDTH`
relative to the checked-in haydn defconfig are rejected. Source configs must remain
unchanged during the build.

The baseline's custom module policies are **not silently corrected**. Provenance records
`CONFIG_MODVERSIONS`, `CONFIG_MODULE_FORCE_LOAD`,
`CONFIG_MODULE_FAKE_LOAD_SUCCESS_WITHOUT_LOADING` and related signing/unloading settings
from the effective config. Forced loads and an `insmod` success return (especially the
fake-success policy) do **not** establish stock-vendor ABI compatibility. `Module.symvers`
is diagnostic evidence, not a substitute for that verification. POSIX-mqueue ABI handling
is a separate source/configuration change, not performed by this build script.

The bundled AnyKernel has `do.modules=0`; CI preserves that policy and does not install
replacement vendor modules. If the default target emits `.ko` files, they are provided
in a separate **DIAGNOSTIC-ONLY** archive, not inserted into the installer. The original
AnyKernel code has existing-Magisk handling; CI adds neither Magisk nor KSU, but cannot
guarantee that an untested installation will preserve root or boot successfully.

## Artifacts and failure behavior

The Actions artifact is named
`EXPERIMENTAL-Droidspaces-haydn-HyperOS-NoKSU-<run>-<attempt>` (14-day retention).
A successful build includes:

* `AGNi_kernel-haydn-v7.10-EXPERIMENTAL-Droidspaces-HyperOS-NoKSU-<commit12>.zip`;
* separate nonempty `Image`, `dtb.img`, `dtbo.img` and the effective `.config`;
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

The upstream `kernel/Makefile` embeds `arch/arm64/configs/stock_defconfig`
as IKCONFIG instead of the generated build configuration. Thus `/proc/config.gz`
or `extract-ikconfig Image` is not evidence of the actual enabled features.
This workflow preserves upstream embedding behavior and archives the actual
post-olddefconfig output `.config` with its SHA-256, plus the input defconfig.
Runtime namespace creation still needs verification after a user-controlled flash.

## Pinned Kconfig dependency

Checkout initializes the existing `KernelSU` gitlink at its committed revision.
`drivers/Kconfig` unconditionally parses `drivers/kernelsu/Kconfig` via the
tracked symlink, so the Kconfig source is required even for this NoKSU build.
This does not enable or compile KernelSU: KSU/KPM/SUSFS are explicitly disabled
before olddefconfig and the final effective configuration rejects them.
The dependency revision is recorded in PROVENANCE.txt; upstream Kconfig wiring
is retained rather than deleted for this build.
