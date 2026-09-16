#include <errno.h>
#include <seccomp.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <unistd.h>

static void fail_seccomp(const char *operation, int error) {
    errno = -error;
    perror(operation);
    exit(EXIT_FAILURE);
}

int main(int argc, char *argv[]) {
    scmp_filter_ctx filter;
    int result;

    if (argc < 2) {
        fprintf(stderr, "Usage: %s COMMAND [ARG...]\\n", argv[0]);
        return EXIT_FAILURE;
    }

    /* A process without CAP_SYS_ADMIN must opt out of gaining privileges. */
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) == -1) {
        perror("prctl(PR_SET_NO_NEW_PRIVS)");
        return EXIT_FAILURE;
    }

    /* Permit normal service operation, but deny one syscall for the demo. */
    filter = seccomp_init(SCMP_ACT_ALLOW);
    if (filter == NULL) {
        fputs("seccomp_init: could not create filter\\n", stderr);
        return EXIT_FAILURE;
    }

    result = seccomp_rule_add(filter, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(getppid), 0);
    if (result < 0) {
        seccomp_release(filter);
        fail_seccomp("seccomp_rule_add(getppid)", result);
    }

    result = seccomp_load(filter);
    seccomp_release(filter);
    if (result < 0) {
        fail_seccomp("seccomp_load", result);
    }

    execvp(argv[1], &argv[1]);
    perror("execvp");
    return EXIT_FAILURE;
}
