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

	CL_DIR="$TC_DIR/clang-r547379"
	export PATH=$CL_DIR/bin:$PATH
}

clear_build() {
    if [ -d "$OUT_DIR" ]; then
        rm -rf "$OUT_DIR"
    fi
}

ksu() {
    if [[ "$ARGS" == *"--ksu"* ]]; then
        if [ ! -d "$DIR/KernelSU" ]; then
            echo "INFO: Cloning KernelSU with SUSFS"
            curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s susfs-main
        fi
        ZIP_NAME="gauguin_ksu_$(date +'%Y-%m-%d')"
        
        scripts/config --file $DIR/arch/arm64/configs/$DEFCONFIG \
            -e CONFIG_KSU \
            -e CONFIG_KSU_SUSFS \
            --set-str CONFIG_LOCALVERSION "-ksu"
            
        echo "INFO: Building KSU kernel"

    elif [[ "$ARGS" == *"--next"* ]]; then
        if [ ! -d "$DIR/KernelSU-Next" ]; then
            echo "INFO: Cloning KernelSU Next"
            # curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next-susfs/kernel/setup.sh" | bash -s next-susfs
            curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -
        fi
        ZIP_NAME="gauguin_ksu_next_$(date +'%Y-%m-%d')"
        
        scripts/config --file $DIR/arch/arm64/configs/$DEFCONFIG \
            -e CONFIG_KSU \
            --set-str CONFIG_LOCALVERSION "-ksu_next"
        
        echo "INFO: Building KSU Next"

    elif [[ "$ARGS" == *"--sukisu"* ]]; then
        if [ ! -d "$DIR/KernelSU" ]; then
            echo "INFO: Cloning SukiSU"
            curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-main
        fi
        ZIP_NAME="gauguin_sukisu_$(date +'%Y-%m-%d')"
        
        scripts/config --file $DIR/arch/arm64/configs/$DEFCONFIG \
            -e CONFIG_KSU \
            -e CONFIG_KSU_SUSFS \
            -e CONFIG_KPM \
            -e KSU_MANUAL_HOOK \
            -e CONFIG_KALLSYMS \
            -e CONFIG_KALLSYMS_ALL \
            --set-str CONFIG_LOCALVERSION "-sukisu"
        
        echo "INFO: Building SukiSU kernel"

    else
        if [ -d "$DIR/KernelSU" ] || [ -d "$DIR/KernelSU-Next" ]; then
            rm -rf "$DIR/KernelSU" "$DIR/KernelSU-Next" "$DIR/drivers/kernelsu"
            git reset HEAD --hard
        fi
        ZIP_NAME="gauguin_$(date +'%Y-%m-%d')"
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

patch_kpm() {
    wget -q -O kpm_patch_linux $(curl -s https://api.github.com/repos/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/latest | grep "browser_download_url.*patch_linux" | cut -d : -f 2,3 | tr -d \")
    if [ -f "kpm_patch_linux" ]; then
        echo "INFO: Applying KPM patch"
        chmod +x kpm_patch_linux
        ./kpm_patch_linux Image
        rm Image kpm_patch_linux
        mv oImage Image
    else
        echo "ERROR: KPM patch not found"
    fi
}

makezipfile() {
    cp $OUT_KERNEL $AK3_DIR
    cp $OUT_DTBO $AK3_DIR
    cd $AK3_DIR
    if [[ "$ARGS" == *"--sukisu"* ]]; then
        patch_kpm
    fi
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
