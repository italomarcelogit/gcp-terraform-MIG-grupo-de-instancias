# Criando um Grupo de Instancias para um serviço HTTP WebSite
# Principais Pontos do Projeto:
# - subir um grupo com um mínimo de 2 instâncias e máxima de 5 baseadas em um modelo
# - criar novas instâncias em caso de sobrecarga da instância ou crashes
# - criar uma rede e subnet dedicada a este grupo de instâncias
# - disponibilizar um balanceador de cargas para acessar a porta 80 (tcp/http) das instancias disponíveis
# Github: italomarcelogit


# ############ PASSO A PASSO ############
# 01: configurações de variáveis
# 02: configuração de redes
# 03: configuração do grupo de instâncias
# 04: configuração do load balancer


# ############
# 01: criar variaveis utilizadas na criação da infraestrutura
variable infra_regiao {
    description = "Região onde o Grupo de Instâncias (MIG) será criado"
    default = "europe-west1"
}
variable infra_zona {
    description = "Zona onde o Grupo de Instâncias (MIG) será criado"
    default = "europe-west1-b"
}
variable range_ips_internos {
    description = "Range de IPs internos - Faixa 192.168.10.0/24"
    default = "192.168.10.0/24"
}
variable prefixo_vms {
    description = "Prefixo dos nomes das VMs criadas pelo Grupo de Instancias"
    default = "vm-verde"
}

# ############
# 02: Criar e configurar a rede utilizada pela infraestrutura

# Criar a Rede VPC
resource "google_compute_network" "rede_vpc_webapp" {
  name                    = "rede-vpc-webapp"
  auto_create_subnetworks = false
}
# Criar a VPC - subnet
resource "google_compute_subnetwork" "subnet_vpc_webapp" {
  name          = "subnet-vpc-webapp"
  ip_cidr_range = "${var.range_ips_internos}" # range de ips da subnet
  region        = "${var.infra_regiao}" # regiao
  network       = google_compute_network.rede_vpc_webapp.id # recurso VPC
}
# Criar regras de firewall para permitir tráfego HTTP, SSH, e ICMP na VPC
resource "google_compute_firewall" "regras_vpc_permissoes" {
  name = "regra-webapp-permite-http-ssh-icmp"
  # Escolhendo a rede vpc
  network = google_compute_network.rede_vpc_webapp.self_link
  allow {
    protocol = "tcp"
    ports    = ["22", "80"]
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
}

# ############
# 03: Criar e configurar o grupo de instâncias que hospedarão o website

# Criar um modelo de vm a ser utilizado pelo grupo de instâncias
resource "google_compute_instance_template" "template_vm_verde" {  
  name_prefix = "template-${var.prefixo_vms}-"
  tags         = ["permite-health-check"]
  machine_type = "e2-micro"
  network_interface {
    network    = google_compute_network.rede_vpc_webapp.id
    subnetwork = google_compute_subnetwork.subnet_vpc_webapp.id
    access_config {
    #   network_tier = "PREMIUM"
    }
  }  
  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
  }
  metadata = {
    startup-script = "#! /bin/bash\napt update\napt -y install apache2\napt install net-tools\nIP=\"$(ip addr show ens4  | awk '$1 == \"inet\" { print $2 }' | cut -d/ -f1)\"\n\ncat <<EOF > /var/www/html/index.html\n<html>\n<style>\nbody {\n  background-color: rgb(152,251,152);\n}\n</style>\n<body>\n<h1>Modelo Verde</h1>\n<h3>$HOSTNAME</h3>\n<h4>$IP</h4>\n</body></html>\nEOF"
  }
  lifecycle {
    create_before_destroy = true
  }
}
# Criar um verificador automático (health check) do status do serviço
resource "google_compute_health_check" "health_check_tcp_80" {
  # é utilizado pelo grupo de instancias (VMs) e também pelo balanceador de cargas (Load Balancer)
  name     = "webapp-health-check"
  timeout_sec        = 1
  check_interval_sec = 1
  tcp_health_check {
    port = "80"
  }
}
# MIG
resource "google_compute_instance_group_manager" "grupo_vm_webapp" {
  name     = "grupo-vm-webapp"
  zone     = "${var.infra_zona}"
  named_port {
    name = "minha-porta"
    port = 80
  }
  version {
    instance_template = google_compute_instance_template.template_vm_verde.id
    name              = "primary"
  }
  base_instance_name = "${var.prefixo_vms}"
  target_size        = 2

  auto_healing_policies {
    health_check      = "${google_compute_health_check.health_check_tcp_80.id}"
    initial_delay_sec = 150
  }
}
# Criar um escalonador automático de instâncias
resource "google_compute_autoscaler" "grupo_vm_scaler" {
  name   = "grupo-vm-webapp-scaler"
  zone   = "europe-west1-b"
  target = google_compute_instance_group_manager.grupo_vm_webapp.id
  autoscaling_policy {
    max_replicas    = 5
    min_replicas    = 2
    cooldown_period = 60
    cpu_utilization {
      target = 0.8
    }
  }
}

# ############
# 04: Criar e configurar o load balancer da infraestrutura

# Criar Load Balancer
resource "google_compute_url_map" "loadb" {
  name            = "load-b"
  default_service = google_compute_backend_service.loadb_backend.id
}
# Atribuir um nome ao IP utilizado no Load Balancer
resource "google_compute_global_address" "loadb_ip" {
  name     = "load-b-ip"
}
# Configurando FrontEnd do Load Balancer
resource "google_compute_global_forwarding_rule" "loadb_frontend" {
  name                  = "load-b-regra-encaminhamento"
  ip_protocol           = "TCP" # protocolo de balanceamento
  load_balancing_scheme = "EXTERNAL" # esquema para balancemanto Internet
  port_range            = "80" # a porta do serviço que será balanceado
  target                = google_compute_target_http_proxy.loadb_proxy_http.id
  ip_address            = google_compute_global_address.loadb_ip.id
}
# Criar um proxy para o Load Balancer
resource "google_compute_target_http_proxy" "loadb_proxy_http" {
  name     = "load-b-http-proxy"
  url_map  = google_compute_url_map.loadb.id
}
# Criar BackEnd do Load Balancer
resource "google_compute_backend_service" "loadb_backend" {
  name                    = "load-b-backend"
  protocol                = "HTTP" 
  port_name               = "minha-porta"
  load_balancing_scheme   = "EXTERNAL"
  timeout_sec             = 10
  enable_cdn              = true
  custom_request_headers  = ["X-Client-Geo-Location: {client_region_subdivision}, {client_city}"]
  custom_response_headers = ["X-Cache-Hit: {cdn_cache_status}"]
  health_checks           = [google_compute_health_check.health_check_tcp_80.id]
  backend {
    group           = google_compute_instance_group_manager.grupo_vm_webapp.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
    max_utilization = 0.8
  }
}
