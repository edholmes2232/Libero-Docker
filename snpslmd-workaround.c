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
