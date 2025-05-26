import os
import json
from collections import defaultdict

def define_env(env):
    def get_configurations():
        config_path = os.path.join(os.getcwd(), 'docs', 'configurations.json')
        with open(config_path, 'r') as file:
            return json.load(file)
    
    def format_table(header, rows):
        def generator(header, rows):
            yield f"| {' | '.join(header)} |"
            yield f"|{'|'.join(['-' * (len(x)+2) for x in header]) }|"
            for row in rows:
                yield f"| {' | '.join([str(x) for x in row])} |"
        return "\n".join(generator(header, rows))

    @env.macro
    def stl_table(filter:str, value:any):
        # info = [
        #     "variables: " + repr(env.variables),
        #     "conf: " + repr(env.conf),
        #     "config: " + repr(env.config),
        #     "page: " + repr(env.page),
        #     ">>" + repr(env.conf['site_url']),
        # ]
        # return "<br><br>".join(info)
        configurations = get_configurations()
        
        header = ["Size", "Image"] + [f"{x}x" for x in sorted(list(set(x['Dividers_X']+1 for x in configurations)))]
        def get_rows():
            groups = defaultdict(list)
            for item in configurations:
                if item[filter] == value:
                    groups[item['Grids_X']] .append(item)

            for key in sorted(groups.keys()):
                items = groups[key]
                row = [
                    key,
                    f"![Image](./images/{items[0]['filename']}.png)",
                    "<br>".join(
                        [f"{((item['Grids_X'] *42 -2) - item['Dividers_X']) / (item['Dividers_X'] + 1) :.1f} mm",] 
                        + 
                        [f"[{item['filename']}](orcaslicer://open?file={env.conf['site_url']}/STLs/{item['filename']}.stl)" for item in items if item['Dividers_X'] == 0]
                    ),
                ]
                cols_freezed = len(row)
                row += ["" for _ in header[cols_freezed:]]
                
                for item in items:
                    index = 2 + item['Dividers_X']
                    if index >= cols_freezed:
                        row[index] += f"{((item['Grids_X'] *42 -2) - item['Dividers_X']) / (item['Dividers_X'] + 1) :.1f} mm"                    
                        row[index] += "<br>"
                        row[index] += f"[![Image](./images/{item['filename']}.png)](orcaslicer://open?file={env.conf['site_url']}/STLs/{item['filename']}.stl)"

                yield row
        
        return format_table(header, get_rows())
    
    if __name__ == '__main__':
        print(stl_table('Grids_Z', 6))

if __name__ == '__main__':
    env = type('env', (object,), {
        'macro': lambda self, v, name='': v,
        'conf': {
            'site_url': 'http://127.0.0.1:8000/gridfinity-UltraLight/',
        }
        })()  # Mock environment object with 'macro' attribute
    define_env(env)