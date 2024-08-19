ssh_public_key := env_var('SSH_PUBLIC_KEY')

supervisor:
  #!/usr/bin/python3

  import jinja2
  import yaml
  import os

  def include_sub_template(template_file, values, env):
    template = env.get_template(template_file)
    return template.render(values)

  if __name__ == "__main__":
    ssh_public_key = "{{ssh_public_key}}"
    template_file = "templates/cloud-config/supervisor.yml.j2"
    supervisor_values_file = "values.d/supervisor.yml"
    nodes_values_file = "values.d/nodes.yml"

    with open(supervisor_values_file) as f1, open(nodes_values_file) as f2:
      supervisor = yaml.safe_load(f1)
      nodes = yaml.safe_load(f2)
        
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(searchpath="."))
    env.globals['include_sub_template'] = lambda sub_template_file, sub_values: include_sub_template(sub_template_file, sub_values, env)
    env.globals['getenv'] = lambda key: os.getenv(key)

    template = env.get_template(template_file)
    print(template.render(supervisor,nodes=nodes))

node HOSTNAME:
  #!/usr/bin/python3

  import jinja2
  import yaml
  import os
  import sys
  
  def get_node_by_hostname(hostname, nodes):
    for node in nodes:
        if node['hostname'] == hostname:
            return node
    return None

  if __name__ == "__main__":
    ssh_public_key = "{{ssh_public_key}}"
    hostname = "{{HOSTNAME}}"
    template_file = "templates/cloud-config/node.yml.j2"
    values_file = "values.d/nodes.yml"

    with open(values_file) as f:
      nodes = yaml.safe_load(f)
      node = get_node_by_hostname(hostname, nodes)

      if node is None:
        print(f"Error: Hostname '{hostname}' not found in nodes list.")
        sys.exit(1)

    env = jinja2.Environment(loader=jinja2.FileSystemLoader(searchpath="."))
    env.globals['getenv'] = lambda key: os.getenv(key)

    template = env.get_template(template_file)
    print(template.render(node))

check-supervisor:
  just cloud-config supervisor | cloud-init schema --config-file /dev/stdin

check-node HOSTNAME:
  just supervisor node {{HOSTNAME}} | cloud-init schema --config-file /dev/stdin