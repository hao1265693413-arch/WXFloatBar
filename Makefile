TARGET := iphone:clang:15.0:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WXFloatBar

WXFloatBar_FILES = floater/WXGlassView.m floater/WXFloatBarManager.m floater/WXInjector.m
WXFloatBar_CFLAGS = -fobjc-arc -Ifloater -Wno-deprecated-declarations
WXFloatBar_FRAMEWORKS = UIKit QuartzCore CoreGraphics
WXFloatBar_LIBRARIES = substrate
WXFloatBar_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk
