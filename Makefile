# --- configuration ---

# --- build Linux kernel ---

.PHONY: linux linux-patch

linux: linux-stable/arch/riscv/boot/Image

CROSS_COMPILE_LINUX = /usr/bin/riscv64-linux-gnu-

linux-patch: patches/linux.patch patches/fpga-axi-sdc.c patches/fpga-axi-eth.c patches/linux.config
	if [ -s patches/linux.patch ] ; then cd linux-stable && ( git apply -R --check ../patches/linux.patch 2>/dev/null || git apply ../patches/linux.patch ) ; fi
	cp -p patches/fpga-axi-eth.c  linux-stable/drivers/net/ethernet
	cp -p patches/fpga-axi-sdc.c  linux-stable/drivers/mmc/host
	cp -p patches/fpga-axi-uart.c linux-stable/drivers/tty/serial
	cp -p patches/linux.config linux-stable/.config

linux-stable/arch/riscv/boot/Image: linux-patch
	make -C linux-stable ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE_LINUX) oldconfig
	make -C linux-stable ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE_LINUX) all


# --- build U-Boot ---

ROOTFS ?= SD
ROOTFS_URL ?= 192.168.0.100:/home/nfsroot/192.168.0.243

.PHONY: u-boot u-boot-patch

u-boot: u-boot/u-boot-nodtb.bin

U_BOOT_SRC = $(wildcard patches/u-boot/*/*) \
  patches/u-boot/vivado_riscv64_defconfig \
  patches/u-boot/vivado_riscv64.h \
  patches/u-boot.patch

u-boot/configs/vivado_riscv64_defconfig: patches/u-boot/vivado_riscv64_defconfig Makefile
	cp patches/u-boot/vivado_riscv64_defconfig u-boot/configs
ifeq ($(ROOTFS),NFS)
	echo 'CONFIG_USE_BOOTARGS=y' >>u-boot/configs/vivado_riscv64_defconfig
	echo 'CONFIG_BOOTCOMMAND="booti $${kernel_addr_r} - $${fdt_addr}"' >>u-boot/configs/vivado_riscv64_defconfig
	echo 'CONFIG_BOOTARGS="root=/dev/nfs rootfstype=nfs rw nfsroot='$(ROOTFS_URL)',nolock,vers=4,tcp ip=dhcp earlycon console=ttyAU0,115200n8 locale.LANG=en_US.UTF-8"' >>u-boot/configs/vivado_riscv64_defconfig
else ifeq ($(JTAG_BOOT),1)
	echo 'CONFIG_USE_BOOTARGS=y' >>u-boot/configs/vivado_riscv64_defconfig
	echo 'CONFIG_BOOTCOMMAND="booti $${kernel_addr_r} $${ramdisk_addr_r} $${fdt_addr}"' >>u-boot/configs/vivado_riscv64_defconfig
	echo 'CONFIG_BOOTARGS="ro root=UUID=68d82fa1-1bb5-435f-a5e3-862176586eec earlycon initramfs.runsize=24M locale.LANG=en_US.UTF-8"' >>u-boot/configs/vivado_riscv64_defconfig
endif

u-boot-patch: u-boot/configs/vivado_riscv64_defconfig
	if [ -s patches/u-boot.patch ] ; then cd u-boot && ( git apply -R --check ../patches/u-boot.patch 2>/dev/null || git apply ../patches/u-boot.patch ) ; fi
	cp -p -r patches/u-boot/vivado_riscv64 u-boot/board/xilinx
	cp -p patches/u-boot/vivado_riscv64.h u-boot/include/configs

u-boot/u-boot-nodtb.bin: u-boot-patch $(U_BOOT_SRC)
	make -C u-boot CROSS_COMPILE=$(CROSS_COMPILE_LINUX) BOARD=vivado_riscv64 vivado_riscv64_config
	make -C u-boot \
	  BOARD=vivado_riscv64 \
	  CC=$(CROSS_COMPILE_LINUX)gcc-8 \
	  CROSS_COMPILE=$(CROSS_COMPILE_LINUX) \
	  KCFLAGS='-O1 -gno-column-info' \
	  all


# --- build RISC-V Open Source Supervisor Binary Interface (OpenSBI) ---

bootloader: workspace/boot.elf

workspace/boot.elf: opensbi/build/platform/vivado-risc-v/firmware/fw_payload.elf
	mkdir -p workspace
	cp $< $@

opensbi/build/platform/vivado-risc-v/firmware/fw_payload.elf: $(wildcard patches/opensbi/*) u-boot/u-boot-nodtb.bin
	mkdir -p opensbi/platform/vivado-risc-v
	cp -p patches/opensbi/* opensbi/platform/vivado-risc-v
	make -C opensbi CROSS_COMPILE=$(CROSS_COMPILE_LINUX) PLATFORM=vivado-risc-v \
	 FW_PAYLOAD_PATH=`realpath u-boot/u-boot-nodtb.bin`

