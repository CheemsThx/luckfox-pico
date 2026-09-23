// SPDX-License-Identifier: GPL-2.0
/*
 * uart_blast — V020 蓝牙 UART 台面工具（配合示波器使用）
 *
 * 目的：在 /dev/ttyS1（= uart0 = 蓝牙 HCI，见记忆 v020-bt-hci-tty-remap）
 * 上持续打流，让示波器可以量：
 *
 *   ball 104 / 模组 43  BLE_UART0_TX   ← 本工具驱动力来源
 *   ball 105 / 模组 42  BLE_UART0_RX   ← 模组是否回话
 *   ball 106 / 模组 44  BLE_UART0_CTS  ← 模组是否给流控许可
 *   ball 107 / 模组 41  BLE_UART0_RTS  ← 主机是否放行
 *
 * 同时用 TIOCMGET 以 1ms 粒度记录 CTS/RTS/DSR/DCD 跳变并打时间戳，
 * 这样示波器上的沿和软件侧的时间戳可以对得上。
 *
 * 关键点：默认**不打开** CRTSCTS。若打开（-f），而模组的 CTS 是去断言的，
 * DW UART 的 AFE 会在硅片里把发送摁死 —— 示波器上一个波形都没有。
 * 想复现"被摁死"就加 -f；想看到波形就不要加。
 *
 * 注意：本工具会把 ttyS1 的 line discipline 从 n_hci 改回 N_TTY，
 * 于是正在跑的 hciattach 会失效。退出后要恢复：
 *     /etc/init.d/S35wifibt restart
 *
 * 编译（SDK 内自带工具链）：
 *   tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin/\
 *   arm-rockchip830-linux-uclibcgnueabihf-gcc -O2 -static -o uart_blast uart_blast.c
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <sys/select.h>

/* ---------------------------------------------------------------- termios2
 * uclibc 的 termios.h 里没有 BOTHER，也没有自定义波特率的接口。
 * 直接按 asm-generic/termbits.h 的布局自带一份，用 KTCSETS2 下发。
 * 布局：4×u32 + u8 + u8[19]（NCCS=19）+ 2×u32 = 44 字节。
 */
struct ktermios2_ {
	unsigned int c_iflag, c_oflag, c_cflag, c_lflag;
	unsigned char c_line;
	unsigned char c_cc[19];
	unsigned int c_ispeed, c_ospeed;
};
#define KTCGETS2 _IOR('T', 0x2A, struct ktermios2_)
#define KTCSETS2 _IOW('T', 0x2B, struct ktermios2_)
#ifndef BOTHER
#define BOTHER 0010000
#endif
#ifndef CBAUD
#define CBAUD 0010017
#endif
#ifndef CRTSCTS
#define CRTSCTS 020000000000
#endif
/* asm-generic/termbits.h：VMIN=6、VTIME=5，不是 0/1 */
#ifndef VMIN
#define VMIN 6
#endif
#ifndef VTIME
#define VTIME 5
#endif
/* 调制解调器线状态位（asm-generic/termios.h） */
#ifndef TIOCM_CTS
#define TIOCM_CTS 0x020
#endif
#ifndef TIOCM_RTS
#define TIOCM_RTS 0x004
#endif
#ifndef TIOCM_DSR
#define TIOCM_DSR 0x100
#endif
#ifndef TIOCM_CAR
#define TIOCM_CAR 0x040
#endif
#define N_TTY_DISC 0

/* 模式 */
#define MODE_MIX 0
#define MODE_AA  1
#define MODE_HCI 2

static volatile sig_atomic_t g_stop;

static void on_sigint(int sig) { (void)sig; g_stop = 1; }

static double now_s(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void hexdump(const unsigned char *b, int n)
{
	int i;
	for (i = 0; i < n; i++)
		printf("%02x ", b[i]);
}

int main(int argc, char **argv)
{
	const char *dev = "/dev/ttyS1";
	int baud = 1500000, mode = MODE_MIX, burst = 32, gap_ms = 20;
	int secs = 0, verbose = 0, use_cts = 0;
	int fd, n, i, ldisc = 0;
	struct ktermios2_ t2, t2_orig;
	int have_orig = 0;
	unsigned char *buf;		/* 发送突发 */
	unsigned char rbuf[512];	/* 接收，必须与 buf 分开，否则收到的数据
					 * 会在下一轮被当成突发发出去 */
	int buflen;
	unsigned long tx_total = 0, rx_total = 0;
	unsigned int cts_edges = 0, rx_events = 0;
	int last_cts = -1;
	double t0, t_last_stats;

	if (argc == 1)
		argc = 2, argv[1] = "-h";	/* 无参数 -> 打帮助 */

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "-d") && i + 1 < argc)      dev = argv[++i];
		else if (!strcmp(argv[i], "-b") && i + 1 < argc) baud = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-n") && i + 1 < argc) burst = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-g") && i + 1 < argc) gap_ms = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-t") && i + 1 < argc) secs = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-m") && i + 1 < argc) {
			const char *m = argv[++i];
			if (!strcmp(m, "aa")) mode = MODE_AA;
			else if (!strcmp(m, "hci")) mode = MODE_HCI;
			else mode = MODE_MIX;
		}
		else if (!strcmp(argv[i], "-f")) use_cts = 1;
		else if (!strcmp(argv[i], "-v")) verbose = 1;
		else if (!strcmp(argv[i], "-q")) verbose = 0;
		else {
			printf("用法: %s [-d 设备] [-b 波特率] [-m mix|aa|hci] "
			       "[-n 突发字节数] [-g 间隔ms] [-t 秒数,0=一直跑] [-f 开CRTSCTS] [-v]\n",
			       argv[0]);
			printf("  mix = 2 帧 H4 Reset + n 个 0x55（默认，既能看波形又能让模组有理由回话）\n");
			printf("  aa  = 纯 0x55，在示波器上是波特率/2 的方波，最适合看电平与走线\n");
			printf("  hci = 纯 H4 Reset 帧 01 03 0c 00\n");
			printf("  -f  : 打开硬件流控，用来复现\"CTS 去断言时发送被 AFE 摁死\"\n");
			return 1;
		}
	}

	if (burst < 1) burst = 1;

	fd = open(dev, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fd < 0) {
		fprintf(stderr, "打不开 %s: %s\n", dev, strerror(errno));
		return 1;
	}

	if (ioctl(fd, KTCGETS2, &t2_orig) == 0)
		have_orig = 1;
	else
		fprintf(stderr, "警告: 读不到原 termios(%s)，退出时无法恢复\n",
			strerror(errno));

	if (ioctl(fd, TIOCGETD, &ldisc) == 0 && ldisc != N_TTY_DISC) {
		printf("注意: %s 当前 line discipline = %d (15=n_hci，说明 hciattach 占着)。\n",
		       dev, ldisc);
		printf("      现在改为 N_TTY，hciattach 会失效；退出后跑 "
		       "/etc/init.d/S35wifibt restart 恢复。\n");
		ldisc = N_TTY_DISC;
		if (ioctl(fd, TIOCSETD, &ldisc) != 0)
			fprintf(stderr, "警告: 改 line discipline 失败: %s\n",
				strerror(errno));
	}

	/* 清空并从内核读回一份当前配置作为底子 */
	if (ioctl(fd, KTCGETS2, &t2) != 0) {
		fprintf(stderr, "KTCGETS2 失败: %s\n", strerror(errno));
		close(fd);
		return 1;
	}
	t2.c_iflag = 0;
	t2.c_oflag = 0;
	t2.c_lflag = 0;
	t2.c_line = N_TTY_DISC;
	t2.c_cflag &= ~(CBAUD | CSIZE | PARENB | CSTOPB | CRTSCTS);
	t2.c_cflag |= CS8 | CREAD | CLOCAL | BOTHER;
	if (use_cts)
		t2.c_cflag |= CRTSCTS;
	t2.c_ispeed = baud;
	t2.c_ospeed = baud;
	t2.c_cc[VMIN] = 0;
	t2.c_cc[VTIME] = 0;
	if (ioctl(fd, KTCSETS2, &t2) != 0) {
		fprintf(stderr, "KTCSETS2 失败: %s\n", strerror(errno));
		close(fd);
		return 1;
	}
	/* 读回确认，静默设错波特率是排查里最坑的一类 */
	if (ioctl(fd, KTCGETS2, &t2) == 0 && (int)t2.c_ospeed != baud)
		printf("警告: 内核实际波特率 = %u，不是请求的 %d\n", t2.c_ospeed, baud);
	tcflush(fd, TCIOFLUSH);

	/* 组突发缓冲 */
	buflen = burst;
	if (mode == MODE_MIX)
		buflen = 8 + burst;	/* 2 帧 H4 Reset + n 字节数据 */
	else if (mode == MODE_HCI)
		buflen = (burst / 4) * 4;	/* 整帧，避免写越界 */
	if (buflen < 4)
		buflen = 4;
	if (mode == MODE_MIX && buflen < 8)
		buflen = 8;
	buf = malloc(buflen);
	if (!buf) {
		close(fd);
		return 1;
	}
	if (mode == MODE_HCI || mode == MODE_MIX) {
		for (i = 0; i + 4 <= buflen; i += 4) {
			if (mode == MODE_MIX && i >= 8)
				break;
			buf[i + 0] = 0x01;	/* H4: 命令包 */
			buf[i + 1] = 0x03;	/* opcode 0x0c03 = Reset，小端 */
			buf[i + 2] = 0x0c;
			buf[i + 3] = 0x00;	/* 无参数 */
		}
	}
	if (mode == MODE_AA || mode == MODE_MIX) {
		int off = (mode == MODE_MIX) ? 8 : 0;
		memset(buf + off, 0x55, buflen - off);
	}

	printf("=== uart_blast ===\n");
	printf("设备 %s   波特率 %d   模式 %s   突发 %d 字节   间隔 %d ms   流控 %s\n",
	       dev, baud,
	       mode == MODE_AA ? "aa(纯0x55方波)" :
	       mode == MODE_HCI ? "hci(纯H4 Reset)" : "mix(H4 Reset + 0x55)",
	       buflen, gap_ms, use_cts ? "开(CRTSCTS)" : "关");
	printf("跑 %s。Ctrl-C 退出。\n\n",
	       secs ? "指定时长" : "到 Ctrl-C 为止");
	if (use_cts)
		printf("!! 已打开 CRTSCTS：若模组 CTS 去断言，这里写下去也不会有波形 !!\n\n");
	fflush(stdout);

	signal(SIGINT, on_sigint);
	signal(SIGTERM, on_sigint);

	t0 = now_s();
	t_last_stats = t0;

	while (!g_stop) {
		int sent = 0;

		if (secs && (now_s() - t0) >= secs)
			break;

		/* --- 发送整个突发，处理部分写 --- */
		while (sent < buflen && !g_stop) {
			n = write(fd, buf + sent, buflen - sent);
			if (n > 0) {
				sent += n;
				tx_total += n;
			} else if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
				fd_set wf;
				struct timeval tv = { 0, 2000 };
				FD_ZERO(&wf);
				FD_SET(fd, &wf);
				select(fd + 1, NULL, &wf, NULL, &tv);
			} else if (n < 0 && errno == EINTR) {
				continue;
			} else {
				fprintf(stderr, "\nwrite 失败: %s\n", strerror(errno));
				g_stop = 1;
			}
		}
		if (verbose)
			printf("[%9.3f] TX %d 字节\n", now_s() - t0, sent);

		/* --- 间隔期内 1ms 轮询调制解调器线 + 收数据 --- */
		{
			double gap_end = now_s() + gap_ms / 1000.0;
			while (!g_stop && now_s() < gap_end) {
				int m = 0;

				if (ioctl(fd, TIOCMGET, &m) == 0) {
					int cts = !!(m & TIOCM_CTS);
					if (cts != last_cts) {
						printf("[%9.3f] CTS %d -> %d   "
						       "(RTS=%d DSR=%d DCD=%d)\n",
						       now_s() - t0,
						       last_cts < 0 ? 0 : last_cts,
						       cts,
						       !!(m & TIOCM_RTS),
						       !!(m & TIOCM_DSR),
						       !!(m & TIOCM_CAR));
						if (last_cts >= 0)
							cts_edges++;
						last_cts = cts;
						fflush(stdout);
					}
				}

				n = read(fd, rbuf, sizeof(rbuf));
				if (n > 0) {
					rx_total += n;
					rx_events++;
					printf("[%9.3f] RX %d 字节: ", now_s() - t0, n);
					hexdump(rbuf, n);
					printf("\n");
					fflush(stdout);
				} else if (n < 0 && errno != EAGAIN &&
					   errno != EWOULDBLOCK && errno != EINTR) {
					fprintf(stderr, "\nread 失败: %s\n", strerror(errno));
					g_stop = 1;
				}

				usleep(1000);
			}
		}

		if (now_s() - t_last_stats >= 1.0) {
			int m = 0;
			ioctl(fd, TIOCMGET, &m);
			printf("[%9.3f] tx=%lu rx=%lu CTS=%d RTS=%d CTS跳变=%u RX事件=%u\n",
			       now_s() - t0, tx_total, rx_total,
			       !!(m & TIOCM_CTS), !!(m & TIOCM_RTS),
			       cts_edges, rx_events);
			fflush(stdout);
			t_last_stats = now_s();
		}
	}

	/* 收尾：把没排空的接收缓冲再读一次，别丢掉模组的回复 */
	for (i = 0; i < 8; i++) {
		n = read(fd, rbuf, sizeof(rbuf));
		if (n <= 0)
			break;
		rx_total += n;
		printf("[%9.3f] RX(收尾) %d 字节: ", now_s() - t0, n);
		hexdump(rbuf, n);
		printf("\n");
	}

	printf("\n=== 结束：tx=%lu rx=%lu CTS跳变=%u RX事件=%u ===\n",
	       tx_total, rx_total, cts_edges, rx_events);
	if (rx_total)
		printf("模组有回话。\n");
	else
		printf("模组一个字节都没回 —— 结合示波器看 TX 到底有没有到模组脚上。\n");

	if (have_orig && ioctl(fd, KTCSETS2, &t2_orig) != 0)
		fprintf(stderr, "警告: 恢复 termios 失败: %s\n", strerror(errno));
	free(buf);
	close(fd);
	printf("已恢复 termios。要把 hci0 弄回来：/etc/init.d/S35wifibt restart\n");
	return 0;
}
