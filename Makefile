VERSION=1.0.1
DATE="16 March 2023"
PREFIX=/user/local

recommended : check-build-dirs select-workspaces-sh select-quota-sh select-check-quota-sh man-allocations-py
	m4 -DVERSION=$(VERSIUON) -DDATE=$(DATE) man/man1/lumi-tools-recommended.1 >build/share/man/man1/lumi-tools.1

check-build-dirs :
	mkdir -p build/bin
	mkdir -p build/share/man/man1
	
select-workspaces-sh : check-build-dirs
	cp src/lumi-workspaces.sh build/bin/lumi-workspaces
	m4 -DVERSION=$(VERSIUON) -DDATE=$(DATE) man/man1/lumi-workspaces-sh.1 >build/share/man/man1/lumi-workspaces.1
	
select-quota-sh : check-build-dirs
	cp src/lumi-quota.sh build/bin/lumi-quota
	m4 -DVERSION=$(VERSIUON) -DDATE=$(DATE) man/man1/lumi-quota-sh.1 >build/share/man/man1/lumi-quota.1

select-check-quota-sh : check-build-dirs
	cp src/lumi-check-quota.sh build/bin/lumi-check-quota
	m4 -DVERSION=$(VERSIUON) -DDATE=$(DATE) man/man1/lumi-check-quota-sh.1 >build/share/man/man1/lumi-check-quota.1

man-allocations-py : check-build-dirs
	m4 -DVERSION=$(VERSIUON) -DDATE=$(DATE) man/man1/lumi-allocations-py.1 >build/share/man/man1/lumi-allocations.1

install :
	mkdir -p $(PREFIX)/bin
	mkdir -p $(PREFIX)/share/man/man1
	cp build/bin/* $(PREFIX)/bin
	cp build/share/man/man1/* $(PREFIX)/share/man/man1

clean :
	-/bin/rm -rf build
