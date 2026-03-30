COVDIR := coverage
LCOV   := $(COVDIR)/lcov.info
PKGCFG := .dart_tool/package_config.json

.PHONY: test coverage coverage-html coverage-open coverage-clean

test:
	dart test

coverage:
	dart test --coverage=$(COVDIR)
	dart run coverage:format_coverage \
	  --packages=$(PKGCFG) \
	  --report-on=lib \
	  --in=$(COVDIR) \
	  --out=$(LCOV) \
	  --lcov

coverage-html: coverage
	genhtml $(LCOV) -o $(COVDIR)/html

coverage-open: coverage-html
	xdg-open $(COVDIR)/html/index.html || open $(COVDIR)/html/index.html

coverage-clean:
	rm -rf $(COVDIR)
