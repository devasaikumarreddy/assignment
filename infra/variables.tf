
####connection######



variable "env" {
  description = "Environment Name"
  default = "dev"
  type        = string
}

variable "appName" {
  description = "Application Name"
  default = null
  type    = string
  
}

# variable "address_space" {
#   type        = list(string)
#   description = "address space of the virtual network" 
# }