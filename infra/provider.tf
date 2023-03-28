terraform {
  required_version = ">= 0.14.8"
}


provider "azurerm" {
  features {}
}


terraform {
   backend "azurerm" {
   }
 }

