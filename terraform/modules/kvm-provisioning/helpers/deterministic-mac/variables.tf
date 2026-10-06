
variable "seeds" {
  description = "Seed strings keyed by caller-chosen keys. Every distinct seed yields a distinct MAC address with a probability set by the first 24 bits of its MD5 digest."
  type        = map(string)
}
