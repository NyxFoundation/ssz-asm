#include "ssz_asm.h"
#include "Platform.h"
#include "Abi.h"

typedef unsigned char U8;
typedef unsigned long U64;
typedef long I64;

#define DECLARE(name) \
  extern I64 name##_serialize(const ssz_value *, U8 *, U64); \
  extern I64 name##_deserialize(const U8 *, U64, ssz_value *, ssz_arena *); \
  extern I64 name##_validate(const ssz_value *)

DECLARE(u16); DECLARE(bytes); DECLARE(bits); DECLARE(lbytes);
DECLARE(empty_bytes); DECLARE(empty_list);
DECLARE(huge_bytes); DECLARE(huge_list); DECLARE(huge_element);

extern void *ssz_copy(void *, const void *, U64);
extern void *ssz_zero(void *, U64);
extern void *ssz_alloc(ssz_arena *, U64);
extern U64 ssz_read_u32(const U8 *);
extern void ssz_write_u32(U8 *, U64);

static U8 arena_buffer[16384] __attribute__((aligned(8)));
static U8 output[8192];
static U64 checks;

static void write_text(const char *s, U64 n) {
  syscall3(SYS_WRITE, 1, s, n);
}

__attribute__((noreturn)) static void fail(const char *s, U64 n) {
  write_text(s, n);
  syscall3(SYS_EXIT, 1, 0, 0);
  __builtin_unreachable();
}

#define CHECK(expr) do { \
  ++checks; \
  if (!(expr)) fail("FAIL: " #expr "\n", sizeof("FAIL: " #expr "\n") - 1); \
} while (0)

static int equal(const void *a, const void *b, U64 n) {
  const U8 *x = a, *y = b;
  for (U64 i = 0; i < n; ++i) if (x[i] != y[i]) return 0;
  return 1;
}

static ssz_arena arena(void) {
  ssz_arena result = {arena_buffer, sizeof(arena_buffer)};
  return result;
}

static void runtime(void) {
  U8 data[16] = {0};
  U8 src[] = {1, 2, 3};
  CHECK(ssz_copy(0, 0, 0) == 0);
  CHECK(ssz_zero(0, 0) == 0);
  CHECK(ssz_copy(data, src, 3) == data && equal(data, src, 3));
  CHECK(ssz_zero(data, 3) == data && data[0] == 0 && data[2] == 0);
  ssz_write_u32(data + 1, 0xfedcba98UL);
  CHECK(ssz_read_u32(data + 1) == 0xfedcba98UL);
  ssz_arena a = arena();
  CHECK(ssz_alloc(&a, 1) == arena_buffer);
  CHECK(a.next == arena_buffer + 8 && a.remaining == sizeof(arena_buffer) - 8);
  ssz_arena before = a;
  CHECK(ssz_alloc(&a, ~0UL) == 0 && equal(&a, &before, sizeof(a)));
  CHECK(ssz_alloc(&a, sizeof(arena_buffer)) == 0 && equal(&a, &before, sizeof(a)));
  a.next = (void *)(~0UL - 7); a.remaining = 16; before = a;
  CHECK(ssz_alloc(&a, 8) == 0 && equal(&a, &before, sizeof(a)));
}

static void exhaustive_bit_delimiters(void) {
  for (U64 length = 0; length <= 16; ++length) {
    U8 data[2] = {0xff, 0xff};
    if (length < 8) data[0] = (1U << length) - 1;
    if (length > 8 && length < 16) data[1] = (1U << (length - 8)) - 1;
    ssz_value v = {data, length, 0}, decoded;
    U64 size = length / 8 + 1;
    CHECK(bits_serialize(&v, output, size) == (I64)size);
    ssz_arena a = arena();
    CHECK(bits_deserialize(output, size, &decoded, &a) == 0);
    CHECK(decoded.length == length && equal(decoded.data, data, (length + 7) / 8));
  }
  for (U64 last = 0; last < 256; ++last) {
    U8 data[2] = {0x5a, (U8)last}; ssz_value decoded;
    ssz_arena a = arena();
    I64 result = bits_deserialize(data, 2, &decoded, &a);
    if (!last) { CHECK(result == -1); continue; }
    CHECK(result == 0);
    CHECK(bits_serialize(&decoded, output, sizeof(output)) == 2);
    CHECK(equal(output, data, 2));
  }
}

static void boundaries(void) {
  U8 data[] = {1, 2}; ssz_value decoded;
  ssz_arena a = {arena_buffer, 0};
  CHECK(u16_deserialize(data, 2, &decoded, &a) == -2);
  a.next = (void *)(~0UL - 7); a.remaining = 32;
  CHECK(u16_deserialize(data, 2, &decoded, &a) == -3);
  a = arena(); CHECK(bytes_deserialize(data, 1UL << 32, &decoded, &a) == -3);
  ssz_value v = {data, 1UL << 32, 0};
  CHECK(huge_bytes_validate(&v) == 0);
  CHECK(huge_bytes_serialize(&v, output, sizeof(output)) == -3);
  CHECK(huge_bytes_deserialize(data, 1UL << 32, &decoded, &a) == -3);
  v.data = 0; v.length = 0;
  CHECK(huge_list_serialize(&v, 0, 0) == 0);
  CHECK(huge_element_serialize(&v, 0, 0) == 0);
  CHECK(huge_element_deserialize(0, 0, &decoded, &a) == 0);
  CHECK(empty_list_serialize(&v, 0, 0) == 0);
  CHECK(empty_bytes_serialize(&v, 0, 0) == 0);
  CHECK(empty_bytes_deserialize(0, 0, &decoded, &a) == 0 && decoded.data == 0);
  CHECK(u16_serialize(0, output, sizeof(output)) == -1);
  CHECK(bytes_deserialize(0, 1, &decoded, &a) == -1);
  CHECK(bytes_deserialize((void *)(~0UL - 1), 4, &decoded, &a) == -3);
}

static void allocation_boundaries(void) {
  U8 input[] = {4, 0, 0, 0, 42}; ssz_value decoded;
  for (U64 n = 0; n < 32; ++n) {
    ssz_arena a = {arena_buffer, n};
    CHECK(lbytes_deserialize(input, 5, &decoded, &a) == -2);
  }
  ssz_arena a = {arena_buffer, 32};
  CHECK(lbytes_deserialize(input, 5, &decoded, &a) == 0 && a.remaining == 0);
  CHECK(decoded.length == 1 && ((const ssz_value *)decoded.data)->length == 1);
  a.next = arena_buffer + 1; a.remaining = 16;
  ssz_arena before = a;
  CHECK(ssz_alloc(&a, 1) == 0 && equal(&a, &before, sizeof(a)));
  U8 too_many[] = {20, 0, 0, 0, 20, 0, 0, 0, 20, 0, 0, 0,
    20, 0, 0, 0, 20, 0, 0, 0};
  a = arena(); CHECK(lbytes_deserialize(too_many, 20, &decoded, &a) == -1);
  CHECK(a.next == arena_buffer);
}

static void abi(void) {
  ABI_SEED();
  U8 data[] = {1, 2}; ssz_value v = {data, 2, 0}, decoded;
  ABI_BARRIER();
  CHECK(u16_serialize(&v, output, 2) == 2);
  ssz_arena a = arena(); CHECK(u16_deserialize(output, 2, &decoded, &a) == 0);
  ABI_BARRIER();
  CHECK(ABI_INTACT);
}

static void report_checks(void) {
  char digits[24]; U64 n = checks, i = sizeof(digits);
  do { digits[--i] = '0' + n % 10; n /= 10; } while (n);
  write_text(digits + i, sizeof(digits) - i);
  write_text(" codec checks passed\n", sizeof(" codec checks passed\n") - 1);
}

int test_main(void) {
  runtime(); boundaries(); exhaustive_bit_delimiters();
  allocation_boundaries(); abi(); report_checks();
  return 0;
}
