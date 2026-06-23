packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "iso_url" {
  type = string
}

variable "iso_checksum" {
  type = string
}

variable "ssh_username" {
  type    = string
  default = "vyos"
}

variable "ssh_password" {
  type      = string
  default   = "vyos"
  sensitive = true
}

variable "vm_name" {
  type    = string
  default = "vyos15-daed-gateway"
}

variable "disk_size" {
  type    = string
  default = "8192"
}

variable "daed_version" {
  type    = string
  default = "latest"
}

source "qemu" "vyos15" {
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  vm_name          = "${var.vm_name}.qcow2"
  output_directory = "output-${var.vm_name}"
  format           = "qcow2"
  disk_size        = var.disk_size
  disk_interface   = "virtio"

  qemu_binary = "qemu-system-x86_64"
  accelerator = "tcg"
  net_device  = "virtio-net"
  headless    = true
  memory      = 4096
  cpus        = 2

  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "45m"

  boot_wait = "60s"

  boot_command = [
    "<enter><wait90s>",
    "${var.ssh_username}<enter><wait>",
    "${var.ssh_password}<enter><wait>",
    "configure<enter><wait>",
    "set interfaces ethernet eth0 address dhcp<enter>",
    "set service ssh port 22<enter>",
    "set system name-server 1.1.1.1<enter>",
    "commit<enter><wait>",
    "save<enter><wait>",
    "exit<enter><wait>",
    "install image<enter><wait5s>",
    "Yes<enter><wait>",
    "<enter><wait>",
    "${var.ssh_password}<enter><wait>",
    "${var.ssh_password}<enter><wait>",
    "K<enter><wait>",
    "<enter><wait>",
    "Y<enter><wait>",
    "Y<enter><wait>",
    "1<enter><wait>",
    "reboot<enter><wait>",
    "y<enter>"
  ]

  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
}

build {
  name    = "vyos15-daed-gateway"
  sources = ["source.qemu.vyos15"]

  provisioner "file" {
    source      = "packer/custom-services/"
    destination = "/tmp/custom-services/"
  }

  provisioner "file" {
    source      = "packer/scripts/setup-gateway.sh"
    destination = "/tmp/setup-gateway.sh"
  }

  provisioner "shell" {
    execute_command = "echo '${var.ssh_password}' | sudo -S bash '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/setup-gateway.sh",
      "DAED_VERSION='${var.daed_version}' /tmp/setup-gateway.sh"
    ]
  }

  post-processor "shell-local" {
    inline = [
      <<-EOT
      set -e
      mkdir -p artifacts ova-work
      rm -f ova-work/${var.vm_name}.vmdk ova-work/${var.vm_name}.ovf artifacts/${var.vm_name}.ova

      qemu-img convert -p -O vmdk -o subformat=streamOptimized \
        output-${var.vm_name}/${var.vm_name}.qcow2 \
        ova-work/${var.vm_name}.vmdk

      DISK_BYTES="$(stat -c%s ova-work/${var.vm_name}.vmdk)"

      cat > ova-work/${var.vm_name}.ovf <<EOF
      <?xml version="1.0" encoding="UTF-8"?>
      <Envelope xmlns="http://schemas.dmtf.org/ovf/envelope/1"
                xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
                xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
                xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData">
        <References>
          <File ovf:id="file1" ovf:href="${var.vm_name}.vmdk" ovf:size="$DISK_BYTES"/>
        </References>
        <DiskSection>
          <Info>Virtual disk information</Info>
          <Disk ovf:diskId="disk1"
                ovf:fileRef="file1"
                ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"
                ovf:capacity="${var.disk_size}"
                ovf:capacityAllocationUnits="byte * 2^20"/>
        </DiskSection>
        <NetworkSection>
          <Info>Logical networks</Info>
          <Network ovf:name="VM Network">
            <Description>Primary network</Description>
          </Network>
        </NetworkSection>
        <VirtualSystem ovf:id="${var.vm_name}">
          <Info>VyOS 1.5 daed transparent gateway</Info>
          <Name>${var.vm_name}</Name>
          <OperatingSystemSection ovf:id="96">
            <Info>Debian GNU/Linux 12 compatible</Info>
            <Description>Debian_64</Description>
          </OperatingSystemSection>
          <VirtualHardwareSection>
            <Info>Virtual hardware requirements</Info>
            <System>
              <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
              <vssd:InstanceID>0</vssd:InstanceID>
              <vssd:VirtualSystemIdentifier>${var.vm_name}</vssd:VirtualSystemIdentifier>
              <vssd:VirtualSystemType>vmx-13</vssd:VirtualSystemType>
            </System>
            <Item>
              <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
              <rasd:Description>Number of virtual CPUs</rasd:Description>
              <rasd:ElementName>2 virtual CPU(s)</rasd:ElementName>
              <rasd:InstanceID>1</rasd:InstanceID>
              <rasd:ResourceType>3</rasd:ResourceType>
              <rasd:VirtualQuantity>2</rasd:VirtualQuantity>
            </Item>
            <Item>
              <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
              <rasd:Description>Memory Size</rasd:Description>
              <rasd:ElementName>4096MB of memory</rasd:ElementName>
              <rasd:InstanceID>2</rasd:InstanceID>
              <rasd:ResourceType>4</rasd:ResourceType>
              <rasd:VirtualQuantity>4096</rasd:VirtualQuantity>
            </Item>
            <Item>
              <rasd:AddressOnParent>0</rasd:AddressOnParent>
              <rasd:ElementName>disk1</rasd:ElementName>
              <rasd:HostResource>ovf:/disk/disk1</rasd:HostResource>
              <rasd:InstanceID>3</rasd:InstanceID>
              <rasd:ResourceType>17</rasd:ResourceType>
            </Item>
            <Item>
              <rasd:AddressOnParent>0</rasd:AddressOnParent>
              <rasd:Connection>VM Network</rasd:Connection>
              <rasd:Description>VIRTIO ethernet adapter</rasd:Description>
              <rasd:ElementName>Network adapter 1</rasd:ElementName>
              <rasd:InstanceID>4</rasd:InstanceID>
              <rasd:ResourceType>10</rasd:ResourceType>
            </Item>
          </VirtualHardwareSection>
        </VirtualSystem>
      </Envelope>
      EOF

      tar -C ova-work -cf artifacts/${var.vm_name}.ova ${var.vm_name}.ovf ${var.vm_name}.vmdk
      EOT
    ]
  }
}
