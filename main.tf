data "template_file" "_log_configuration" {
  count = var.log_driver == "__NOT_DEFINED__" ? 0 : 1

  template = <<JSON
  $${ jsonencode("logConfiguration") } : {
    $${ jsonencode("logDriver") } : $${ jsonencode(log_driver) },
    $${ jsonencode("options") } : {
      $${ log_driver_options }
    }
  }
JSON

  vars = {
    log_driver = var.log_driver
    log_driver_options = join(",\n", data.template_file._log_driver_options.*.rendered)
  }
}

data "template_file" "_log_driver_options" {
  count = length(keys(var.log_driver_options))
  template = <<JSON
$${ jsonencode(key) }: $${ jsonencode(value) }
JSON

  vars = {
    key   = keys(var.log_driver_options)[count.index]
    value = var.log_driver_options[keys(var.log_driver_options)[count.index]]
  }
}

data "template_file" "_port_mappings" {
  template = <<JSON
$${val}
JSON

  vars = {
    val = join(",\n", data.template_file._port_mapping.*.rendered)
  }
}

data "template_file" "_port_mapping" {
  count = var.port_mappings[0]["containerPort"] == "__NOT_DEFINED__" ? 0 : length(var.port_mappings)

  template = <<JSON
{
$${join(",\n",
  compact([
    host_port == "" || host_port == "__NOT_DEFINED__" ? "" : "$${ jsonencode("hostPort") }: $${host_port}",
    container_port == "" || container_port == "__NOT_DEFINED__" ? "" : "$${ jsonencode("containerPort") }: $${container_port}",
    protocol == "" || protocol == "__NOT_DEFINED__" ? "" : "$${ jsonencode("protocol") }: $${ jsonencode(protocol) }"
  ])
)}
}
JSON

  vars = {
    host_port      = lookup(var.port_mappings[count.index], "hostPort", "")
    container_port = var.port_mappings[count.index]["containerPort"]
    protocol       = lookup(var.port_mappings[count.index], "protocol", "")
  }
}

data "template_file" "_environment_vars" {
  count = lookup(var.environment_vars, "__NOT_DEFINED__", "__ITS_DEFINED__") == "__NOT_DEFINED__" ? 0 : 1
  depends_on = [data.template_file._environment_var]

  template = <<JSON
$${ jsonencode("environment") } : [
$${val}
]
JSON

  vars = {
    val = join(",\n", data.template_file._environment_var.*.rendered)
  }
}

data "template_file" "_environment_var" {
  count = length(keys(var.environment_vars))

  template = <<JSON
{
$${join(",\n",
  compact([
    var_name == "__NOT_DEFINED__" ? "" : "$${ jsonencode("name") }: $${ jsonencode(var_name)}",
    var_value == "__NOT_DEFINED__" ? "" : "$${ jsonencode("value") }: $${ jsonencode(var_value)}"
  ])
)}
}
JSON

  vars = {
    var_name  = sort(keys(var.environment_vars))[count.index]
    var_value = lookup(var.environment_vars, sort(keys(var.environment_vars))[count.index], "")
  }
}

data "template_file" "_ulimit" {
  template = jsonencode([
    {
      name      = "nofile",
      softLimit = 30000,
      hardLimit = 50000
    }
  ])
}

data "template_file" "_extra_container" {
  count = length(var.extra_containers)

  template = <<JSON
{
  $${jsonencode("name")}: $${jsonencode(name)},
  $${jsonencode("image")}: $${jsonencode(image)},
  $${jsonencode("cpu")}: $${cpu},
  $${jsonencode("memory")}: $${memory},
  $${jsonencode("essential")}: false,
  $${jsonencode("mountPoints")}: $${mount_points},
  $${jsonencode("environment")}: $${environment},
  $${jsonencode("secrets")}: $${secrets},
  $${jsonencode("logConfiguration")}: {
    $${jsonencode("logDriver")}: $${jsonencode(log_driver)},
    $${jsonencode("options")}: $${log_options}
  }
}
JSON

  vars = {
    name         = var.extra_containers[count.index].name
    image        = var.extra_containers[count.index].image
    cpu          = var.extra_containers[count.index].cpu
    memory       = var.extra_containers[count.index].memory
    mount_points = jsonencode(var.extra_containers[count.index].mountPoints)
    environment  = jsonencode(var.extra_containers[count.index].environment)
    secrets      = jsonencode(var.extra_containers[count.index].secrets)
    log_driver   = var.extra_containers[count.index].logConfiguration.logDriver
    log_options  = jsonencode(var.extra_containers[count.index].logConfiguration.options)
  }
}

data "template_file" "_volumes" {
  count = length(var.volumes) > 0 ? 1 : 0

  template = <<JSON
$${jsonencode("volumes")}: $${volumes}
JSON

  vars = {
    volumes = jsonencode(var.volumes)
  }
}

locals {
  extra_containers = length(data.template_file._extra_container) > 0 ? ",\n  ${join(",\n  ", [for c in data.template_file._extra_container : c.rendered])}" : ""

  volumes_block = length(data.template_file._volumes) > 0 ? format(",\n%s", data.template_file._volumes[0].rendered) : ""
}



data "template_file" "_final" {
  depends_on = [
    data.template_file._environment_vars,
    data.template_file._port_mappings,
    data.template_file._log_configuration,
    data.template_file._extra_container,
    data.template_file._volumes
  ]

  template = <<JSON
[
  {
    $${val}
  }$${extra_containers}
]
$${volumes_block}
JSON

  vars = {
    val = join(
      ",\n    ",
      compact([
        "${jsonencode("cpu")}: ${var.cpu}",
        "${jsonencode("memory")}: ${var.memory}",
        "${jsonencode("entryPoint")}: ${jsonencode(compact(split(" ", var.entrypoint)))}",
        "${jsonencode("command")}: ${jsonencode(compact(split(" ", var.service_command)))}",
        "${jsonencode("links")}: ${jsonencode(var.links)}",
        "${jsonencode("portMappings")}: [${data.template_file._port_mappings.rendered}]",
        join("", data.template_file._environment_vars[*].rendered),
        join("", data.template_file._log_configuration[*].rendered),
        "${jsonencode("name")}: ${jsonencode(var.service_name)}",
        "${jsonencode("image")}: ${jsonencode(var.service_image)}",
        "${jsonencode("essential")}: ${var.essential ? true : false}",
        "${jsonencode("ulimits")}: ${data.template_file._ulimit.rendered}"
      ])
    )

    extra_containers = local.extra_containers
    volumes_block    = local.volumes_block
  }
}
