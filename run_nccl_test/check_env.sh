#!/usr/bin/env bash
# NCCL 跨节点测试环境自检脚本

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
EXIT_CODE=0

HOSTFILE_DEFAULT="${SCRIPT_DIR}/hostfile"
HOSTFILE="${HOSTFILE:-$HOSTFILE_DEFAULT}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"

resolve_nccl_tests_dir() {
    if [[ -n "${NCCL_TESTS_DIR:-}" ]]; then
        printf '%s' "$NCCL_TESTS_DIR"
        return
    fi

    local repo_path="${ROOT_DIR}/nccl-tests"
    if [[ -d "$repo_path" ]]; then
        printf '%s' "$repo_path"
        return
    fi

    printf '%s' "/usr/wkspace/docker/testbed/nccl-tests"
}

NCCL_TESTS_DIR_RESOLVED="$(resolve_nccl_tests_dir)"

print_section() {
    printf '\n==========================================\n'
    printf '%s\n' "$1"
    printf '==========================================\n'
}

pass() { printf '[ OK ] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
fail() {
    printf '[FAIL] %s\n' "$1"
    EXIT_CODE=1
}

check_command() {
    local cmd="$1"
    local desc="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        pass "$desc (${cmd})"
        return 0
    fi
    fail "缺少命令: ${cmd} (${desc})"
    return 1
}

print_section "基本信息"
printf '日期: %s\n' "$(date)"
printf '主机: %s\n' "$(hostname)"
printf '脚本目录: %s\n' "$SCRIPT_DIR"

print_section "MPI 环境"
if check_command mpirun "已安装 MPI"; then
    mpirun --version 2>/dev/null | head -n 1
fi

print_section "GPU 可见性"
if check_command nvidia-smi "检测 GPU"; then
    if nvidia-smi -L >/dev/null 2>&1; then
        pass "nvidia-smi 正常"
        nvidia-smi -L
    else
        fail "nvidia-smi 无法列出 GPU"
    fi
fi

print_section "NCCL 库与测试程序"
if command -v ldconfig >/dev/null 2>&1; then
    if ldconfig -p | grep -qi nccl; then
        pass "系统已安装 libnccl"
    else
        warn "ldconfig 中未找到 libnccl，确认是否已安装"
    fi
else
    warn "ldconfig 不可用，跳过 NCCL 库检测"
fi

if [[ -d "$NCCL_TESTS_DIR_RESOLVED" ]]; then
    pass "找到 NCCL tests 目录: ${NCCL_TESTS_DIR_RESOLVED}"
    if [[ -x "${NCCL_TESTS_DIR_RESOLVED}/build/all_reduce_perf" ]]; then
        pass "all_reduce_perf 已编译"
    else
        fail "在 ${NCCL_TESTS_DIR_RESOLVED}/build 中找不到 all_reduce_perf，需先编译"
    fi
else
    fail "找不到 NCCL tests 目录: ${NCCL_TESTS_DIR_RESOLVED}"
fi

print_section "网络与 RDMA"
if check_command ip "查看网络接口"; then
    ip -o link show | awk -F': ' '{print "- "$2}'
else
    warn "无法使用 ip，尝试 ifconfig"
    if check_command ifconfig "查看网络接口 (net-tools)"; then
        ifconfig -a | sed 's/^/    /'
    fi
fi

if command -v ibv_devinfo >/dev/null 2>&1; then
    pass "ibv_devinfo 可用"
    ibv_devinfo -l 2>/dev/null || ibv_devinfo 2>/dev/null | head -n 20
else
    warn "未找到 ibv_devinfo, RDMA 组件可能未安装"
fi

print_section "SSH 与 Hostfile"
if [[ -f "$HOSTFILE" ]]; then
    pass "找到 hostfile: ${HOSTFILE}"
    sed -e 's/^/    /' "$HOSTFILE"
else
    warn "未找到 hostfile (期望路径: ${HOSTFILE})"
fi

if [[ -f "$SSH_KEY" ]]; then
    pass "找到 SSH 密钥: ${SSH_KEY}"
    stat --printf='    权限: %a\n' "$SSH_KEY" 2>/dev/null || true
else
    warn "未找到 SSH 密钥 (期望路径: ${SSH_KEY})"
fi

if [[ -x "${SCRIPT_DIR}/ssh_to_container.sh" ]]; then
    pass "ssh_to_container.sh 可用"
else
    warn "缺少 SSH 包装脚本 ssh_to_container.sh"
fi

print_section "总结"
if [[ $EXIT_CODE -eq 0 ]]; then
    printf '所有关键检查通过，可运行 run_all_reduce.sh\n'
else
    printf '存在失败项，请根据提示修复后再运行测试\n'
fi

exit "$EXIT_CODE"
