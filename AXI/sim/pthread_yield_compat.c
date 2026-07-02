// pthread_yield compatibility stub for glibc >= 2.34
// pthread_yield was removed; provide it as an alias for sched_yield

#include <sched.h>

int pthread_yield(void) {
    return sched_yield();
}
