import sys
import json
from jinja2 import Template

with open(sys.argv[1]) as f:
    template = Template(f.read(), trim_blocks=True, lstrip_blocks=True)
data = {} if len(sys.argv) == 3 else json.loads(sys.argv[2])
data['tab'] = '\t'
data['newline'] = '\n'
out = template.render(**data)
with open(sys.argv[-1],'w') as f:
   f.write(out)
