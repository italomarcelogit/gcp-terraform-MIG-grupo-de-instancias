# Criando uma infraestrutura no Google Cloud, utilizando Terraform.
## O script de IAsC Terraform criará um Grupo de Instancias que hospedará uma aplicação de um website.

![ScreenShot](PNGs/img.png)

### Principais pontos deste script
- subir um grupo com um mínimo de 2 instâncias e máxima de 5 baseadas em um modelo
- criar novas instâncias em caso de sobrecarga da instância ou crashes
- criar uma rede e subnet dedicada a este grupo de instâncias
- disponibilizar um balanceador de cargas para acessar a porta 80 (tcp/http) das instancias disponíveis
