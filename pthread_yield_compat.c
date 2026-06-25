#include <sched.h>

// glibc >= 2.34 removed pthread_yield. Older VCS releases (2018)
// link against it. This shim provides the missing symbol.
int pthread_yield(void) {
    return sched_yield();
}
