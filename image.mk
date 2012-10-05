ifeq ($(TARGET_USE_IAGO),true)

LOCAL_PATH := $(call my-dir)

iago_base := $(PRODUCT_OUT)/iago
iago_ramdisk_root := $(iago_base)/ramdisk
iago_iso_root := $(iago_base)/root
iago_ramdisk := $(iago_base)/ramdisk.img
iago_images_root := $(iago_base)/images
iago_images_sfs := $(iago_base)/images.sfs
iago_iso_image := $(PRODUCT_OUT)/liveimg.iso

system_sfs := $(iago_base)/system.sfs
data_sfs := $(iago_base)/userdata.sfs

define create-sfs
	$(hide) PATH=/sbin:/usr/sbin:$(PATH) mksquashfs $(1) $(2) -no-recovery -noappend
endef

iago_images_deps := \
        $(INSTALLED_USERDATAIMAGE_TARGET) \
	$(INSTALLED_BOOTIMAGE_TARGET) \
	$(INSTALLED_RECOVERYIMAGE_TARGET) \

ifeq ($(TARGET_USERIMAGES_SPARSE_EXT_DISABLED),false)
# need to convert sparse images back to normal ext4
iago_sparse_images_deps += \
	$(INSTALLED_SYSTEMIMAGE) \

iago_images_deps_bin += \
	$(HOST_OUT_EXECUTABLES)/simg2img \

else
iago_images_deps += \
	$(INSTALLED_SYSTEMIMAGE) \

endif

ifeq ($(TARGET_STAGE_DROIDBOOT),true)
iago_images_deps += $(DROIDBOOT_BOOTIMAGE)
endif

ifeq ($(TARGET_USE_SYSLINUX),true)
iago_images_syslinux_files = $(TARGET_SYSLINUX_FILES)
iago_images_syslinux_bin = \
        $(call intermediates-dir-for,EXECUTABLES,android_syslinux)/android_syslinux

ifneq ($(TARGET_SYSLINUX_CONFIG_TEMPLATE),)
iago_images_syslinux_conf = $(TARGET_SYSLINUX_CONFIG_TEMPLATE)
else
$(warning TARGET_SYSLINUX_CONFIG_TEMPLATE is not set. Installer may not be able to generate correct SYSLINUX config file.)
endif

endif # TARGET_USE_SYSLINUX

iago_isolinux_files := \
	$(SYSLINUX_BASE)/isolinux.bin \
	$(SYSLINUX_BASE)/vesamenu.c32 \
	$(LOCAL_PATH)/splash.png \
	$(iago_base)/isolinux.cfg \

$(iago_images_sfs): \
		$(iago_images_deps) \
		$(iago_images_deps_bin) \
		$(iago_sparse_images_deps) \
		$(iago_images_syslinux_files) \
		$(iago_images_syslinux_conf) \
		$(iago_images_syslinux_bin) \
		| $(ACP) \

	$(hide) rm -rf $(iago_images_root)
	$(hide) mkdir -p $(iago_images_root)
	$(hide) mkdir -p $(dir $@)
	$(hide) $(ACP) -f $(iago_images_deps) $(iago_images_root)
ifeq ($(TARGET_USERIMAGES_SPARSE_EXT_DISABLED),false)
	$(hide) $(foreach _simg,$(iago_sparse_images_deps), \
		$(HOST_OUT_EXECUTABLES)/simg2img $(_simg) $(iago_images_root)/`basename $(_simg)`; \
		)
endif
ifeq ($(TARGET_USE_SYSLINUX),true)
	$(hide) mkdir -p $(iago_images_root)/syslinux
	$(hide) mkdir -p $(iago_images_root)/syslinux/files
	$(hide) mkdir -p $(iago_images_root)/syslinux/bin
	$(hide) $(ACP) -f $(iago_images_syslinux_files) \
		$(iago_images_root)/syslinux/files
ifneq ($(TARGET_SYSLINUX_CONFIG_TEMPLATE),)
	$(hide) $(ACP) -f $(iago_images_syslinux_conf) \
		$(iago_images_root)/syslinux/files/syslinux.cfg
endif
	$(hide) $(ACP) -f $(iago_images_syslinux_bin) \
		$(iago_images_root)/syslinux/bin
	$(hide) chmod 0755 $(iago_images_root)/syslinux/bin/*
endif
	$(call create-sfs,$(iago_images_root),$@)

$(iago_base)/isolinux.cfg: $(LOCAL_PATH)/isolinux.cfg
	$(hide) mkdir -p $(iago_base)
	$(hide) sed "s|CMDLINE|$(BOARD_KERNEL_CMDLINE)|" $^ > $@

$(iago_ramdisk): \
		$(LOCAL_PATH)/image.mk \
		$(INSTALLED_RAMDISK_TARGET) \
		$(MKBOOTFS) \
		$(iago_base)/preinit \
		| $(MINIGZIP) \

	$(hide) rm -rf $(iago_ramdisk_root)
	$(hide) mkdir -p $(iago_ramdisk_root)
	$(hide) $(ACP) -rf $(TARGET_ROOT_OUT)/* $(iago_ramdisk_root)
	$(hide) mv $(iago_ramdisk_root)/init $(iago_ramdisk_root)/init2
	$(hide) $(ACP) $(iago_base)/preinit $(iago_ramdisk_root)/init
	$(hide) mkdir -p $(iago_ramdisk_root)/installmedia
	$(hide) mkdir -p $(iago_ramdisk_root)/tmp
	$(hide) echo "import init.iago.rc" >> $(iago_ramdisk_root)/init.rc
	$(hide) sed -i -r 's/^[\t ]*(mount_all|mount yaffs|mount ext).*//g' $(iago_ramdisk_root)/init*.rc
	$(hide) $(ACP) $(LOCAL_PATH)/init.iago.rc $(iago_ramdisk_root)
	$(hide) $(MKBOOTFS) $(iago_ramdisk_root) | $(MINIGZIP) > $@

# TODO: Add 'genisoimage' to the build
$(iago_iso_image): \
		$(LOCAL_PATH)/image.mk \
		$(iago_ramdisk) \
		$(iago_images_sfs) \
		$(iago_isolinux_files) \
		$(INSTALLED_KERNEL_TARGET) \
		$(HOST_OUT_EXECUTABLES)/isohybrid \
		| $(ACP) \

	$(hide) rm -rf $(iago_iso_root)
	$(hide) mkdir -p $(iago_iso_root)
	$(hide) $(ACP) -f $(iago_ramdisk) $(iago_iso_root)/ramdisk.img
	$(hide) $(ACP) -f $(INSTALLED_KERNEL_TARGET) $(iago_iso_root)/kernel
	$(hide) touch $(iago_iso_root)/iago-cookie
	$(hide) $(ACP) -f $(iago_images_sfs) $(iago_iso_root)
	$(hide) mkdir -p $(iago_iso_root)/isolinux
	$(hide) mkdir -p $(iago_iso_root)/images
	$(hide) $(ACP) -f $(iago_isolinux_files) $(iago_iso_root)/isolinux/
	$(hide) genisoimage -vJURT -b isolinux/isolinux.bin -c isolinux/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		-input-charset utf-8 -V "IAGO Android Live/Installer CD" \
		-o $@ $(iago_iso_root)
	$(hide) $(HOST_OUT_EXECUTABLES)/isohybrid $@

.PHONY: liveimg
liveimg: $(iago_iso_image)

endif # TARGET_USE_IAGO
