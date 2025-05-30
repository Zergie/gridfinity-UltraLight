PYTHON := python3
NPROCS:=$(shell grep -c ^processor /proc/cpuinfo)

.PHONY: all
all: makefile.configurations configurations stl
setup: .venv/bin/activate requirements

.venv/bin/activate:
	$(PYTHON) -m venv .venv

requirements: .venv/bin/activate | requirements.txt
	.venv/bin/pip install -r requirements.txt

makefile.configurations: templates/makefile.configurations.j2
	$(PYTHON) scripts/render_with_jinja.py $< '{"PYTHON":"$(PYTHON)"}' $@

configurations: makefile.configurations
	make -j $(NPROCS) -f $<

stl: makefile.openscad
	make -j $(NPROCS) -f $<



site:
	mkdocs build

serve:
	mkdocs serve


clean:
	make -f makefile.configurations clean
	make -f makefile.openscad clean
	rm -f makefile.configurations
