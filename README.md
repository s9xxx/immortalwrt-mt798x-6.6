ImmortalWrt 项目说明
1  项目简介
ImmortalWrt 是 OpenWrt 的一个分支。相比上游，它为大陆用户移植了更多软件包、支持更多设备，并提供默认优化的配置文件以及本地化修改。
与上游相比，本项目允许使用无法提交上游的修改或取巧做法，以提供更好的功能、更好的性能以及更完善的支持。
默认登录地址为 http://192.168.6.1 或 http://immortalwrt.lan，用户名为 root，密码为空（无密码）。
2  下载
本项目已为多种架构提供编译好的固件镜像，并附带可供 WiFi 家用路由器使用的软件包选择。若要从厂商原厂固件快速迁移到 ImmortalWrt，可使用固件选择器（Firmware Selector）。
● ImmortalWrt 固件选择器
如果您的设备受支持，请点击 Info 链接查看安装说明，或查阅下文列出的支持资源。
3  开发
要自行编译固件，需要一台 GNU/Linux、BSD 或 macOS 系统（要求文件系统区分大小写）。不支持 Cygwin，因为其文件系统不区分大小写。
3.1  环境要求
推荐使用 Debian 11 构成本项目。需要基于 AMD64 架构的 CPU，至少 4 GB 内存以及 25 GB 可用磁盘空间，并确保可以访问互联网。
编译 ImmortalWrt 需要下列工具，不同发行版中软件包名称可能不同。以下为 Debian/Ubuntu 用户的示例。
方式一：通过 APT 安装依赖
sudo apt update -y
sudo apt full-upgrade -y
sudo apt install -y ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
  bzip2 ccache clang cmake cpio curl device-tree-compiler ecj fastjar flex gawk gettext gcc-multilib \
  g++-multilib git gnutls-dev gperf haveged help2man intltool lib32gcc-s1 libc6-dev-i386 libelf-dev \
  libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses-dev libpython3-dev \
  libreadline-dev libssl-dev libtool libyaml-dev libz-dev lld llvm lrzsz mkisofs msmtp nano \
  ninja-build p7zip p7zip-full patch pkgconf python3 python3-pip python3-ply python3-docutils \
  python3-pyelftools qemu-utils re2c rsync scons squashfs-tools subversion swig texinfo uglifyjs \
  upx-ucl unzip vim wget xmlto xxd zlib1g-dev zstd
方式二：使用官方构建环境初始化脚本
sudo bash -c 'bash <(curl -s https://build-scripts.immortalwrt.org/init_build_environment.sh)'
注意事项：
● 所有操作均以非特权用户身份执行，不要使用 root，也不要使用 sudo。
● 使用其他架构的 CPU 通常也可以编译 ImmortalWrt，但需要更多调整，且不提供任何保证。
● PATH 环境变量或磁盘上的工作目录中不得包含空格或非 ASCII 字符。
● 如果使用 Windows Subsystem for Linux（WSL），需要从 PATH 中移除 Windows 目录，详见对应文档。
● 不建议使用 macOS 作为宿主构建系统，不提供任何保证。可参考下方链接获取提示。
● macOS 构建环境说明
● 更多细节请参见构建系统安装文档。
3.2  快速开始
1. 克隆源代码：
git clone -b openwrt-24.10-6.6 --single-branch --filter=blob:none \
  https://github.com/padavanonly/immortalwrt-mt798x-24.10 immortalwrt-mt798x-24.10
2. 进入源码目录：
cd immortalwrt-mt798x-24.10
3. 获取最新的软件包定义（feeds.conf / feeds.conf.default 中定义的全部 feeds）：
./scripts/feeds update -a
4. 安装软链接，把已获取的软件包安装到 package/feeds/ 目录：
./scripts/feeds install -a
5. 从 defconfig 目录中复制适用于您设备的配置文件到项目根目录，并重命名为 .config：
# MT7981
cp -f defconfig/mt7981-ax3000.config .config

# MT7986
cp -f defconfig/mt7986-ax6000.config .config
6. 运行 make 开始编译。该过程会下载全部源码、构建交叉编译工具链，然后针对目标系统交叉编译 GNU/Linux 内核与所有已选应用：
make
4  相关仓库
主仓库通过多个子仓库来管理不同类别的软件包。所有软件包均通过名为 opkg 的 OpenWrt 包管理器安装。如果您打算开发 Web 界面或向 ImmortalWrt 移植软件包，请在下方找到合适的仓库。
● LuCI Web 界面：通过浏览器控制设备的现代化、模块化界面。
● ImmortalWrt Packages：移植软件包的社区仓库。
● OpenWrt Routing：专注于（网状）路由的软件包。
● OpenWrt Video：专注于显示服务器与客户端的软件包（Xorg 与 Wayland）。
5  支持信息
受支持的设备列表请参见 OpenWrt 硬件数据库。
5.1  文档
● 快速入门指南
● 用户指南
● 开发者指南
● 技术参考
5.2  支持社区
● Telegram 交流群：@ctcgfw_openwrt_discuss
● Matrix 交流群：#immortalwrt
6  许可证
ImmortalWrt 采用 GPL-2.0-only 许可证授权。
7  致谢
感谢下列服务商与组织对本项目的支持：
● Dler Cloud
● JetBrains（提供开源许可证支持）
● SourceForge（提供镜像与分发支持）
