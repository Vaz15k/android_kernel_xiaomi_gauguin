#!/bin/bash
DIR=$(readlink -f .)
PARENT_DIR=$(readlink -f ${DIR}/..)

ARGS="$*"

AK3_DIR="$HOME/AnyKernel3"
OUT_DIR="$DIR/out"
OUT_KERNEL="$OUT_DIR/arch/arm64/boot/Image"
OUT_DTBO="$OUT_DIR/arch/arm64/boot/dtbo.img"

toolchain() {
    if [ "$GITHUB_ACTIONS" = "true" ]; then
        TC_DIR="$HOME/Prebuilts"
    else
        TC_DIR="$HOME/Projetos/Prebuilts"
    fi
	BT_DIR="$TC_DIR/build-tools"
	CL_DIR="$TC_DIR/gl-clang/clang-r547379"
	GAS_DIR="$TC_DIR/gas"

	export PATH=$CL_DIR/bin:$PATH
	export PATH=$BT_DIR/path/linux-x86:$PATH
	export PATH=$GAS_DIR/linux-x86:$PATH
}

clear_build() {
    if [ -d "$OUT_DIR" ]; then
        rm -rf "$OUT_DIR"
    fi
}

ksu() {
    if [[ "$ARGS" == *"--ksu"* ]]; then
        echo "KernelSU without SUSFS"
        if [ ! -d "KernelSU" ]; then
            echo "KernelSU not found !"
            echo "Fetching ...."
            curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -
        fi
        ZIP_NAME="gauguin_ksu_$(date +'%Y-%m-%d')"
        scripts/config --file $DIR/arch/arm64/configs/$DEFCONFIG \
            -e CONFIG_KSU \
            --set-str CONFIG_LOCALVERSION "-ksu"
        echo "Building Kernel with KernelSU"
    elif [[ "$ARGS" == *"--next"* ]]; then
        echo "KernelSU-Next without SUSFS"
        if [ ! -d "KernelSU" ]; then
            echo "KernelSU Next not found !"
            echo "Fetching ...."
            curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -
        fi
        ZIP_NAME="gauguin_ksu_next_$(date +'%Y-%m-%d')"
        scripts/config --file $DIR/arch/arm64/configs/$DEFCONFIG \
            -e CONFIG_KSU \
            --set-str CONFIG_LOCALVERSION "-ksu_next"
        echo "Building Kernel with KernelSU-Next"
    else
        echo "KSU disabled"
        ZIP_NAME="gauguin_$(date +'%Y-%m-%d')"
        if [ -d "KernelSU" ]; then
            rm -rf drivers/kernelsu KernelSU
            git reset HEAD --hard
        fi
    fi
}

anykernel3() {
	if [ -d $AK3_DIR ]; then
		cd $AK3_DIR
		git reset HEAD --hard
		git clean -xdf
		cd $DIR
	else
        git clone --branch gauguin https://github.com/Vaz15k/AnyKernel3.git $AK3_DIR
        cd $DIR
	fi
}

makezipfile() {
    cp $OUT_KERNEL $AK3_DIR
    cp $OUT_DTBO $AK3_DIR
    cd $AK3_DIR
    zip -r9 $ZIP_NAME . -x '*.git*' '*patch*' '*ramdisk*' 'README.md' '*modules*'
}

export KBUILD_BUILD_USER="Vaz15K"
export KBUILD_BUILD_HOST="GithubActions"

DEFCONFIG=gauguin_defconfig
JOBS=$(nproc --all)

MAKE_PARAMS="-j$JOBS O=$OUT_DIR ARCH=arm64 CC=clang LD=ld.lld HOSTCC=clang HOSTCXX=clang++ READELF=llvm-readelf HOSTAR=llvm-ar AR=llvm-ar AS=llvm-as NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi"

if [[ "$ARGS" == *"--clean"* ]]; then
    if [ -d "$OUT_DIR" ]; then
    	rm -rf "$OUT_DIR"
    fi
    echo "INFO: Limpeza concluída!"
fi

toolchain
ksu

scripts/config --file $DIR/arch/arm64/configs/$DEFCONFIG \
	-e CONFIG_THINLTO \
    -d CONFIG_LOCALVERSION_AUTO

make $MAKE_PARAMS $DEFCONFIG
make $MAKE_PARAMS

if [[ ! -f "$OUT_KERNEL" ]]; then
    echo "Build failed"
else
    anykernel3
    makezipfile
fi
