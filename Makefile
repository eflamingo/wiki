# 
SHELL = /bin/sh
INSTALL = /usr/bin/install
INSTALL_PROGRAM = $(INSTALL)
INSTALL_DATA = $(INSTALL) -m 644
#include Makefile.conf


DIRS = static perl
NORMALDIRS = static
PERLDIRS = perl

# the sets of directories to do various things in
BUILDDIRS = $(DIRS:%=build-%)
INSTALLDIRS = $(NORMALDIRS:%=install-%)
CLEANDIRS = $(NORMALDIRS:%=clean-%)
TESTDIRS = $(DIRS:%=test-%)

# perl's make install appends perlpod, which is bad for debuild
PERLINSTALLDIRS = $(PERLDIRS:%=install-%)
PERLCLEANDIRS = $(PERLDIRS:%=clean-%)

all: $(BUILDDIRS)
$(DIRS): $(BUILDDIRS)
$(BUILDDIRS):
	$(MAKE) -C $(@:build-%=%)

# the utils need the libraries in dev built first
#build-utils: build-dev

install: $(INSTALLDIRS) $(PERLINSTALLDIRS) all
$(INSTALLDIRS):
	$(MAKE) -C $(@:install-%=%) install
$(PERLINSTALLDIRS):
	$(MAKE) -C $(@:install-%=%) pure_install DESTDIR=$(DESTDIR)

test: $(TESTDIRS) all
$(TESTDIRS): 
	$(MAKE) -C $(@:test-%=%) test

clean: $(CLEANDIRS) $(PERLCLEANDIRS)
$(CLEANDIRS): 
	$(MAKE) -C $(@:clean-%=%) clean
$(PERLCLEANDIRS):
	(cd perl && perl Makefile.PL)
	$(MAKE) -C $(@:clean-%=%) clean
	$(RM) perl/Makefile.old

.PHONY: subdirs $(DIRS)
.PHONY: subdirs $(NORMALDIRS)
.PHONY: subdirs $(PERLDIRS)
.PHONY: subdirs $(BUILDDIRS)
.PHONY: subdirs $(INSTALLDIRS)
.PHONY: subdirs $(PERLINSTALLDIRS)
.PHONY: subdirs $(PERLCLEANDIRS)
.PHONY: subdirs $(TESTDIRS)
.PHONY: subdirs $(CLEANDIRS)
.PHONY:  all install clean test

