ifeq ($(APP_PARAM), )
    APP_PARAM:=../Makefile.param
    include $(APP_PARAM)
endif

export LC_ALL=C
SHELL:=/bin/bash

# 单文件小工具，不走 tarball/configure 那一套，直接调交叉 gcc。
# 落地路径（见 build.sh __PACKAGE_RESOURCES）：
#   install_out/usr/bin/dw_powerkey          -> /oem/usr/bin/dw_powerkey
#   install_out/etc/init.d/S45dwpowerkey     -> /oem/usr/etc/init.d/S45dwpowerkey
#     后者会被 /oem/usr/bin/RkLunch.sh 里的 rcS 循环（遍历 /oem/usr/etc/init.d/S??*）
#     拉起来，和 /oem 下别的服务一个路子，不占 rootfs 的 init.d。

CURRENT_DIR := $(shell pwd)
PKG_BIN_INSTALL_DIR := install_out

CFLAGS += $(RK_APP_CROSS_CFLAGS) -O2 -Wall

TARGET := dw_powerkey

all: $(TARGET)
	@mkdir -p $(CURRENT_DIR)/$(PKG_BIN_INSTALL_DIR)/usr/bin \
		$(CURRENT_DIR)/$(PKG_BIN_INSTALL_DIR)/etc/init.d
	@cp -fa $(CURRENT_DIR)/$(TARGET) $(CURRENT_DIR)/$(PKG_BIN_INSTALL_DIR)/usr/bin/
	@cp -fa $(CURRENT_DIR)/S45dwpowerkey $(CURRENT_DIR)/$(PKG_BIN_INSTALL_DIR)/etc/init.d/
	@chmod +x $(CURRENT_DIR)/$(PKG_BIN_INSTALL_DIR)/usr/bin/$(TARGET) \
		$(CURRENT_DIR)/$(PKG_BIN_INSTALL_DIR)/etc/init.d/S45dwpowerkey
	$(call MAROC_COPY_PKG_TO_APP_OUTPUT, $(RK_APP_OUTPUT), $(PKG_BIN_INSTALL_DIR))

$(TARGET): $(TARGET).c
	$(RK_APP_CROSS)-gcc $(CFLAGS) -o $@ $<

clean:
	@rm -rf $(CURRENT_DIR)/$(TARGET) $(CURRENT_DIR)/$(PKG_BIN_INSTALL_DIR)

distclean: clean

info:
	@echo "dw_powerkey: BTN_nQON 长按关机（阈值在 /oem/usr/etc/init.d/S45dwpowerkey 里）"

.PHONY: all clean distclean info
