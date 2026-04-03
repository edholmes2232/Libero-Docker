#!/bin/bash
set -e

echo "Using custom entrypoint"

# =============================================================================
# Installation paths
# =============================================================================
export SC_INSTALL_DIR=/usr/local/microchip/SoftConsole-v2022.2-RISC-V-747
export LIBERO_INSTALL_DIR=/usr/local/microchip/Libero_SoC_2025.2
export LICENSE_DAEMON_DIR=$LIBERO_INSTALL_DIR/LicenseDaemons
export LICENSE_FILE=/usr/local/microchip/license

# =============================================================================
# SoftConsole
# =============================================================================
export PATH=$PATH:$SC_INSTALL_DIR/riscv-unknown-elf-gcc/bin
export FPGENPROG=$LIBERO_INSTALL_DIR/Libero_SoC/Designer/bin64/fpgenprog

# =============================================================================
# Libero
# =============================================================================
export PATH=$PATH:$LIBERO_INSTALL_DIR/Libero_SoC/Designer/bin:$LIBERO_INSTALL_DIR/Libero_SoC/Designer/bin64
export PATH=$PATH:$LIBERO_INSTALL_DIR/Libero_SoC/Synplify_Pro/bin
export PATH=$PATH:$LIBERO_INSTALL_DIR/Libero_SoC/ModelSim_Pro/linuxacoem
export LOCALE=C
export LD_LIBRARY_PATH=/usr/lib/i386-linux-gnu:${LD_LIBRARY_PATH:-}

# =============================================================================
# License
# =============================================================================
export LM_LICENSE_FILE=1702@localhost
export SNPSLMD_LICENSE_FILE=1702@localhost

# Create a non-root user to run the license daemon safely
# (FlexLM vendor daemons famously crash or fail to write lock files if run as root)
if ! id "flexlm" &>/dev/null; then
    useradd -r -s /bin/false flexlm
fi

# Ensure temp directories and logs are writable by the flexlm user
# (Ubuntu 22.04 doesn't have /usr/tmp, so we symlink it to /tmp)
if [ ! -d "/usr/tmp" ]; then
    ln -s /tmp /usr/tmp
fi
mkdir -p /tmp/.flexlm /var/log/microchip /var/tmp
chmod 1777 /tmp/.flexlm /var/tmp /tmp
chown -R flexlm:flexlm /var/log/microchip
touch /var/log/microchip/lmgrd.log
chown flexlm:flexlm /var/log/microchip/lmgrd.log

# =============================================================================
# snpslmd overlayfs AND Docker detection LD_PRELOAD hack
# =============================================================================
if [ ! -f "$LICENSE_DAEMON_DIR/snpslmd-hack.so" ]; then
    echo "[entrypoint] Compiling LD_PRELOAD hack for snpslmd..."
    
    if ! command -v gcc &> /dev/null; then
        echo "[entrypoint] installing gcc..."
        apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -yqq gcc > /dev/null
    fi
    
    # Generate a pristine, legitimate-looking cgroup file without docker references
    echo "0::/user.slice/user-1000.slice/session-2.scope" > /usr/tmp/fake_cgroup
    
    cat << 'EOF' > /tmp/snpslmd-hack.c
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <dirent.h>
#include <dlfcn.h>
#include <string.h>
#include <fcntl.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <errno.h>

static int is_root = 0;
static int d_ino = -1;

static DIR *(*orig_opendir)(const char *name);
static int (*orig_closedir)(DIR *dirp);
static struct dirent *(*orig_readdir)(DIR *dirp);

static int (*orig_open)(const char *pathname, int flags, ...);
static int (*orig_open64)(const char *pathname, int flags, ...);
static FILE *(*orig_fopen)(const char *pathname, const char *mode);
static FILE *(*orig_fopen64)(const char *pathname, const char *mode);
static int (*orig_access)(const char *pathname, int mode);
static int (*orig_stat)(const char *pathname, struct stat *statbuf);
static int (*orig_lstat)(const char *pathname, struct stat *statbuf);

int is_docker(const char *pathname) {
    if (!pathname) return 0;
    if (strstr(pathname, "docker") || strstr(pathname, "lxc")) return 1;
    return 0;
}

int is_cgroup(const char *pathname) {
    if (!pathname) return 0;
    if (strstr(pathname, "cgroup")) return 1;
    return 0;
}

int access(const char *pathname, int mode) {
    if (is_docker(pathname)) { errno = ENOENT; return -1; }
    if (!orig_access) orig_access = dlsym(RTLD_NEXT, "access");
    if (is_cgroup(pathname)) return orig_access("/usr/tmp/fake_cgroup", mode);
    return orig_access(pathname, mode);
}

int stat(const char *pathname, struct stat *statbuf) {
    if (is_docker(pathname)) { errno = ENOENT; return -1; }
    if (!orig_stat) orig_stat = dlsym(RTLD_NEXT, "stat");
    if (is_cgroup(pathname)) return orig_stat("/usr/tmp/fake_cgroup", statbuf);
    return orig_stat(pathname, statbuf);
}

int lstat(const char *pathname, struct stat *statbuf) {
    if (is_docker(pathname)) { errno = ENOENT; return -1; }
    if (!orig_lstat) orig_lstat = dlsym(RTLD_NEXT, "lstat");
    if (is_cgroup(pathname)) return orig_lstat("/usr/tmp/fake_cgroup", statbuf);
    return orig_lstat(pathname, statbuf);
}

int open(const char *pathname, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args; va_start(args, flags); mode = va_arg(args, mode_t); va_end(args);
    }
    if (is_docker(pathname)) { errno = ENOENT; return -1; }
    if (!orig_open) orig_open = dlsym(RTLD_NEXT, "open");
    if (is_cgroup(pathname)) return orig_open("/usr/tmp/fake_cgroup", flags, mode);
    return orig_open(pathname, flags, mode);
}

int open64(const char *pathname, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args; va_start(args, flags); mode = va_arg(args, mode_t); va_end(args);
    }
    if (is_docker(pathname)) { errno = ENOENT; return -1; }
    if (!orig_open64) orig_open64 = dlsym(RTLD_NEXT, "open64");
    if (is_cgroup(pathname)) return orig_open64("/usr/tmp/fake_cgroup", flags, mode);
    return orig_open64(pathname, flags, mode);
}

FILE *fopen(const char *pathname, const char *mode) {
    if (is_docker(pathname)) { errno = ENOENT; return NULL; }
    if (!orig_fopen) orig_fopen = dlsym(RTLD_NEXT, "fopen");
    if (is_cgroup(pathname)) return orig_fopen("/usr/tmp/fake_cgroup", mode);
    return orig_fopen(pathname, mode);
}

FILE *fopen64(const char *pathname, const char *mode) {
    if (is_docker(pathname)) { errno = ENOENT; return NULL; }
    if (!orig_fopen64) orig_fopen64 = dlsym(RTLD_NEXT, "fopen64");
    if (is_cgroup(pathname)) return orig_fopen64("/usr/tmp/fake_cgroup", mode);
    return orig_fopen64(pathname, mode);
}

DIR *opendir(const char *name) {
  if (strcmp(name, "/") == 0) is_root = 1;
  if (!orig_opendir) orig_opendir = dlsym(RTLD_NEXT, "opendir");
  return orig_opendir(name);
}

int closedir(DIR *dirp) {
  is_root = 0;
  if (!orig_closedir) orig_closedir = dlsym(RTLD_NEXT, "closedir");
  return orig_closedir(dirp);
}

struct dirent *readdir(DIR *dirp) {
  if (!orig_readdir) orig_readdir = dlsym(RTLD_NEXT, "readdir");
  struct dirent *r = orig_readdir(dirp);
  if (is_root && r) {
    if (strcmp(r->d_name, ".") == 0 || strcmp(r->d_name, "..") == 0) {
      r->d_ino = d_ino;
    }
  }
  return r;
}

static __attribute__((constructor)) void init_methods() {
  orig_opendir = dlsym(RTLD_NEXT, "opendir");
  orig_closedir = dlsym(RTLD_NEXT, "closedir");
  orig_readdir = dlsym(RTLD_NEXT, "readdir");
  DIR *d = orig_opendir("/");
  struct dirent *e = orig_readdir(d);
  while (e) {
    if (strcmp(e->d_name, ".") == 0) {
      d_ino = e->d_ino;
      break;
    }
    e = orig_readdir(d);
  }
  orig_closedir(d);
}
EOF

    gcc -ldl -shared -fPIC /tmp/snpslmd-hack.c -o "$LICENSE_DAEMON_DIR/snpslmd-hack.so"
    
    if [ ! -f "$LICENSE_DAEMON_DIR/snpslmd_bin" ]; then
        mv "$LICENSE_DAEMON_DIR/snpslmd" "$LICENSE_DAEMON_DIR/snpslmd_bin"
        
        # Install strace for debugging
        if ! command -v strace &> /dev/null; then
            echo "[entrypoint] installing strace..."
            apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -yqq strace > /dev/null
        fi

        cat << 'EOF' > "$LICENSE_DAEMON_DIR/snpslmd"
#!/bin/sh
export LD_PRELOAD=$LICENSE_DAEMON_DIR/snpslmd-hack.so
exec strace -f -e trace=open,openat,access,stat,lstat,readlink,statfs,fstatfs,getdents64 -o /tmp/snpslmd_trace.txt "$LICENSE_DAEMON_DIR/snpslmd_bin" "$@"
EOF
        sed -i "s|\$LICENSE_DAEMON_DIR|$LICENSE_DAEMON_DIR|g" "$LICENSE_DAEMON_DIR/snpslmd"
        chmod +x "$LICENSE_DAEMON_DIR/snpslmd"
    fi
fi

# Start license daemon in background as the non-root user
if [ -f "$LICENSE_FILE" ]; then
    echo "[entrypoint] Starting license daemon as 'flexlm' user..."
    su -s /bin/bash flexlm -c "$LICENSE_DAEMON_DIR/lmgrd -c $LICENSE_FILE -l /var/log/microchip/lmgrd.log" &
    # Wait a solid 6 seconds to let snpslmd fully initialize and crash
    sleep 8
    
    echo "================================================"
    echo "          SNPSLMD BACKGROUND TRACE DUMP         "
    echo "================================================"
    grep -E -v "localtime|zoneinfo|locale|\.so|libnss|host\.conf|ld\.so|resolv" /tmp/snpslmd_trace.txt | tail -n 80 2>/dev/null || true
    echo "================================================"
    
    echo "[entrypoint] License daemon started (log: /var/log/microchip/lmgrd.log)"
else
    echo "[entrypoint] WARNING: No license file at $LICENSE_FILE — daemon not started."
fi

# Hand off to user's command (bash, libero_soc, CI script, etc.)
exec "$@"
