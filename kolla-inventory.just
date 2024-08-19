multinode:
  #!/usr/bin/python3
  
  import jinja2
  import yaml

  template_file = "templates/multinode.toml.j2"
  supervisor_values_file = "values.d/supervisor.yml"
  nodes_values_file = "values.d/nodes.yml"

  with open(supervisor_values_file) as f1, open(nodes_values_file) as f2:
    supervisor = yaml.safe_load(f1)
    nodes = yaml.safe_load(f2)
    
  env = jinja2.Environment(loader=jinja2.FileSystemLoader(searchpath="."))

  template = env.get_template(template_file)
  print(template.render(supervisor,nodes=nodes))