// SPDX-License-Identifier: GPL-2.0
/*
 * dw_powerkey —— DW-TLY-V020：长按 BTN_nQON 关机
 *
 * 一次"关机"由两半组成，本程序只是前半：
 *   本程序：按键按住多久算长按；到点走**正规关机**——让 /sbin/poweroff 去
 *           通知 init，由 init 停服务、umount，最后由 init 调 reboot(RB_POWER_OFF)。
 *   内核：  bq256xx_charger.c 认领 pm_power_off，在上面那次 reboot(RB_POWER_OFF)
 *           走完 kernel_power_off() 的其余步骤之后、最后一步才写 BQ25601 的
 *           BATFET_DIS，真的把电断掉。RV1106 没有 PMIC，缺了这一步"关机"只会
 *           停住 CPU，模组和充电芯片继续耗电。
 *
 * 为什么要绕 init 一圈，而不是自己直接 reboot(RB_POWER_OFF)：
 *   reboot(2) 那条内核路径里**没有 sync、没有 umount**，只有 device_shutdown/
 *   syscore_shutdown 这类设备回调；文件系统收尾是用户态的事：
 *   busybox 的 poweroff = sync() + kill(1, SIGUSR2)，init 收到 SIGUSR2 后跑
 *   /etc/init.d/rcK、swapoff、umount -a（都是 inittab 的 ::shutdown: 行），
 *   最后才 reboot(RB_POWER_OFF)。直接调 reboot(2) 等于跳过 umount，
 *   UBIFS 会留下脏的挂载状态。
 *
 * 阈值为什么取 3 s：
 *   按键（BTN_nQON，ball 95 = GPIO1_C0）和 U3 pin12（/QON）是同一个网络，
 *   而 BQ25601 的 /QON 被**持续拉低** tQON_RST = 8 s(min)~12 s(max)（手册，
 *   且只在没插适配器、BATFET_DIS=0 时生效）会硬复位整机 —— 注意计时是从
 *   按下那一刻起的，所以"阈值 + 整个关机流程"都得在 8 s 内跑完。
 *   正规关机的余量 = 8 - 3 = 5 s，本程序给 init 的宽限是 GRACE_MS（4 s）：
 *   3 + 4 = 7 s，仍在 8 s 之内。超了宽限就自己 sync + reboot(RB_POWER_OFF)
 *   兜底：宁可少 umount 一次，也不要撞上硬件复位 —— 那是「重启」，不是关机，
 *   而且一样什么都没来得及同步。那条硬复位通路是系统卡死时唯一的退路，
 *   别去关它（BQ25601 REG07 的 BATFET_RST_EN 保持 1）。
 *
 * 交互：到点即动，不等松手 —— 板子几秒后自己黑掉，反馈就是它本身；
 *       不足阈值就松手 = 取消。
 *
 * 用法：
 *   dw_powerkey [-t 秒] [-d /dev/input/eventN] [-n] [-v]
 *     -t N   阈值秒数（默认 3，可带小数）
 *     -d DEV 指定输入设备（默认自动找 name = "gpio-keys" 的那个）
 *     -n     只打印，不真的关机（台架上验阈值/极性用）
 *     -v     打印每个按键事件（验极性：按下应上报 value 1，松开 value 0）
 */

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define DEV_DIR		"/dev/input"
#define DEV_PREFIX	"event"
#define DEV_NAME	"gpio-keys"
#define DEV_PATH_MAX	320	/* dirent 名字最长 255，够放 DEV_DIR "/" 前缀 */
#define DEFAULT_HOLD_S	3.0

static int opt_verbose;
static int opt_dry_run;
static volatile sig_atomic_t stop;

static long long now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* 按名字找 gpio-keys 对应的 /dev/input/eventN：设备号不保证稳定，不写死 */
static int find_device(char *path, size_t path_len)
{
	struct dirent *de;
	DIR *dir;

	dir = opendir(DEV_DIR);
	if (!dir) {
		fprintf(stderr, "dw_powerkey: open %s: %s\n", DEV_DIR,
			strerror(errno));
		return -1;
	}

	while ((de = readdir(dir)) != NULL) {
		char p[DEV_PATH_MAX], name[256] = {0};
		int fd;

		if (strncmp(de->d_name, DEV_PREFIX, strlen(DEV_PREFIX)))
			continue;

		snprintf(p, sizeof(p), DEV_DIR "/%s", de->d_name);
		fd = open(p, O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;

		if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) < 0 ||
		    strcmp(name, DEV_NAME)) {
			close(fd);
			continue;
		}

		close(fd);
		closedir(dir);
		snprintf(path, path_len, "%s", p);
		return 0;
	}

	closedir(dir);
	return -1;
}

static void on_signal(int sig)
{
	(void)sig;
	stop = 1;
}

/* 交给 init 之后的宽限；超过就自己断电兜底。见文件头 3 s 的算法 */
#define GRACE_MS	4000
#define GRACE_POLL_MS	200

/*
 * 到点了。走正规关机：/sbin/poweroff 只做 sync + 发信号给 init，真正停服务、
 * umount 的是 init；init 最后自己调 reboot(RB_POWER_OFF)，内核一路走到
 * kernel_power_off() 的末尾才调 pm_power_off —— 也就是充电驱动里那次
 * BATFET_DIS。断电落在最后一刻，前面该同步的都同步完了。
 *
 * 为什么要兜底：init 要是没起来或者卡住，这条链子就断在半路，而硬件 /QON
 * 的 8 s 计时还在走。所以这里等 GRACE_MS；等不到就自己 sync +
 * reboot(RB_POWER_OFF)（还是会有 device_shutdown，只是没有 umount）。
 *
 * 等待期间忽略 SIGTERM：init 收尾时会 kill(-1)，被它顺手打死的话兜底就没了。
 * 真走到 SIGKILL 那一步时 init 自己也快到 reboot 了，无所谓。
 */
static void fire(double held_s)
{
	int i, waited;
	pid_t pid;

	fprintf(stderr, "dw_powerkey: held %.1fs >= threshold, powering off\n",
		held_s);

	if (opt_dry_run) {
		fprintf(stderr, "dw_powerkey: dry-run, not powering off\n");
		return;
	}

	pid = fork();
	if (pid == 0) {
		execl("/sbin/poweroff", "poweroff", NULL);
		_exit(127);	/* exec 失败才用 127，父进程据此提前兜底 */
	}
	if (pid < 0)
		fprintf(stderr, "dw_powerkey: fork: %s\n", strerror(errno));

	signal(SIGTERM, SIG_IGN);
	signal(SIGINT, SIG_IGN);

	/*
	 * 注意 /sbin/poweroff 是"发完信号就退出"，退得很快 —— 它退不代表关机
	 * 完成，只是说明 init 开始干活了。所以这里必须**照样等满**宽限期：
	 * 用 reaped 单独记"已经回收过子进程"，别拿 pid 当标志位去改循环条件。
	 */
	for (i = 0, waited = 0; i < GRACE_MS / GRACE_POLL_MS; i++) {
		int st;

		if (!waited && pid > 0) {
			if (waitpid(pid, &st, WNOHANG) == pid) {
				waited = 1;
				if (WIFEXITED(st) &&
				    WEXITSTATUS(st) == 127) {
					fprintf(stderr, "dw_powerkey: 起不来 "
						"/sbin/poweroff\n");
					break;
				}
			}
		}
		usleep(GRACE_POLL_MS * 1000);
	}

	fprintf(stderr, "dw_powerkey: 等了 %d ms 系统还没关掉，sync 后"
		"直接断电兜底\n", i * GRACE_POLL_MS);
	sync();
	reboot(RB_POWER_OFF);

	fprintf(stderr, "dw_powerkey: reboot(RB_POWER_OFF) returned: %s "
		"(pm_power_off 没有被认领？充电驱动没起来？)\n", strerror(errno));
	exit(1);
}

int main(int argc, char **argv)
{
	struct sigaction sa;
	struct pollfd pfd;
	char dev[DEV_PATH_MAX] = {0};
	double hold_s = DEFAULT_HOLD_S;
	long long down_ms = 0;
	int down = 0;
	int fd, c;

	while ((c = getopt(argc, argv, "t:d:nvh")) != -1) {
		switch (c) {
		case 't':
			hold_s = atof(optarg);
			break;
		case 'd':
			snprintf(dev, sizeof(dev), "%s", optarg);
			break;
		case 'n':
			opt_dry_run = 1;
			break;
		case 'v':
			opt_verbose = 1;
			break;
		default:
			fprintf(stderr, "usage: %s [-t sec] [-d dev] [-n] [-v]\n",
				argv[0]);
			return 1;
		}
	}

	if (hold_s <= 0 || hold_s >= 8) {
		fprintf(stderr, "dw_powerkey: 阈值 %g s 不合理："
			"必须 > 0 且明显小于硬件的 8 s（见文件头注释）\n", hold_s);
		return 1;
	}

	if (!dev[0] && find_device(dev, sizeof(dev))) {
		fprintf(stderr, "dw_powerkey: 在 %s 里找不到 name=%s 的设备\n",
			DEV_DIR, DEV_NAME);
		return 1;
	}

	fd = open(dev, O_RDONLY);
	if (fd < 0) {
		fprintf(stderr, "dw_powerkey: open %s: %s\n", dev,
			strerror(errno));
		return 1;
	}

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_signal;
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);

	fprintf(stderr, "dw_powerkey: %s, 阈值 %.1fs%s%s\n", dev, hold_s,
		opt_dry_run ? ", dry-run" : "", opt_verbose ? ", verbose" : "");

	pfd.fd = fd;
	pfd.events = POLLIN;

	while (!stop) {
		int timeout = -1;
		struct input_event ev;
		ssize_t n;

		/* 按住期间按剩余时间醒来，到点就动手 */
		if (down)
			timeout = (int)(hold_s * 1000) - (int)(now_ms() - down_ms);
		if (down && timeout <= 0) {
			fire((double)(now_ms() - down_ms) / 1000);
			/* dry-run 才会走到这里：复位状态，避免一直重触发 */
			down = 0;
			continue;
		}

		if (poll(&pfd, 1, timeout) <= 0)
			continue;

		n = read(fd, &ev, sizeof(ev));
		if (n != sizeof(ev)) {
			if (errno == EINTR || errno == EAGAIN)
				continue;
			fprintf(stderr, "dw_powerkey: read: %s\n",
				strerror(errno));
			return 1;
		}

		if (ev.type != EV_KEY || ev.code != KEY_POWER)
			continue;

		if (opt_verbose)
			fprintf(stderr, "dw_powerkey: event KEY_POWER value=%d\n",
				ev.value);

		if (ev.value == 1) {
			down = 1;
			down_ms = now_ms();
		} else if (ev.value == 0) {
			if (down)
				fprintf(stderr, "dw_powerkey: 按住 %lld ms，"
					"不足阈值，取消\n", now_ms() - down_ms);
			down = 0;
		}
		/* value == 2 是自动重复，忽略 */
	}

	return 0;
}
