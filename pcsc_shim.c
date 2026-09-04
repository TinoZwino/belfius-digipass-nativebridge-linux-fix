#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <unistd.h>
#include <stdarg.h>
#include <stdint.h>
#include <fcntl.h>

#define SCARD_S_SUCCESS             0x00000000
#define SCARD_E_INSUFFICIENT_BUFFER 0x80100008
#define SCARD_E_PROTO_MISMATCH      0x8010000F
#define SCARD_PROTOCOL_T0           0x00000001
#define SCARD_PROTOCOL_T1           0x00000002
#define SCARD_PROTOCOL_Tx           (SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1)
#define SCARD_ATTR_ATR_STRING       0x00090303
#define SCARD_AUTOALLOCATE_32       0xFFFFFFFFUL
#define SCARD_AUTOALLOCATE_64       ((unsigned long)-1)

/* Debugging disabled by default to prevent leaking smartcard metadata */
static int debug_enabled = 0;
static FILE *log_fp = NULL;
static void *pcsc_handle = NULL;

static void shim_log(const char *fmt, ...) {
    if (!debug_enabled) return;
    va_list args;
    va_start(args, fmt);
    if (!log_fp) {
        const char *log_path = getenv("PCSC_SHIM_LOG");
        if (log_path && log_path[0] != '\0') {
            /* Open custom log file securely (O_NOFOLLOW prevents symlink attacks) */
            int fd = open(log_path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0600);
            if (fd >= 0) {
                log_fp = fdopen(fd, "a");
            }
        }
        /* Default to stderr so systemd journal securely captures logs without world-readable /tmp files */
        if (!log_fp) log_fp = stderr;
    }
    fprintf(log_fp, "[PCSC_SHIM pid=%d] ", getpid());
    vfprintf(log_fp, fmt, args);
    fprintf(log_fp, "\n");
    fflush(log_fp);
    va_end(args);
}

/* Thread-safe initialization run at library load time */
__attribute__((constructor)) static void shim_init(void) {
    const char *dbg = getenv("PCSC_SHIM_DEBUG");
    if (dbg && (strcmp(dbg, "1") == 0 || strcasecmp(dbg, "true") == 0)) {
        debug_enabled = 1;
    }

    pcsc_handle = dlopen("libpcsclite.so.1", RTLD_LAZY | RTLD_GLOBAL);
    if (!pcsc_handle) {
        fprintf(stderr, "[PCSC_SHIM] ERROR: Failed to load libpcsclite.so.1: %s\n", dlerror());
    } else {
        shim_log("Initialized PC/SC Wine shim for process %d", getpid());
    }
}

__attribute__((destructor)) static void shim_fini(void) {
    if (log_fp && log_fp != stderr && log_fp != stdout) {
        fclose(log_fp);
        log_fp = NULL;
    }
}

static void *get_real(const char *name) {
    if (!pcsc_handle) {
        pcsc_handle = dlopen("libpcsclite.so.1", RTLD_LAZY | RTLD_GLOBAL);
        if (!pcsc_handle) return NULL;
    }
    return dlsym(pcsc_handle, name);
}

long SCardEstablishContext(unsigned long dwScope, const void *pv1, const void *pv2, unsigned long *phContext) {
    long (*real_func)(unsigned long, const void *, const void *, unsigned long *) = get_real("SCardEstablishContext");
    if (!real_func) return 0x80100014;
    long ret = real_func(dwScope, pv1, pv2, phContext);
    shim_log("SCardEstablishContext(scope=%lu) -> ret=%#lx, handle=%lu", dwScope, ret, phContext ? *phContext : 0);
    return ret;
}

long SCardReleaseContext(unsigned long hContext) {
    long (*real_func)(unsigned long) = get_real("SCardReleaseContext");
    if (!real_func) return 0x80100014;
    long ret = real_func(hContext);
    shim_log("SCardReleaseContext(hContext=%lu) -> ret=%#lx", hContext, ret);
    return ret;
}

long SCardListReaders(unsigned long hContext, const char *mszGroups, char *mszReaders, unsigned long *pcchReaders) {
    long (*real_func)(unsigned long, const char *, char *, unsigned long *) = get_real("SCardListReaders");
    if (!real_func) return 0x80100014;
    long ret = real_func(hContext, mszGroups, mszReaders, pcchReaders);
    shim_log("SCardListReaders(hContext=%lu, pcchReaders=%lu) -> ret=%#lx", hContext, pcchReaders ? *pcchReaders : 0, ret);
    if (ret == SCARD_S_SUCCESS && mszReaders && pcchReaders && *pcchReaders > 0) {
        shim_log("  readers found: %s", mszReaders);
    }
    return ret;
}

long SCardGetStatusChange(unsigned long hContext, unsigned long dwTimeout, void *rgReaderStates, unsigned long cReaders) {
    long (*real_func)(unsigned long, unsigned long, void *, unsigned long) = get_real("SCardGetStatusChange");
    if (!real_func) return 0x80100014;
    long ret = real_func(hContext, dwTimeout, rgReaderStates, cReaders);
    shim_log("SCardGetStatusChange(hContext=%lu, timeout=%lu, count=%lu) -> ret=%#lx", hContext, dwTimeout, cReaders, ret);
    return ret;
}

long SCardConnect(unsigned long hContext, const char *szReader, unsigned long dwShareMode, unsigned long dwPreferredProtocols, unsigned long *phCard, unsigned long *pdwActiveProtocol) {
    long (*real_func)(unsigned long, const char *, unsigned long, unsigned long, unsigned long *, unsigned long *) = get_real("SCardConnect");
    if (!real_func) return 0x80100014;

    shim_log("SCardConnect(reader='%s', share=%lu, prefProto=%lu)",
             szReader ? szReader : "(null)", dwShareMode, dwPreferredProtocols);
    long ret = real_func(hContext, szReader, dwShareMode, dwPreferredProtocols, phCard, pdwActiveProtocol);
    if (ret == SCARD_E_PROTO_MISMATCH && (dwPreferredProtocols & SCARD_PROTOCOL_T0)) {
        shim_log("  SCardConnect PROTO_MISMATCH; retrying with T=0 only");
        ret = real_func(hContext, szReader, dwShareMode, SCARD_PROTOCOL_T0, phCard, pdwActiveProtocol);
    }
    shim_log("SCardConnect result: ret=%#lx, card=%lu, activeProto=%lu",
             ret, phCard ? *phCard : 0, pdwActiveProtocol ? *pdwActiveProtocol : 0);
    return ret;
}

long SCardGetAttrib(long hCard, unsigned long dwAttrId, unsigned char *pbAttr, unsigned long *pcbAttrLen) {
    long (*real_func)(long, unsigned long, unsigned char *, unsigned long *) = get_real("SCardGetAttrib");
    if (!real_func) return 0x80100014;

    unsigned long in_len = pcbAttrLen ? *pcbAttrLen : 0;
    int was_autoallocate = 0;

    /*
     * ROOT CAUSE FIX:
     * Wine's 64-bit winscard.c zero-extends the 32-bit SCARD_AUTOALLOCATE (0xFFFFFFFF)
     * to 64-bit 0x00000000FFFFFFFF.
     * However, 64-bit Linux pcsc-lite defines SCARD_AUTOALLOCATE as (unsigned long)-1
     * (0xFFFFFFFFFFFFFFFF).
     * We translate 0xFFFFFFFF to (unsigned long)-1 so pcsc-lite allocates the ATR buffer!
     */
    if (pcbAttrLen && *pcbAttrLen == SCARD_AUTOALLOCATE_32) {
        was_autoallocate = 1;
        *pcbAttrLen = SCARD_AUTOALLOCATE_64;
        shim_log("SCardGetAttrib: Fixed SCARD_AUTOALLOCATE (0xffffffff -> -1)");
    }

    long ret = real_func(hCard, dwAttrId, pbAttr, pcbAttrLen);
    shim_log("SCardGetAttrib(hCard=%ld, attrId=%#lx, in_len=%#lx) -> ret=%#lx, out_len=%lu",
             hCard, dwAttrId, in_len, ret, pcbAttrLen ? *pcbAttrLen : 0);
    if (ret == SCARD_S_SUCCESS && was_autoallocate && pbAttr && *(void **)pbAttr) {
        shim_log("  autoallocated buffer ptr=%p", *(void **)pbAttr);
    }
    return ret;
}

long SCardFreeMemory(unsigned long hContext, const void *pvMem) {
    long (*real_func)(unsigned long, const void *) = get_real("SCardFreeMemory");
    if (!real_func) return 0x80100014;
    long ret = real_func(hContext, pvMem);
    shim_log("SCardFreeMemory(hContext=%lu, ptr=%p) -> ret=%#lx", hContext, pvMem, ret);
    return ret;
}
