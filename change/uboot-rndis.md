# 效果
目前还没有固化 `sdboot`, `ipaddr`, `serverip` 这些环境变量, 这里先手动设置来感受.

查看 USB 设备:
```sh
$ ls /dev | grep -i usb
ttyUSB0
usb
vboxusb
```

之后观察串口:
```sh
$ sudo minicom -D /dev/ttyUSB0 -b 115200
```

在另一个终端观察 `dmesg` 输出:
```sh
$ sudo dmesg -w
```

给 SG2002 上电, 进入 U-Boot 后:
```
setenv ipaddr 192.168.42.1
setenv serverip 192.168.42.100
ping 192.168.42.100
```

之后在宿主机终端里查看新的网络接口:
```sh
$ ip a
```

![](./.github/img/interface-show-up.png)

找到后快速设置:
```sh
$ sudo ip addr add 192.168.42.100/24 dev enp0s20f0u1c2
$ sudo ip link set enp0s20f0u1c2 up
```
![](./.github/img/setup-interface.png)

之后 U-Boot 中的 `ping 192.168.42.100` 会返回则表示连接成功:

![](./.github/img/u-boot-ping-alive.png)

在你的电脑上安装 `tftp` 服务并启动, 我这里是 Archlinux:
```sh
sudo pacman -S tftp-hpa
sudo systemctl start tftpd
sudo mkdir -p /srv/tftp
sudo bash -c "echo 'Hello U-Boot' > /srv/tftp/hello.txt"
```

在 U-Boot 内拉取文件并查看:
```
tftpboot 0x84000000 hello.txt
md 0x84000000
```

![](./.github/img/u-boot-tftp.png)

拉取 `boot.sd` 示例:
```
tftpboot 0x81800000 boot.sd
bootm 0x81800000#config-sg2002_licheervnano_sd
```
