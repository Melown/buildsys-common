# Debian packaging related stuff

include $(BUILDSYS_COMMON_ROOT)deb-releases.mk

# use given customer's debian directory and release
DEB_CUSTOMER ?= internal
DEB_RELEASE ?= $(call deb_release)
DEB_CHANGES_RELEASE ?= $(DEB_TRANSLATE_RELEASE_$(DEB_RELEASE))
DEB_CHANGES_RELEASE_OPTION ?= --changes-option=-DDistribution="${DEB_CHANGES_RELEASE}"

# default dput configuration
DPUT_DISTRIBUTION ?= melown
DPUT_CONFIG ?= $(BUILDSYS_COMMON_ROOT)dput.cf

# where is tar?
TAR_BINARY=$(shell (which tar))

# Default settings
BUILD_BINARY_PACKAGE ?= YES
BUILD_SOURCE_PACKAGE ?= NO

ifeq ("","$(wildcard /proc/cpuinfo)")
	CPU_COUNT = 1
else
	CPU_COUNT = $(shell grep -c ^processor /proc/cpuinfo)
endif

DPKG_SOURCE_OPTIONS=$(shell $(BUILDSYS_COMMON_ROOT)/generate-exludes.sh \
							$(notdir $(BUILDSYS_SRC_ROOT)))

debbin: deb_prepare
	@(echo "*** Building debian binary package for $(DEB_CHANGES_RELEASE) using configuration for $(DEB_RELEASE).")
	@(dpkg-buildpackage $(DEB_CHANGES_RELEASE_OPTION) -b -j$(CPU_COUNT) $(DEB_OVERRIDE))

debsrc: deb_prepare
	@(echo "*** Building debian source package for $(DEB_CHANGES_RELEASE) using configuration for $(DEB_RELEASE).")
	@(export PATH=$(BUILDSYS_COMMON_ROOT):$$PATH TAR_BINARY=$(TAR_BINARY); \
		dpkg-buildpackage $(DEB_CHANGES_RELEASE_OPTION) -S $(DEB_OVERRIDE) $(DPKG_SOURCE_OPTIONS))

# deb target (conditionally) depends on debbin and debsrc
ifeq ($(BUILD_BINARY_PACKAGE),YES)
deb: debbin
endif
ifeq ($(BUILD_SOURCE_PACKAGE),YES)
deb: debsrc
endif

debclean: deb_prepare
	@(unset MAKELEVEL; unset MAKEFLAGS;	fakeroot ./debian/rules clean)

dput: deb_prepare
	dput -c $(DPUT_CONFIG) $(DPUT_DISTRIBUTION) $(call deb_changes_file)

dversion: deb_prepare
	@echo $(call deb_version)

# we need to use some magic to mimic old simple behaviour:
#     * plain version increment: --increment + --no-auto-nmu
#     * grab info from previous entries: --release-heuristic log
#     * no addition stuff in version (like ubuntu on ubuntu): use fake vendor
dch: deb_prepare
	@dch --increment --release-heuristic log --no-auto-nmu --vendor Melown

debsign: deb_prepare
	@(debsign $(call deb_changes_file))

deb_prepare:
	@$(BUILDSYS_COMMON_ROOT)/deblink.sh $(DEB_CUSTOMER) $(DEB_RELEASE)

.PHONY: deb debbin debsrc debclean dput dtag deb_prepare deb_show_config

# supporting macros
define deb_changes_file
$(shell (dpkg-parsechangelog; \
	echo -n "Architecture: "; dpkg-architecture -qDEB_BUILD_ARCH) \
	| gawk '/^Version:/ { version=$$2; } /^Source:/ { source=$$2; } /^Architecture:/ { arch=$$2; } END { printf("../%s_%s_%s.changes\n", source, version, arch); }')
endef

define deb_tag
$(shell dpkg-parsechangelog | \
	gawk '/^Version:/ { version=$$2; } /^Source:/ { source=$$2; } END { printf("%s %s\n", source, version); }')
endef

define deb_version
$(shell dpkg-parsechangelog | \
	gawk '/^Version:/ { print $$2; }')
endef

define deb_release
$(shell lsb_release -c 2>/dev/null | gawk '/Codename:/ { print $$2 }')
endef

# compose DEB_OVERRIDE from DEB_OVERRIDE_* variables
ifdef DEB_OVERRIDE_RELEASE
	DEB_OVERRIDE:="$(DEB_OVERRIDE) --changes-option=-DDistribution=\"$(DEB_OVERRIDE_RELEASE)\""
endif
ifdef DEB_OVERRIDE_CHANGED_BY
	DEB_OVERRIDE:="$(DEB_OVERRIDE) --changes-option=-DChanged-By=\"$(DEB_OVERRIDE_CHANGED_BY)\""
endif

deb_show_config:
	@echo DEB_CUSTOMER = $(DEB_CUSTOMER)
	@echo DEB_RELEASE = $(DEB_RELEASE)
