#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# CI-only experimental build. Never run the author's interactive/multi-variant script.
set -Eeuo pipefail
umask 022

# Fail before any compiler invocation outside GitHub-hosted CI.
[[ ${GITHUB_ACTIONS:-} == true && ${RUNNER_ENVIRONMENT:-} == github-hosted ]] || {
  echo 'This entry point is restricted to GitHub-hosted Actions; no local build.' >&2
  exit 2
}
[[ $# == 0 ]] || { echo 'No variant arguments are accepted.' >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
OUT=${AGNI_CI_OUT:?}
ARTIFACTS=${AGNI_CI_ARTIFACTS:?}
TOOLS=${AGNI_CI_TOOLS:?}
# Keep the cleanup/diagnostics paths constrained, including on manual invocations.
[[ $OUT == "$ROOT/out-haydn-ci" && $ARTIFACTS == "$ROOT/artifacts-haydn-ci" ]] || exit 2
mkdir -p "$OUT" "$ARTIFACTS/diagnostics" "$TOOLS"
DIAG="$ARTIFACTS/diagnostics"
[[ ! -e $OUT/.config && ! -e $OUT/arch/arm64/boot/Image ]] || {
  echo 'Refusing reused kernel output: use a fresh hosted job.' >&2; exit 2;
}
exec > >(tee "$DIAG/ci.log") 2>&1

finish() {
  local result=$?
  trap - EXIT
  set +e
  printf 'exit_code=%s\n' "$result" > "$DIAG/status.txt"
  local file
  for file in .config .config.old Module.symvers System.map modules.order modules.builtin \
    modules.builtin.modinfo include/config/kernel.release include/generated/compile.h; do
    if [[ -f $OUT/$file ]]; then
      mkdir -p "$DIAG/$(dirname "$file")"
      cp "$OUT/$file" "$DIAG/$file"
    fi
  done
  git status --short --untracked-files=no > "$DIAG/source-status-after.txt"
  # Keep failure uploads bounded. Never upload the toolchain, object tree, vmlinux or credentials.
  for file in "$DIAG"/*.log; do
    [[ -f $file ]] || continue
    if (( $(stat -c %s "$file") > 16777216 )); then
      tail -c 16777216 "$file" > "$file.tail"
      mv "$file.tail" "$file"
    fi
  done
  if (( result != 0 )); then
    rm -f "$ARTIFACTS"/*.zip "$ARTIFACTS"/SHA256SUMS
    echo 'FAILED: no install ZIP is retained; inspect diagnostics.' >&2
  fi
  exit "$result"
}
trap finish EXIT

COMMIT=$(git rev-parse HEAD)
[[ $COMMIT == "${GITHUB_SHA:?}" ]] || { echo 'Dispatched commit mismatch'; exit 1; }
git diff --exit-code HEAD --
[[ -z $(git status --porcelain --untracked-files=no) ]] || exit 1
[[ $(sed -n 's/^export AGNI_VERSION="\([^"]*\)"/\1/p' AGNi_version.sh) == v7.10 ]] || {
  echo 'This workflow is specifically reviewed for AGNi v7.10.'; exit 1;
}
# Do NOT source AGNi_version.sh: it rewrites every agni_* source defconfig.
export AGNI_VERSION=v7.10 AGNI_BUILD_TYPE=HyperOS ARCH=arm64 SUBARCH=arm64
export KBUILD_BUILD_USER=y2485871697 KBUILD_BUILD_HOST=github-actions KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP
KBUILD_BUILD_TIMESTAMP=$(git show -s --format=%cD HEAD)
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH=$(git show -s --format=%ct HEAD)
export KCONFIG_NOTIMESTAMP=1

# Official Google Android Clang 14 prebuilt; same LLVM major as the author's local
# Snapdragon LLVM 14.1.4, but NOT represented as the identical proprietary compiler.
TC_URL=https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86
TC_COMMIT=f3480869e8aea2016f5c9263a2c73f3c467cc731
TC_SUBDIR=clang-r450784d
TC_TREE=12362e20aad2323231ad6031de145fbbcc533df5
TC_REPO="$TOOLS/aosp-clang"
[[ ! -e $TC_REPO ]] || { echo 'Refusing a reused toolchain directory'; exit 1; }
git init "$TC_REPO"
git -C "$TC_REPO" remote add origin "$TC_URL"
git -C "$TC_REPO" config core.sparseCheckout true
git -C "$TC_REPO" config remote.origin.promisor true
git -C "$TC_REPO" config remote.origin.partialclonefilter blob:none
printf '/%s/\n' "$TC_SUBDIR" > "$TC_REPO/.git/info/sparse-checkout"
git -C "$TC_REPO" -c fetch.fsckObjects=true fetch --filter=blob:none --depth=1 origin "$TC_COMMIT" \
  2>&1 | tee "$DIAG/toolchain-fetch.log"
[[ $(git -C "$TC_REPO" rev-parse FETCH_HEAD) == "$TC_COMMIT" ]]
[[ $(git -C "$TC_REPO" rev-parse "FETCH_HEAD:$TC_SUBDIR") == "$TC_TREE" ]]
git -C "$TC_REPO" -c transfer.fsckObjects=true checkout --detach FETCH_HEAD
# Git validates object IDs during transfer; fsck checks all fetched objects again.
git -C "$TC_REPO" fsck --no-reflogs > "$DIAG/toolchain-fsck.log" 2>&1
TC="$TC_REPO/$TC_SUBDIR"
export PATH="$TC/bin:$PATH"
export LD_LIBRARY_PATH="$TC/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
{
  printf 'url=%s\ncommit=%s\nsubdirectory=%s\nsubtree=%s\n' "$TC_URL" "$TC_COMMIT" "$TC_SUBDIR" "$TC_TREE"
  cat "$TC/AndroidVersion.txt"
  "$TC/bin/clang" --version
  "$TC/bin/ld.lld" --version
} | tee "$DIAG/toolchain.txt"
# Record SHA-256 for every downloaded toolchain file, including notices/libraries.
(cd "$TC" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) \
  > "$DIAG/toolchain-files.sha256"
cp "$TC/NOTICE" "$DIAG/toolchain-NOTICE"

JOBS=$(nproc)
# Explicit command-line overrides adapt Snapdragon-prefixed names without editing Makefile.
# Empty CROSS_COMPILE selects upstream Makefile's --target=aarch64-linux-gnu.
# Its host C++ rule uses Snapdragon-specific -flto=$(BUILDJOBS); use standard ThinLTO
# for host utilities with AOSP Clang (does not change kernel LTO/configuration).
MAKE_ARGS=( O="$OUT" ARCH=arm64 SUBARCH=arm64 CROSS_COMPILE= LLVM=1 LLVM_IAS=1
  CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
  CC_COMPAT="$TC/bin/clang --target=arm-linux-gnueabi" LD_COMPAT="$TC/bin/ld.lld"
  CC="$TC/bin/clang" REAL_CC="$TC/bin/clang" LD="$TC/bin/ld.lld"
  AR="$TC/bin/llvm-ar" NM="$TC/bin/llvm-nm" LLVM_NM="$TC/bin/llvm-nm"
  OBJCOPY="$TC/bin/llvm-objcopy" OBJDUMP="$TC/bin/llvm-objdump"
  READELF="$TC/bin/llvm-readelf" OBJSIZE="$TC/bin/llvm-size" STRIP="$TC/bin/llvm-strip"
  HOSTCC="$TC/bin/clang" HOSTCXX="$TC/bin/clang++" HOSTLDFLAGS=-fuse-ld=lld
  KBUILD_HOSTCXXFLAGS='-O2 -flto=thin'
  BUILDJOBS="$JOBS" PYTHON=python3 PYTHON3=python3 )

make "${MAKE_ARGS[@]}" agni_haydn_defconfig 2>&1 | tee "$DIAG/configure.log"
# No source defconfig writeback, menuconfig, savedefconfig, or all-optional-features fragment.
# Explicitly turn off root replacements; the project's AnyKernel preserves the boot ramdisk.
scripts/config --file "$OUT/.config" --disable KSU --disable KSU_NEXT --disable KSU_SUSFS --disable KPM
make "${MAKE_ARGS[@]}" olddefconfig 2>&1 | tee -a "$DIAG/configure.log"
check_config() {
  local symbol
  for symbol in NAMESPACES PID_NS IPC_NS UTS_NS NET_NS SYSVIPC POSIX_MQUEUE \
    DEVTMPFS NETFILTER_XT_MATCH_ADDRTYPE SECCOMP SECCOMP_FILTER CGROUPS \
    COMPAT COMPAT_VDSO MODVERSIONS; do
    grep -qx "CONFIG_${symbol}=y" "$OUT/.config" || {
      echo "Required effective CONFIG_${symbol}=y missing after olddefconfig"; return 1;
    }
  done
  # Check enabled forms rather than assuming undefined symbols appear as '# ... is not set'.
  if grep -Eq '^CONFIG_(KSU[A-Za-z0-9_]*|KPM|SUSFS[A-Za-z0-9_]*)=[ym]$' "$OUT/.config"; then
    echo 'KernelSU, SUSFS or KPM configuration is enabled'; return 1
  fi
  # Never alter baseline resource-controller choices. Only reject newly enabled limits.
  for symbol in USER_NS CGROUP_PIDS CFS_BANDWIDTH; do
    if grep -Eq "^CONFIG_${symbol}=[ym]$" "$OUT/.config" &&
       ! grep -Eq "^CONFIG_${symbol}=[ym]$" arch/arm64/configs/agni_haydn_defconfig; then
      echo "Unexpected newly enabled CONFIG_${symbol}"; return 1
    fi
  done
}
check_config
cp "$OUT/.config" "$ARTIFACTS/.config"
cp arch/arm64/configs/agni_haydn_defconfig "$DIAG/input-agni_haydn_defconfig"
{
  printf 'source_repository=%s\nsource_commit=%s\n' "${GITHUB_SERVER_URL:?}/${GITHUB_REPOSITORY:?}" "$COMMIT"
  printf 'source_base=7dc006fa2217dab1b30ce0a615980f6c5013667f\n'
  printf 'run=%s/%s/actions/runs/%s\nattempt=%s\n' "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}"
  printf 'variant=EXPERIMENTAL Droidspaces haydn AGNi v7.10 HyperOS-NoKSU\n'
  printf 'targets=default (original haydn build), dtbs\n'
  printf 'make '; printf '%q ' "${MAKE_ARGS[@]}"; printf '\n'
  git show -s --format=fuller HEAD
  printf '\nPinned source submodules (configuration dependency only):\n'
  git submodule status
  sha256sum arch/arm64/configs/agni_haydn_defconfig "$OUT/.config"
  printf '\nEffective module/ABI policy (not proof of stock-vendor ABI compatibility):\n'
  for symbol in MODULES MODVERSIONS MODULE_FORCE_LOAD MODULE_FORCE_UNLOAD \
    MODULE_FAKE_LOAD_SUCCESS_WITHOUT_LOADING MODULE_SIG MODULE_SIG_FORCE MODULE_SIG_ALL; do
    grep -E "^(CONFIG_${symbol}=|# CONFIG_${symbol} is not set)" "$OUT/.config" || \
      printf 'CONFIG_%s: absent\n' "$symbol"
  done
  printf 'WARNING: build success or insmod return value is NOT stock-vendor ABI validation.\n'
} > "$ARTIFACTS/PROVENANCE.txt"
# Default target follows the original author (includes configured in-tree modules).
# dtbs is explicit as an additional safeguard for the haydn dtb/dtbo output.
make -j"$JOBS" "${MAKE_ARGS[@]}" 2>&1 | tee "$DIAG/build.log"
make -j"$JOBS" "${MAKE_ARGS[@]}" dtbs 2>&1 | tee "$DIAG/dtbs.log"
check_config
cmp "$ARTIFACTS/.config" "$OUT/.config"
git diff --exit-code HEAD --

BOOT="$OUT/arch/arm64/boot"
for file in Image dtb.img dtbo.img; do
  [[ -s $BOOT/$file ]] || { echo "Missing original haydn payload: $file"; exit 1; }
  cp "$BOOT/$file" "$ARTIFACTS/$file"
done
[[ -s $OUT/Module.symvers ]] || { echo 'Missing Module.symvers'; exit 1; }
find "$OUT" -type f -name '*.ko' -printf '%P\n' | LC_ALL=C sort > "$DIAG/built-modules.txt"
if [[ -s $DIAG/built-modules.txt ]]; then
  # Original AnyKernel has do.modules=0: do not change installation policy or vendor modules.
  # Keep any built modules separately for ABI investigation, never silently install them.
  tar -C "$OUT" -czf "$ARTIFACTS/modules-DIAGNOSTIC-ONLY.tar.gz" -T "$DIAG/built-modules.txt"
fi

STAGE="$OUT/anykernel-stage"
mkdir -p "$STAGE"
cp -a anykernel3/. "$STAGE/"
# No replacement AnyKernel download; all its scripts/binaries are from this source commit.
[[ -s $STAGE/anykernel.sh && -s $STAGE/tools/ak3-core.sh && -s $STAGE/META-INF/com/google/android/update-binary ]]
[[ ! -e $STAGE/.git ]] || { echo 'Unexpected AnyKernel VCS metadata'; exit 1; }
# Refuse templates carrying a stale kernel payload from a different build.
if find "$STAGE" -maxdepth 1 -type f \( -name 'Image*' -o -name 'dtb*' -o -name 'dtbo*' \) | grep -q .; then
  echo 'Unexpected pre-existing AnyKernel payload'; exit 1
fi
cp "$ARTIFACTS/Image" "$ARTIFACTS/dtb.img" "$ARTIFACTS/dtbo.img" "$STAGE/"
# Change the display label in the staged copy only; keep installer/root handling untouched.
sed -i 's/^kernel.string=.*/kernel.string=EXPERIMENTAL AGNi v7.10 Droidspaces haydn HyperOS-NoKSU/' "$STAGE/anykernel.sh"
cp "$ARTIFACTS/PROVENANCE.txt" "$STAGE/PROVENANCE.txt"
cp COPYING "$ARTIFACTS/COPYING.kernel"
cp COPYING "$STAGE/COPYING.kernel"
cat > "$ARTIFACTS/EXPERIMENTAL.txt" <<'WARNING'
EXPERIMENTAL: AGNi v7.10 / haydn / Droidspaces / HyperOS-NoKSU
Built for evaluation, NOT a claim of boot, stock-vendor ABI or Droidspaces compatibility.
No phone has been connected, flashed or tested by this workflow. No Release is created.
The original repository AnyKernel installer is retained; no Magisk installer or KernelSU
is added. Preserving an existing Magisk installation is not a tested guarantee.
Any modules archive is DIAGNOSTIC ONLY and is not installed by this ZIP.
Do not use on the primary phone. Review the source, logs, config and recovery plan first.
WARNING
cp "$ARTIFACTS/EXPERIMENTAL.txt" "$STAGE/EXPERIMENTAL.txt"
ZIP="AGNi_kernel-haydn-v7.10-EXPERIMENTAL-Droidspaces-HyperOS-NoKSU-${COMMIT:0:12}.zip"
# Do not execute any recovery script or the ARM magiskboot utility on the host.
(cd "$STAGE" && zip -q -r "$ARTIFACTS/$ZIP" .)
unzip -t "$ARTIFACTS/$ZIP" > "$DIAG/zip-test.txt"
unzip -l "$ARTIFACTS/$ZIP" > "$DIAG/zip-contents.txt"
for file in Image dtb.img dtbo.img; do
  [[ $(unzip -p "$ARTIFACTS/$ZIP" "$file" | sha256sum | cut -d' ' -f1) == \
     $(sha256sum "$ARTIFACTS/$file" | cut -d' ' -f1) ]]
done
(cd "$ARTIFACTS" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | \
  LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS)
printf 'SUCCESS: %s (experimental, not flashed or device-tested)\n' "$ZIP"
