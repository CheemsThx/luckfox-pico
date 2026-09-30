# DW-012 V015 关闭 SMB/NMB 开机服务

- 源码分支：`codex/dw-012-v015-emmc-adaptation`；功能提交 `5e237add4a9208dfce91c281d26e6fc7cc78eed7`。未 push、未烧录。V015 eMMC 供电和焊球仍待硬件签核，不能当作可烧录量产件。
- 原因：继承的 `luckfox_pico_w_defconfig` 启用 `BR2_PACKAGE_SAMBA4=y`，rootfs 的 `/etc/init.d/S91smb` 会启动 `smbd` 与 `nmbd`。当前视频、SD 本地录像和传感器业务不依赖 SMB/NMB。
- 实施：V015 BoardConfig 专属选择 `dw-tly-v015-disable-smb-post.sh`，在镜像后处理中只删除打包 rootfs 的 `S91smb`。共享 Buildroot defconfig 未改，其他板型不受影响；Samba 二进制仍随包，关闭的是开机自动启动。
- 脚本验证：`bash -n`、`git diff --check` 通过；独立 `/tmp` rootfs 夹具运行后 `S91smb` 消失。
- 构建：从干净功能提交执行 `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ./build.sh allsave`，退出码 0；日志 `/tmp/dw012-v015-smb-off-allsave.log` 含 `SMB/NMB autostart disabled`。镜像 `IMAGE/IPC_EMMC_BUILDROOT_RV1106_DW_TLY_V015_20260930.1022_RELEASE_TEST/IMAGES/update.img`，476,355,146 字节，SHA-256 `de90f9deea52bb3e904999dddb3a03f414d54752a13d3e14e31e884e869bf68f`。
- 包内验证：打包目录无 `etc/init.d/S91smb`。使用 SDK `rkImageMaker -unpack` 与 `afptool -unpack` 双层解包到 `/tmp/dw012-v015-smb-unpack.mlE6RE/`；包内 ext4 `rootfs.img` 与 `output/image/rootfs.img` 逐字节一致，SHA-256 `552c62f16e16fb1d89c9cb99d788ef998c6e7802fe1885552ce614c9e0710f9c`。`debugfs` 对包内镜像的 `/etc/init.d/S91smb` 返回 `File not found`，同时可读取其他启动脚本 `/etc/init.d/S20linkmount`。`smbd`、`nmbd` 二进制仍可在该 rootfs 中找到。构建后源码工作树干净。
- 待验证：V015 板与硬件签核尚缺；未进行烧录或实机启动检查。SMB/NMB 不自动运行的实板结论须待匹配 V015 硬件验证。
