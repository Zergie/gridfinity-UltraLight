PYTHON := python3
NPROCS := 10

.PHONY: all setup requirements configurations docker openscad site gh-deploy serve clean-unused clean
all: makefile.configurations openscad
setup: .venv/bin/activate requirements
requirements: ./.venv/bin/mkdocs

.venv/bin/activate:
	$(PYTHON) -m venv .venv

.venv/bin/mkdocs: requirements.txt .venv/bin/activate
	.venv/bin/pip install -r $<

makefile.configurations: templates/makefile.configurations.j2
	$(PYTHON) scripts/render_with_jinja.py $< '{"PYTHON":"$(PYTHON)"}' $@

configurations: makefile.configurations
	@make -j $(NPROCS) -f $< PYTHON=$(PYTHON)

docker:
	@for image in openscad/openscad:latest dpokidov/imagemagick; do \
	  if ! docker image inspect $$image > /dev/null 2>&1; then \
	    echo "Pulling $$image..."; \
	    docker pull $$image; \
	  else \
	    echo "$$image already available locally."; \
	  fi; \
	done

openscad: makefile.openscad docker configurations
	@make -j $(NPROCS) -f $< stl PYTHON=$(PYTHON)
	@make -j $(NPROCS) -f $< png PYTHON=$(PYTHON)
	
site:
	.venv/bin/python -m mkdocs build

gh-deploy:
	.venv/bin/python -m mkdocs gh-deploy

serve:
	.venv/bin/python -m mkdocs serve

clean-unused:
	@make -f makefile.configurations clean-unused
	@make -f makefile.openscad clean-unused

clean:
	@make -f makefile.configurations clean
	@make -f makefile.openscad clean
	rm -f makefile.configurations
