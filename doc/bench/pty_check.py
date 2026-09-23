#!/usr/bin/env python3
"""在本机用 pty 验证 uart_blast 的数据通路（不需要板子）。

pty 的从端当 /dev/ttyS1 用，主端读回来核对：
  - 收到的字节是否正好是设计好的那一串（H4 Reset 帧 + 0x55）
  - 接收路径是否被回灌（曾经的 bug：收数据复用发送缓冲）
运行时把主端收到的东西再回写回去，模拟"模组回话"，检查 RX 上报。
"""
import os
import pty
import subprocess
import sys
import time

BIN = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ub_host"

master, slave = pty.openpty()
slave_name = os.ttyname(slave)
print(f"pty: master={master} slave={slave_name}")

# 让从端更像目标：非阻塞地开一个 fd 保持住，避免被关掉
keep = os.open(slave_name, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
# 主端必须非阻塞：子进程退出后 os.read 会永久阻塞，脚本永远走不到超时判断
os.set_blocking(master, False)

p = subprocess.Popen(
    [BIN, "-d", slave_name, "-b", "1500000", "-m", "mix", "-n", "16",
     "-g", "30", "-t", "2"],
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
)

rx = b""
echoed = 0
deadline = time.time() + 2.5
while time.time() < deadline:
    try:
        chunk = os.read(master, 4096)
    except OSError:
        chunk = b""
    if chunk:
        rx += chunk
        if echoed < 3:          # 回写几次，模拟模组应答
            os.write(master, b"\x04\x0e\x04\x01\x03\x0c\x00")
            echoed += 1
    else:
        time.sleep(0.01)

try:
    out, _ = p.communicate(timeout=10)
except subprocess.TimeoutExpired:
    p.kill()
    out, _ = p.communicate()

print("---- uart_blast 输出 ----")
print(out)
print("---- pty 主端收到 ----")
print(f"共 {len(rx)} 字节")
print(rx[:200].hex(" "))

# 核对：每个突发的头 8 字节必须是两帧 H4 Reset，其后是 0x55
burst = bytes([0x01, 0x03, 0x0c, 0x00]) * 2 + b"\x55" * 16
ok_head = rx.startswith(burst)
print(f"首突发与设计一致: {ok_head}")
if not ok_head:
    print(f"  期望开头: {burst[:24].hex(' ')}")
    print(f"  实际开头: {rx[:24].hex(' ')}")

# 突发是否严格重复
n = len(rx) // len(burst)
repeat_ok = rx[: n * len(burst)] == burst * n
print(f"共 {n} 个完整突发，严格重复: {repeat_ok}")
if rx[n * len(burst):]:
    print(f"  尾部残余 {len(rx) - n * len(burst)} 字节（正常，跑满时长被截断）")

os.close(keep)
os.close(slave)
os.close(master)
sys.exit(0 if (ok_head and repeat_ok) else 1)
