# DW-012 V020 关闭 SMB/NMB 开机服务

- 源码分支：`codex/dw-012-v020-nand-validation`；功能提交 `ebf61369fd8724dc687cc562fbd0470c744f368b`。未 push、未烧录。
- 原因：启动日志的 `Starting SMB services` 和 `Starting NMB services` 来自 Buildroot Samba4 生成的 `/etc/init.d/S91smb`，分别拉起 `smbd` 文件共享和 `nmbd` 局域网名称服务。应用的双路 RTSP、可靠 GOP 上送、SD 本地录像以及充电/电量计不依赖 SMB/NMB；应用代码检索未发现 Samba/CIFS 调用。
- 实施：共享的 `luckfox-buildroot-ble-fix-post.sh` 仅在 `RK_KERNEL_DTS=rv1106g-dw-tly-v020.dts` 时移除打包 rootfs 的 `/etc/init.d/S91smb`。不改 V014 的启动行为，也不修改共享 Buildroot defconfig；Samba 二进制仍在 rootfs，本次关闭的是自动启动。
- 脚本验证：`bash -n`、`git diff --check` 通过；两个独立 `/tmp` rootfs 夹具分别用 V020、V014 DTS 运行脚本，V020 的 `S91smb` 消失，V014 保留。
- 构建：从干净功能提交运行 `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ./build.sh allsave`，退出码 0；日志 `/tmp/dw012-v020-smb-off-allsave.log` 明确打印 `V020 SMB/NMB autostart disabled` 和 `Running build_allsave succeeded`。镜像为 `IMAGE/IPC_SPI_NAND_TLY_V020_20260930.1010_RELEASE_TEST/IMAGES/update.img`，81,013,322 字节，SHA-256 `d9cf335afcbb4bd0969e3ee515354423fa827e1beee988009d0dafc1875fe47f`。
- 包内验证：`output/out/rootfs_uclibc_rv1106/etc/init.d/S91smb` 不存在。用 SDK 自带 `rkImageMaker -unpack`、`afptool -unpack` 双层解包至 `/tmp/dw012-smb-unpack.8rEwbP/`；包内 `rootfs.img` 与 `output/image/rootfs.img` 逐字节一致，SHA-256 `5f5cbc7231b8190b6e3344fc86c1d194c3e0d7d4b644d96d8e7a1c9451a1e813`。新镜像 rootfs 字节中找不到 `S91smb` 文件名，而前一候选 rootfs 中可找到；该字节扫描是辅助检查，主要依据仍是打包目录缺失与包内 rootfs 一致。V020 DTB SHA-256 `2677c4e2f7cdff23a85c36443529034f6566c1944f8362cc959f5c060e5f3704`，与第五版相同。
- Windows 候选目录：`C:\Users\henry\Documents\Linux\DW-TLY-V020-5.10.160-candidate-d9cf335a\`，含 `update.img`、`boot.img`、V020 DTB、`MANIFEST.txt`、`SHA256SUMS`。目标目录三份镜像文件的 `sha256sum -c SHA256SUMS` 均为 `OK`；`update.img` 与构建目录同哈希。前一候选未覆盖。
- 构建副作用：`allsave` 改写了唯一已跟踪文件 `project/app/wifi_app/wifi/librkwifibt.so`。构建前工作树干净；改写件已备份为 `/tmp/dw012-v020-smb-off-librkwifibt-built.so`（SHA-256 `5b7f73c6af09da871925bbc85766f9b5bf35d954f417488528218c86fb86188d`）并核对逐字节一致，再恢复仓库版本；源码工作树重新干净。
- 待验证：用户在对应 V020 NAND 验证板自行烧录后，核对串口不再打印 SMB/NMB 启动信息、`smbd`/`nmbd` 不运行，且 ADB、RTSP、SD、本次电源驱动功能正常。当前只有静态与构建证据，不能声称实板通过；V015 eMMC 量产适配未由此验证。
