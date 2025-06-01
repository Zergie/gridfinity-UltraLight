import os
import json
from collections import defaultdict
from jsonpath_ng.ext import parse

def define_env(env):
    def get_configurations():
        result = []
        path = os.path.join(os.getcwd(), 'generated')
        for cfg in [x for x in os.listdir(path) if x.endswith(".json")]:
            with open(os.path.join(os.getcwd(), 'generated', cfg), 'r') as file:
                obj = json.load(file)['parameterSets']['make']
                obj['filename'] = os.path.splitext(cfg)[0]
                result.append(obj)
        return result
    
    def format_table(header, rows):
        def generator(header, rows):
            yield f"| {' | '.join(header)} |"
            yield f"|{'|'.join(['-' * (len(x)+2) for x in header]) }|"
            for row in rows:
                yield f"| {' | '.join([str(x) for x in row])} |"
        return "\n".join(generator(header, rows))

    @env.macro
    def stl_table(query:str):
        def format_head(item:dict):
            return str((item['Dividers_X']+1)*(item['Dividers_Y']+1))

        configurations = [match.value for match in parse(query).find(get_configurations())]
        header = ["Size", "Image"] + [x for x in sorted(list(set(format_head(x) for x in configurations)), key=int) if x != "0"]

        def get_rows():
            groups = defaultdict(list)
            for item in configurations:
                groups[item['Grids_X']].append(item)

            for key in sorted(groups.keys()):
                items = groups[key]
                row = [
                    key,
                    "<br>".join([
                        "",
                        f"![Image](./images/{items[0]['filename']}.png)",
                    ]),
                    "<br>".join(
                        [f"{items[0]['width']:.1f} mm ",] 
                        + 
                        [f"[{'With Scoop' if item['Scoops'] == 'true' else 'No Scoop'}](orcaslicer://open?file={env.conf['site_url']}/STLs/{item['filename']}.stl)" for item in items if item['Dividers_X'] == items[0]['Dividers_X']]
                    ),
                ]
                cols_freezed = len(row)
                row += ["" for _ in header[cols_freezed:]]
                
                for item in items:
                    index = header.index(format_head(item))
                    if index >= cols_freezed:
                        row[index] += f"{item['width']:.1f} mm"                    
                        row[index] += "<br>"
                        row[index] += f"[![Image](./images/{item['filename']}.png)](orcaslicer://open?file={env.conf['site_url']}/STLs/{item['filename']}.stl)"

                yield row
        
        return format_table(header, get_rows())
    
    if __name__ == '__main__':
        print(stl_table('$[?Grids_Y == 2 & Grids_Z == 6 & Dividers_Y == 1]'))

if __name__ == '__main__':
    env = type('env', (object,), {
        'macro': lambda self, v, name='': v,
        'conf': {
            'site_url': 'http://127.0.0.1:8000/gridfinity-UltraLight/',
        }
        })()  # Mock environment object with 'macro' attribute
    define_env(env)
