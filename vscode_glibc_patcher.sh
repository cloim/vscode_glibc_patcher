#!/bin/bash
set -e

echo "CentOS 7 전용 VS Code Server glibc 및 libstdc++ 패치 스크립트를 시작합니다."
echo "--------------------------------------------------------"

# 스크립트 전역에서 사용할 변수 사전 정의
GLIBC_VERSION="2.28"
INSTALL_PREFIX="/opt/glibc-$GLIBC_VERSION"
LIBSTDC_RPM_FILE="libstdc++-8.5.0-4.el8_5.x86_64.rpm"

# --- [공통 함수 정의] ---

error_exit() {
    echo ""
    echo "❌ [오류 발생] $1"
    echo "작업을 중단하고 시스템을 보호하기 위해 스크립트를 안전하게 종료합니다."
    echo "--------------------------------------------------------"
    exit 1
}

download_if_not_exists() {
    local url=$1
    local filename=$(basename "$url")
    if [ -f "$filename" ]; then
        echo " -> 이미 다운로드된 [$filename] 파일을 재사용합니다."
    else
        echo " -> [$filename] 파일을 다운로드합니다."
        wget "$url" || error_exit "[$filename] 다운로드에 실패했습니다. 네트워크 상태나 링크를 확인해 주십시오."
    fi
}

cleanup_temp_files() {
    echo " -> 임시 다운로드 파일 및 빌드 폴더를 정리합니다."
    cd /tmp || return
    rm -rf make-4.3.tar.gz make-4.3
    rm -rf glibc-$GLIBC_VERSION.tar.gz glibc-$GLIBC_VERSION
    rm -rf "$LIBSTDC_RPM_FILE" ./usr ./etc ./var
    echo " -> 찌꺼기 파일 청소가 완료되었습니다."
}

# --- [저장소 강력 패치 함수 (중복 실행 방지 적용)] ---
patch_all_repos() {
    local step=$1
    local marker="/etc/yum.repos.d/.repo_patched_step${step}"

    if [ -f "$marker" ]; then
        echo " -> 💡 ${step}차 저장소 패치가 이미 적용되어 있어 건너뜁니다."
        return 0
    fi

    echo " -> 시스템 내 저장소를 Vault 주소로 치환합니다. (${step}차)"
    sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/*.repo 2>/dev/null || true
    sed -i 's|^metalink=|#metalink=|g' /etc/yum.repos.d/*.repo 2>/dev/null || true
    sed -i 's|^#baseurl=|baseurl=|g' /etc/yum.repos.d/*.repo 2>/dev/null || true
    sed -i 's|^# baseurl=|baseurl=|g' /etc/yum.repos.d/*.repo 2>/dev/null || true
    sed -i 's|http://mirror.centos.org|http://vault.centos.org|g' /etc/yum.repos.d/*.repo 2>/dev/null || true
    sed -i 's|http://download.fedoraproject.org/pub/epel|https://archives.fedoraproject.org/pub/archive/epel|g' /etc/yum.repos.d/*.repo 2>/dev/null || true
    
    yum clean all
    touch "$marker"
}

# --- [사전 체크 단계] ---

echo "[1/5] 기존 패치 적용 여부를 확인합니다..."
if [ -f "/etc/profile.d/vscode-glibc.sh" ] && [ -f "$INSTALL_PREFIX/lib/ld-$GLIBC_VERSION.so" ]; then
    echo " -> 💡 이미 이 서버에는 VS Code Server 패치가 적용되어 있습니다."
    cleanup_temp_files
    echo "작업을 중단하고 스크립트를 정상 종료합니다."
    exit 0
fi
echo " -> 신규 패치 대상 서버임을 확인했습니다."

echo "[2/5] root 권한을 확인합니다..."
if [ "$(id -u)" -ne 0 ]; then
    error_exit "이 스크립트는 root 권한으로 실행해야 합니다. (sudo 또는 su 활용)"
fi
echo " -> root 권한 확인 완료."

echo "[3/5] 시스템 아키텍처를 확인합니다..."
if [ "$(uname -m)" != "x86_64" ]; then
    error_exit "이 스크립트는 x86_64 (AMD64) 아키텍처에서만 동작합니다. (현재: $(uname -m))"
fi
echo " -> x86_64 아키텍처 확인 완료."

echo "[4/5] 운영체제 버전을 확인합니다..."
if [ ! -f /etc/centos-release ] || ! grep -q "release 7" /etc/centos-release; then
    error_exit "이 패키지 설치 명령어와 경로 설정은 CentOS 7 환경 전용입니다."
fi
echo " -> CentOS 7 환경 확인 완료."

echo "[5/5] 외부 네트워크 연결을 확인합니다..."
if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    error_exit "인터넷에 연결할 수 없습니다. 네트워크 설정을 확인해 주십시오."
fi
echo " -> 네트워크 연결 확인 완료."

echo "--------------------------------------------------------"
echo "모든 사전 체크를 통과했습니다. 본격적인 설치를 진행합니다."
echo "--------------------------------------------------------"

# --- [본 작업 단계] ---

echo "[작업 1] 패키지 저장소 복구 및 컴파일러 업데이트를 진행합니다."

# 1-1. 기존에 남아있는 모든 저장소 찌꺼기 1차 패치
patch_all_repos 1

# 1-2. 필수 확장 저장소 패키지 설치
yum install -y --nogpgcheck --disablerepo=*wandisco*,*icinga* epel-release centos-release-scl || error_exit "기본 저장소(epel, scl) 패키지 설치에 실패했습니다."

# 1-3. 새로 설치된 확장 저장소에 대해 2차 패치
patch_all_repos 2

# 1-4. 컴파일러 및 빌드 도구 설치 (texinfo 추가)
yum install -y --nogpgcheck --disablerepo=*wandisco*,*icinga* devtoolset-8-gcc devtoolset-8-gcc-c++ devtoolset-8-binutils bison python3 wget bzip2 patchelf gawk cpio texinfo || error_exit "컴파일에 필요한 필수 패키지 설치에 실패했습니다."

source /opt/rh/devtoolset-8/enable || error_exit "GCC 8 (devtoolset-8) 활성화에 실패했습니다."

echo "[작업 2] Make 4.3 컴파일을 시작합니다."
cd /tmp
download_if_not_exists "https://ftp.gnu.org/gnu/make/make-4.3.tar.gz"
tar -xzf make-4.3.tar.gz || error_exit "make-4.3 압축 해제에 실패했습니다."
cd make-4.3
./configure || error_exit "Make 4.3 환경 설정(configure)에 실패했습니다."
make || error_exit "Make 4.3 컴파일(make)에 실패했습니다."
make install || error_exit "Make 4.3 설치(make install)에 실패했습니다."
hash -r

echo "[작업 3] glibc 2.28 다운로드 및 빌드를 시작합니다."
export PATH=/usr/local/bin:$PATH
ln -sf /usr/local/bin/make /usr/local/bin/gmake || error_exit "gmake 심볼릭 링크 생성에 실패했습니다."

cd /tmp
download_if_not_exists "http://ftp.gnu.org/gnu/libc/glibc-$GLIBC_VERSION.tar.gz"
tar -xzf glibc-$GLIBC_VERSION.tar.gz || error_exit "glibc 2.28 압축 해제에 실패했습니다."
mkdir -p glibc-$GLIBC_VERSION/build
cd glibc-$GLIBC_VERSION/build

# glibc 보안 정책에 걸리지 않도록 환경 변수 초기화
unset LD_LIBRARY_PATH

MAKE=/usr/local/bin/make ../configure --prefix=$INSTALL_PREFIX --disable-werror || error_exit "glibc 2.28 환경 설정(configure)에 실패했습니다."
/usr/local/bin/make -j"$(nproc)" || error_exit "glibc 2.28 컴파일(make)에 실패했습니다."
/usr/local/bin/make install || error_exit "glibc 2.28 설치(make install)에 실패했습니다."

echo "[작업 4] VS Code Server 환경변수를 등록합니다."
LINKER="$INSTALL_PREFIX/lib/ld-$GLIBC_VERSION.so"
LIBPATH="$INSTALL_PREFIX/lib"
PATCHELF="$(which patchelf)"

cat > /etc/profile.d/vscode-glibc.sh << EOF
export VSCODE_SERVER_CUSTOM_GLIBC_LINKER=$LINKER
export VSCODE_SERVER_CUSTOM_GLIBC_PATH=$LIBPATH:/usr/lib64:/lib64
export VSCODE_SERVER_PATCHELF_PATH=$PATCHELF
EOF
chmod +x /etc/profile.d/vscode-glibc.sh || error_exit "환경변수 스크립트 권한 부여에 실패했습니다."

echo "VSCODE_SERVER_CUSTOM_GLIBC_LINKER=$LINKER" >> /etc/environment
echo "VSCODE_SERVER_CUSTOM_GLIBC_PATH=$LIBPATH:/usr/lib64:/lib64" >> /etc/environment
echo "VSCODE_SERVER_PATCHELF_PATH=$PATCHELF" >> /etc/environment

echo "[작업 5] Node.js 실행을 위한 libstdc++ 호환성 패치를 진행합니다."
cd /tmp
LIBSTDC_RPM_URL="https://vault.centos.org/8.5.2111/BaseOS/x86_64/os/Packages/$LIBSTDC_RPM_FILE"

download_if_not_exists "$LIBSTDC_RPM_URL"

rpm2cpio "$LIBSTDC_RPM_FILE" | cpio -idmv || error_exit "libstdc++ RPM 패키지 압축 해제에 실패했습니다."
cp ./usr/lib64/libstdc++.so.6.0.25 $LIBPATH/ || error_exit "libstdc++ 라이브러리 파일 복사에 실패했습니다."
cd $LIBPATH
ln -sf libstdc++.so.6.0.25 libstdc++.so.6 || error_exit "libstdc++ 심볼릭 링크 생성에 실패했습니다."

echo "[작업 6] 설치 완료 후 정리 작업을 수행합니다."
cleanup_temp_files

echo "--------------------------------------------------------"
echo "🎉 모든 패치 및 정리가 성공적으로 완료되었습니다."
echo "새로운 SSH 세션에서 VS Code Server가 정상적으로 구동될 것입니다."
