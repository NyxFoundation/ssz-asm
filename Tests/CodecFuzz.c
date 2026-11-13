#include "ssz_asm.h"

typedef int64_t (*Encode)(const ssz_value *, uint8_t *, uint64_t);
typedef int64_t (*Decode)(const uint8_t *, uint64_t, ssz_value *, ssz_arena *);
typedef struct { Encode encode; Decode decode; } Operations;
#include "fuzz_cases.h"

static uint8_t storage[1048576] __attribute__((aligned(8)));
static uint8_t input[4096], output[4096];

static int64_t read_bytes(void *data, uint64_t length) {
    register uint64_t a0 __asm__("a0") = 0;
    register void *a1 __asm__("a1") = data;
    register uint64_t a2 __asm__("a2") = length;
    register uint64_t a7 __asm__("a7") = 63;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return (int64_t)a0;
}

static int read_exact(uint8_t *data, uint64_t length) {
    uint64_t offset = 0;
    while (offset < length) {
        int64_t count = read_bytes(data + offset, length - offset);
        if (count <= 0) return 0;
        offset += (uint64_t)count;
    }
    return 1;
}

static void report(uint8_t result) {
    register uint64_t a0 __asm__("a0") = 1;
    register const uint8_t *a1 __asm__("a1") = &result;
    register uint64_t a2 __asm__("a2") = 1;
    register uint64_t a7 __asm__("a7") = 64;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
}

static uint32_t read32(const uint8_t *data) {
    return (uint32_t)data[0] | ((uint32_t)data[1] << 8) |
           ((uint32_t)data[2] << 16) | ((uint32_t)data[3] << 24);
}

static uint8_t check(const Operations *ops, uint64_t length) {
    ssz_value decoded;
    ssz_arena arena = {storage, sizeof(storage)};
    if (ops->decode(input, length, &decoded, &arena) < 0) return 1;
    int64_t size = ops->encode(&decoded, output, sizeof(output));
    if (size != (int64_t)length) return 2;
    for (uint64_t i = 0; i < length; ++i)
        if (output[i] != input[i]) return 2;
    return 0;
}

static int run(void) {
    uint8_t header[8];
    while (read_exact(header, sizeof(header))) {
        uint64_t index = read32(header), length = read32(header + 4);
        if (index >= sizeof(operations) / sizeof(operations[0]) || length > sizeof(input))
            return 1;
        if (!read_exact(input, length)) return 1;
        report(check(&operations[index], length));
    }
    return 0;
}

void _start(void) {
    register uint64_t a0 __asm__("a0") = (uint64_t)run();
    register uint64_t a7 __asm__("a7") = 93;
    __asm__ volatile("ecall" : : "r"(a0), "r"(a7) : "memory");
    __builtin_unreachable();
}
