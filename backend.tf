terraform {
  backend "azurerm" {
    resource_group_name  = "RG-TerraformState"
    storage_account_name = "tfstatentfsnerdlab"
    container_name       = "tfstate"
    key                  = "ntfs-lab.terraform.tfstate"
  }
}