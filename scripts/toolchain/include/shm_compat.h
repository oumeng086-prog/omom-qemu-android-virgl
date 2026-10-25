#ifndef __SHM_COMPAT_H__
#define __SHM_COMPAT_H__
#include <sys/types.h>
#ifdef __cplusplus
extern "C" {
#endif
int shm_open(const char *name, int oflag, mode_t mode);
int shm_unlink(const char *name);
#ifdef __cplusplus
}
#endif
#endif
